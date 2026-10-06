# Message flow and sequence diagrams

## High-level flow

```text
Person A
  ↓ compose plaintext
  ↓ local encryption
  ↓ authenticated encrypted message
  ↓ ciphertext packet
  ↓ relay
  ↓ ciphertext packet
  ↓ Person B device
  ↓ verification
  ↓ decryption
  ↓ plaintext displayed locally
```

## Sequence diagram: first contact

```mermaid
sequenceDiagram
    participant A as Device A
    participant B as Device B
    participant R as Relay

    A->>B: Public identity QR / verification bundle
    B->>A: Public identity QR / verification bundle
    A->>A: Verify fingerprint
    B->>B: Verify fingerprint
    A->>R: Contact request / encrypted identity handshake
    R-->>B: Relay encrypted packet
    A->>B: Establish authenticated session
    B-->>A: Session confirmation
```

## Sequence diagram: session establishment

```mermaid
sequenceDiagram
    participant A as Device A
    participant B as Device B
    participant R as Relay

    A->>B: Hello / identity binding / ephemeral data
    B->>A: Identity verification / ephemeral response
    A->>A: Derive session key material
    B->>B: Derive session key material
    A->>R: Encrypted session setup packet
    R-->>B: Forward ciphertext
    B->>B: Validate authentication and transcript
    B-->>A: Session established
```

## Sequence diagram: normal message

```mermaid
sequenceDiagram
    participant A as Device A
    participant B as Device B
    participant R as Relay

    A->>A: Compose plaintext
    A->>A: Encrypt and authenticate
    A->>R: Send ciphertext packet
    R-->>B: Forward ciphertext packet
    B->>B: Verify authenticity and session state
    B->>B: Decrypt locally
    B-->>A: Ack / delivery status
```

## Sequence diagram: offline recipient

```mermaid
sequenceDiagram
    participant A as Device A
    participant B as Device B
    participant R as Relay

    A->>A: Encrypt message to outbox
    A->>R: Submit ciphertext packet
    R->>R: Queue packet
    B-->>R: Offline / unavailable
    R-->>A: Queue accepted
    B->>R: Reconnect
    R-->>B: Deliver queued ciphertext
    B->>B: Verify and decrypt
```

## Sequence diagram: reconnect

```mermaid
sequenceDiagram
    participant A as Device A
    participant B as Device B
    participant R as Relay

    B->>R: Reconnect / resume session
    A->>R: Send queued or new packets
    R-->>B: Deliver pending packets
    B->>B: Validate sequence and dedupe
    B-->>A: Ack and resume state
```

## Sequence diagram: key change

```mermaid
sequenceDiagram
    participant A as Device A
    participant B as Device B
    participant R as Relay

    A->>A: Detect key rotation or identity update
    A->>R: Encrypted key-change notification
    R-->>B: Forward notification
    B->>B: Validate new identity and sequence state
    B-->>A: Accept or reject new key state
```

## Sequence diagram: device revocation

```mermaid
sequenceDiagram
    participant A as Device A
    participant B as Device B
    participant R as Relay

    A->>R: Revoke device or report compromise
    R-->>B: Revocation notice
    B->>B: Mark device invalid
    B-->>A: Security warning / session invalidated
```

## Sequence diagram: replayed message

```mermaid
sequenceDiagram
    participant A as Device A
    participant B as Device B
    participant R as Relay

    A->>R: Message 002
    R-->>B: Deliver message 002
    B->>B: Accept
    A->>R: Message 002 duplicate
    R-->>B: Deliver duplicate
    B->>B: Detect duplicate via message ID / sequence state
    B-->>R: Reject as replay
```

## Sequence diagram: invalid message

```mermaid
sequenceDiagram
    participant A as Device A
    participant B as Device B
    participant R as Relay

    A->>R: Send tampered or invalid ciphertext
    R-->>B: Forward packet
    B->>B: Authentication tag fails
    B->>B: Reject message
    B-->>A: Security error / invalid message
```

## Message handling rules

- The receiver must validate message authentication before decryption.
- The receiver must reject duplicates and old replays.
- The receiver must not display plaintext for unauthenticated or invalid payloads.
- Out-of-order handling must be explicit and safe.
