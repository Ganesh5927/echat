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

### Server compromise test

A test must demonstrate that even if an attacker obtains the relay database, they obtain encrypted protocol data rather than plaintext conversations.

This must be executed with the actual implementation and documented as a real architectural result.

### Network attack test

A test must validate:

- A sends encrypted traffic
- a network attacker modifies the traffic
- relay and recipient detect the modification
- authentication fails as expected
- TLS is correctly configured and validated

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

## Documentation requirement

All security tests must be tied to a documented threat and a specific expected security property.
