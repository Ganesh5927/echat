# Security testing plan

## Mandatory testing requirements

Security tests are mandatory before release. The project must not treat security as an afterthought.

## Cryptographic and protocol tests

The protocol test suite must include:

- key generation
- session establishment
- encryption and decryption
- authentication failure
- tampered ciphertext
- replay attack
- duplicate message
- out-of-order message
- wrong recipient
- invalid identity
- key change
- revoked device
- reconnect
- offline delivery

## Integration tests

The integration suite must validate:

- A -> Relay -> B flow
- relay receives ciphertext only
- relay cannot decrypt payloads
- B can decrypt and validate payloads
- tampering fails detection
- replay fails detection

## Security test examples

### Relay opacity test

The in-process relay integration test verifies that the request uses only the transport packet schema and contains no plaintext, private-key, session-key, local-storage-key, or test-credential marker. The relay has only an in-memory queue; this is not a database-compromise test or a claim about a deployed service.

### Network attack test

A test must validate:

- A sends encrypted traffic
- a network attacker modifies the traffic
- relay and recipient detect the modification
- authentication fails as expected
- deployed TLS is correctly configured and validated (not yet tested)

## Release gates

No release should proceed without passing:

- protocol unit tests
- security regression tests
- integration tests for relay flow
- attack simulation tests
- local storage protection checks
- key lifecycle validation

## Phase 3 local tests

The Phase 3 protocol package tests exercise two local devices and cover AES-GCM round trips, ciphertext/tag/header tampering, recipient/session binding, message-key separation, nonce uniqueness, replay, retries, concurrent sends/receives, malformed and noncanonical packets, and secret/plaintext exclusion. These tests do not provide independent protocol review and are not release approval.

## Messaging Core tests

Messaging Core tests cover encrypted file-store round trips and wrong-key rejection; offline queueing and reconnect with the same message ID and serialized ciphertext; incoming duplicate delivery after a lost acknowledgement; tampering without local persistence or relay acknowledgement; and an in-process HTTPS/relay end-to-end flow that checks the submitted body contains no message plaintext or key fields. They do not validate platform key-provider integration, durable session state across process restart, deployed TLS, cross-process storage locking, background sync, or production relay persistence.

## Trust and device-security tests

Identity tests cover exact public-only QR fields, public-key fingerprint validation, unverified and verified states, changed-key detection, explicit candidate re-verification, and revoked tombstones. Storage tests confirm encrypted trust-state persistence across reconstruction and failure with the wrong key. Messaging tests confirm unverified, changed-key/stale-session, and revoked peers cannot send or be acknowledged. These tests do not provide QR UI, human fingerprint comparison, remote revocation propagation, or protection from direct use of the lower-level session/protocol APIs.

## Mobile application tests

Mobile tests cover dependency composition with injected secure-value storage, key placement outside SharedPreferences, navigation among Contacts/Conversations/Identity, public-payload contact trust display, blocked pending session state, and offline pending-message rendering/retry using the same message ID. These use in-memory transport and record backends; they do not validate platform-specific secure storage, a camera scanner, deployed relay authentication, or network delivery for the session handshake.

## Security Invariants

Implemented invariants and regression coverage:

1. The relay interface has no message decryption key or decryption operation.
2. Private identity keys remain within the originating device; QR and relay schemas contain public identity data only.
3. Session roots and per-message keys are not transport or relay fields.
4. The Messaging Core submits ciphertext packets, never message plaintext; the relay itself treats packet bytes as opaque and cannot validate client encryption.
5. Plaintext is returned only after AEAD authentication; authenticated plaintext is persisted locally before replay state commits.
6. Duplicate IDs and stale sequences are rejected; valid sequence gaps remain accepted.
7. Contact verification, key-change acceptance, and revocation are explicit local trust-state transitions.
8. Revocation tombstones survive encrypted-store reconstruction; rescanning cannot clear them.
9. Outbox retry reuses the same serialized encrypted packet and message ID; delivery remains at least once, not exactly once.
10. Malformed data, authentication failures, wrong recipients, changed/revoked trust, and storage-key failures fail closed.

The test suite is local/in-process and does not establish platform integration, production deployment, or resistance to endpoint compromise.

## Documentation requirement

All security tests must be tied to a documented threat and a specific expected security property.
