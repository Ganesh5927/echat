# Local storage security

## Implementation in Phase 1

The application stores the private key in platform-secure storage and keeps public metadata separate from the cryptographic identity. The implementation is intentionally minimal and follows the design boundary: sensitive identity material is never stored in `SharedPreferences` or plaintext files.

```text
Encrypted Local Database
  ├─ conversations
  ├─ contacts
  ├─ message records
  ├─ session state
  ├─ device records
  └─ outbox / pending messages

Platform Secure Key Storage
  ├─ identity private keys
  ├─ key wrapping metadata
  └─ local encryption keys
```

## Storage protections

The actual implementation uses:

- `flutter_secure_storage` for private key storage
- `SharedPreferences` for public identity/session metadata and UI state, not private key material
- strict separation between cryptographic identity and application preferences
- `FlutterSecureStorage` for session roots and pending ephemeral session private keys
- `SharedPreferences` for public session records and replay counters
- callback-scoped message keys in memory only; they are not persisted

The private key is never logged, never committed to source control, and never sent to the relay or backend.

Phase 3 envelopes contain ciphertext and an authentication tag, not the session root. Plaintext exists briefly for UTF-8 conversion and AEAD, then the owned byte buffer is cleared. Returned Dart strings cannot be reliably zeroized.

- plaintext private keys are forbidden
- local database encryption is required
- key material is stored in secure OS storage
- decryption keys are not exposed to app code in plaintext except in memory under controlled use
- metadata is minimized and not treated as trusted evidence of message truth

## Data classes

The client stores:

- decrypted local message state only after user device verification
- encrypted message payloads and metadata
- conversation indexes and local attachments metadata
- session records and authentication state
- outbox entries for offline queueing

## Secret handling

The app must not keep private cryptographic keys in:

- SharedPreferences
- plain JSON files
- unencrypted SQLite files
- application logs
- crash reports

## Deletion and retention

Deletion should be implemented using secure erase measures where the platform supports them. The design must not claim secure deletion in all cases; it should be documented as technical best effort rather than a guarantee.

## Threat model

This local design mitigates the risk of a stolen or extracted device state, but it cannot prevent a fully compromised device from reading the plaintext presented to the user or from extracting keys from memory while the device is running.
