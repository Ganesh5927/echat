# Development roadmap

## Phase 1: device identity foundation (complete)

- on-device Ed25519 identity creation, storage, verification fingerprint, rotation, and deletion

## Phase 2: secure session foundation (complete)

- authenticated ephemeral X25519 session setup and HKDF-SHA256 session root
- identity-pinned handshake, lifecycle records, and replay checks

## Phase 3: message protocol and encrypted-message foundation (implemented, unaudited)

- versioned canonical JSON envelope with strict parsing
- AES-256-GCM encrypted text payloads and authenticated header fields
- directional per-message HKDF-SHA256 keys and per-session replay state
- no relay, UI, queue, persistent message database, or ratchet

## Phase 4: transport and untrusted relay foundation (implemented; tests pass)

- HTTPS packet transport and authenticated relay API
- bounded in-memory queue, expiry, idempotent submission, and acknowledgement
- relay stores and forwards opaque encrypted protocol bytes

Independent review of the session/message composition remains a release gate.

## Messaging Core: Phases 5-7 (implemented; focused tests pass)

- 1-to-1 integration of the Phase 3 message protocol with Phase 4 transport
- AES-GCM encrypted local message records behind an injected key-provider boundary
- encrypted outbox, reconnect retry using stable message IDs, inbound deduplication, and relay acknowledgements
- at-least-once delivery; exactly-once delivery is not claimed

## Later phases

- platform secure-key adapter and durable session/identity state
- Flutter chat UI and background synchronization
- attachments, groups, calls, multi-device, push notifications, and direct transport

## Release gates

V0.1 is not complete until the protocol and security tests prove that:

- the relay cannot decrypt payloads
- the client can verify session integrity
- replay and tampering are rejected
- local storage remains encrypted
- revocation state is enforced

The current messaging tests do not satisfy the independent protocol review, platform-key integration, persistent session-state, or production deployment gates.