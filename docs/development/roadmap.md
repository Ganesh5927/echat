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

## Phase 4: independent protocol review and transport design

- obtain independent review of the session and message protocol composition
- address review findings before transport integration
- then define relay packet submission, acknowledgements, and bounded queue semantics

## Later phases

- Flutter chat UI and local encrypted message history
- offline delivery, attachments, groups, calls, multi-device, and direct transport

## Release gates

V0.1 is not complete until the protocol and security tests prove that:

- the relay cannot decrypt payloads
- the client can verify session integrity
- replay and tampering are rejected
- local storage remains encrypted
- revocation state is enforced