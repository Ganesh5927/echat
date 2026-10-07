# Storage package

`EncryptedMessageStore`, `EncryptedContactTrustStore`, `EncryptedSessionRecordStore`, and `EncryptedProfileStore` encrypt their complete records with AES-256-GCM before passing them to an `EncryptedRecordBackend`. The file backend stores ciphertext records under SHA-256-derived filenames and uses temporary/backup files when replacing records. The memory backend is intended for tests and ephemeral use.

The local profile store holds only a validated display name and optional bounded avatar bytes. It does not interact with device identity or relay APIs.

The stores accept a `LocalStorageKeyProvider`; they do not generate, persist, or wrap the key. The application must provide a stable key from platform secure storage. Losing the key makes encrypted local records unavailable. Session secret bundles are stored separately through platform secure storage.

On startup, the mobile app migrates legacy plaintext session records from `SharedPreferences` by writing each encrypted record before removing its plaintext preference. A failed encrypted write leaves the legacy record in place for a later retry.

File counts, ciphertext sizes, and filesystem activity remain observable. File deletion is not guaranteed secure erasure, plaintext Dart strings cannot be reliably zeroized, and no database migration or cross-process locking layer is provided.
