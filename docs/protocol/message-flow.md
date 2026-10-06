# Message flow

## Implemented local message lifecycle

```text
Device A
  -> MessageService.sendEncryptedMessage
  -> SessionService reserves sequence and lends a one-use message key
  -> AES-256-GCM encrypts UTF-8 plaintext with canonical header AAD
  -> versioned envelope and separate transport metadata
  -> EncryptedMessageStore persists local plaintext and exact serialized packet
  -> outbox submits exact serialized bytes to HTTPS transport
  -> untrusted relay queues and forwards bytes without parsing the Phase 3 envelope
  -> Device B parses and validates canonical envelope
  -> session validates peer direction and replay state
  -> AES-256-GCM authenticates and decrypts
  -> authenticated plaintext is persisted locally before replay state commits
  -> Device B acknowledges the relay only after local persistence succeeds
```

The packages implement the message protocol, HTTPS/in-memory relay, encrypted file-backed message store, and a UI-independent messaging coordinator. The relay queue is still in memory; the local store needs a host-provided platform-secure key. No chat UI, WebSocket, background sync, or production deployment exists.

## Existing identity and session foundation

```mermaid
sequenceDiagram
    participant A as Device A
    participant B as Device B

    A->>B: session-init signed with Ed25519 identity
    B->>B: Verify expected pinned identity key
    B->>A: session-accept signed with Ed25519 identity
    A->>A: Verify response and matching session-key fingerprint
```

## Local transport exchange

```mermaid
sequenceDiagram
    participant A as Device A
    participant B as Device B
    participant T as HTTPS transport
    participant R as Untrusted relay

    A->>A: Reserve sequence, derive one-use key, encrypt and authenticate
    A->>T: Submit opaque serialized TransportPacket over HTTPS
    T->>R: POST /v1/packets
    R->>R: Validate routing wrapper and queue opaque bytes
    R-->>T: Return queued receipt
    B->>T: Poll GET /v1/packets over HTTPS
    T->>R: Authenticated fetch
    R-->>T: Return same opaque packet bytes
    T-->>B: Supply serialized Phase 3 packet
    B->>B: Parse, validate session/replay, authenticate and decrypt
    B->>T: POST acknowledgement after local acceptance
```

## Replay and retry behavior

```mermaid
sequenceDiagram
    participant A as Device A
    participant B as Device B

    A->>B: Original serialized packet
    B->>B: Authenticate, decrypt and commit message ID / sequence
    A->>B: Same serialized packet retried
    B->>B: Reject committed ID or stale sequence
```

The receiver holds a session lock across replay validation, key derivation, AEAD authentication/decryption, the authenticated persistence callback, and replay-state commit. Failed authentication or local persistence does not consume the message ID or sequence. Sequences must increase; gaps are permitted and out-of-order delivery is not. A retry resends the exact packet with the same message ID. Re-encrypting creates a new message ID, sequence, key, and nonce.

Relay acceptance marks an outgoing item submitted and removes it from the local outbox; it is not a recipient-delivery receipt. Incoming packets are delivered at least once. The recipient deduplicates a matching stored packet and retries its acknowledgement without decrypting it again. Exactly-once delivery is not claimed.

## Tampering behavior

The receiver rejects malformed, unknown-version, noncanonical, wrong-recipient, tampered, duplicate, and stale packets. An authentication failure returns a fixed protocol error and no plaintext. The local integration test exercises this route through an in-process Shelf handler and mocked HTTPS client; it is not a deployed network test.

## Deferred capabilities

Background recovery, persistent relay queues, key-change delivery, revocation delivery, attachments, groups, and multi-device handling are not implemented. Persistent identity/session state is also not wired, so decrypting after process restart is not yet supported. The message/session protocol composition is project-specific and has not been independently audited.