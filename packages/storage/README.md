# Storage package

`EncryptedMessageStore` encrypts each complete message record, including plaintext and the serialized end-to-end encrypted packet, with AES-256-GCM before passing it to an `EncryptedRecordBackend`. The file backend stores ciphertext records under SHA-256-derived filenames and uses temporary/backup files when replacing records. The memory backend is intended for tests and ephemeral use.

The store accepts a `LocalStorageKeyProvider`; it does not generate, persist, or wrap the key. The application must provide a stable key from platform secure storage. The current Flutter app does not yet wire that provider. Losing the key makes local records unavailable.

File counts, ciphertext sizes, and filesystem activity remain observable. File deletion is not guaranteed secure erasure, plaintext Dart strings cannot be reliably zeroized, and no database migration or cross-process locking layer is provided.
