# Key management

## Objective

The Phase 1 implementation enforces the requirement that private cryptographic material remains under device control. The implementation uses a secure, platform-backed private-key store plus public metadata in app preferences, and it explicitly avoids sending private key material to the backend or any relay service.

## Actual lifecycle in the current implementation

- First install: `IdentityService.createIdentity()` generates a new Ed25519 keypair.
- Persist: the private key is written to `FlutterSecureStorage` and the public identity is stored in app preferences only.
- Restart: `IdentityService.loadIdentity()` reads the private key from secure storage and validates the public identity fingerprint.
- Delete: `IdentityService.deleteIdentity()` removes the secure-key value and public metadata.
- Rotation: `IdentityService.rotateIdentity()` creates a new identity and replaces the current public identity record.
- Session setup: `SessionService` derives a 32-byte session root from ephemeral X25519 with HKDF-SHA256 and stores it only in `SecureSessionStore` secret material.
- Message use: the session service derives a directional 32-byte per-message key with HKDF-SHA256, lends it to one protocol callback, then destroys its owned key buffer.
- Message encryption: `MessageService` uses AES-256-GCM and clears owned plaintext byte buffers after use. The envelope contains no secret key material.

## Key classes

- identity private key
- identity public key
- per-device signing or authentication key
- session root keys
- message encryption keys
- message authentication keys
- recovery or re-verification metadata

## Key storage

Private keys are stored in platform secure storage, not in plaintext files or ordinary app-local storage.

The mobile session adapter stores the session root and pending ephemeral private material in `FlutterSecureStorage`. Public session metadata and replay counters are in `SharedPreferences`. Message keys are not persisted. This storage split and the unit tests do not constitute an audit or production approval of the custom protocol composition.

The client should use:

- iOS Keychain
- Android Keystore
- desktop OS secure storage where available

This is a required design constraint, not an optional convenience.

## Key rotation

Device key rotation occurs when:

- a device is re-established
- compromise is suspected
- the existing key is revoked
- the protocol requires a new epoch

Rotation must include:

- new key generation
- public key publication
- verification update
- explicit trust reevaluation
- migration of active sessions only when protocol state allows it

## Device revocation

The contact-trust service can locally revoke a device and retain a tombstone so that a QR rescan cannot silently restore trust. The messaging coordinator checks this state before sending, inbound processing, and acknowledgements. This revocation is not sent to the relay or other contacts, and existing low-level session records are not deleted automatically.

The client should eventually:

- mark the device invalid in local state
- notify peer devices of the revocation
- refuse new sessions with the revoked device
- avoid accepting already-issued packets from that device unless explicitly handled by policy

## Recovery tradeoffs

Recovery cannot be implemented by silently weakening cryptographic identity. Any recovery plan must document the tradeoffs and operational security implications. This includes the risk of key backup, escrow, recovery secrets, and social recovery models.

## Security rules

- never hardcode keys
- never log private keys
- never place session roots or message keys in transport envelopes
- derive message keys with distinct direction, session, message ID, sequence, and epoch context
- destroy callback-scoped message keys after each operation
- never store plaintext keys in source control or ordinary local storage
- never claim a secure system without actual key lifecycle enforcement
- fail closed on authentication or key validation failure
