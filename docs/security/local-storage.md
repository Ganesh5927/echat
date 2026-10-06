# Local storage security

## Current implementation

`packages/storage` provides `EncryptedMessageStore`, which encrypts each complete message record with AES-256-GCM before writing it through a backend. `FileEncryptedRecordBackend` stores only the encoded nonce, ciphertext, and authentication tag in files; the filename is derived from a hash of the message ID. The exact serialized E2E packet and local plaintext are both inside the encrypted record.

The encryption key is supplied by `LocalStorageKeyProvider`. The storage package does not create or persist the key, and the Flutter app does not yet connect this provider to platform secure storage. The existing identity and session test stores are in-memory implementations; durable identity/session storage is not part of this milestone.

`EncryptedContactTrustStore` uses the same AEAD boundary for contact keys, fingerprints, and trust/revocation states. Message and contact adapters require separate backend directories because each adapter expects to decrypt every record returned by its backend.

```text
Planned local encrypted database
  ├─ conversations
  ├─ contacts
  ├─ message records
  ├─ session state
  ├─ device records
  └─ outbox / pending messages

Required platform secure key storage (provider wiring pending)
  ├─ identity private keys
  ├─ key wrapping metadata
  └─ local encryption keys
```

## Storage protections

The implemented message store uses independent random-nonce AES-256-GCM encryption for records and fails closed when a record cannot be decrypted. A local encryption key is never written by the message store. The host application must provide a stable key from secure OS storage before using the file backend for real user data; an in-memory or hardcoded production key is not acceptable.

The relay receives only the Phase 3 serialized encrypted packet, not the local plaintext, local storage key, identity private key, or session secret. Message IDs, routing identifiers, packet size, and timing remain observable metadata.

Phase 3 envelopes contain ciphertext and an authentication tag, not the session root. Plaintext exists briefly for UTF-8 conversion and AEAD, then the owned byte buffer is cleared. Returned Dart strings cannot be reliably zeroized.

- plaintext private keys are forbidden
- local database encryption is required
- key material is stored in secure OS storage
- decryption keys are not exposed to app code in plaintext except in memory under controlled use
- metadata is minimized and not treated as trusted evidence of message truth

## Intended data classes

The client stores:

- decrypted local message state only after user device verification
- encrypted message payloads and metadata
- conversation indexes and local attachments metadata
- session records and authentication state
- outbox entries for offline queueing

## Secret handling

The app must not keep private cryptographic keys or the message-store encryption key in:

- SharedPreferences
- plain JSON files
- unencrypted SQLite files
- application logs
- crash reports

## Deletion and retention

The file backend supports logical record deletion but does not guarantee secure erase. Backups, filesystem journals, snapshots, and storage wear-leveling may retain prior bytes. The current local message records also have no automated expiration/retention cleanup.

## Threat model

This local design mitigates offline file disclosure only when the host supplies a well-protected key. It cannot prevent a fully compromised device from reading plaintext presented to the user or extracting keys from memory while the device is running. Plaintext Dart strings cannot be reliably zeroized.
