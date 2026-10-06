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

## Documentation requirement

All security tests must be tied to a documented threat and a specific expected security property.
