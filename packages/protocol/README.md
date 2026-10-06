# Protocol package

This package implements the Phase 3 local message protocol foundation.

- `MessageEnvelope` and `TransportPacket` provide strict version-1 canonical JSON serialization and schema validation.
- `MessageService.sendEncryptedMessage` and `decryptIncomingMessage` use AES-256-GCM with authenticated envelope headers and callback-scoped message keys from `SessionService`.
- Receive replay state commits only after successful authentication and decryption.

The package does not implement transport, a relay, a queue, a message database, UI, attachments, groups, or a ratchet. Primitive operations use the mature `cryptography` library; the protocol composition is project-specific, unaudited, and not production-approved. See `docs/protocol/message-format.md` for the wire format and limitations.