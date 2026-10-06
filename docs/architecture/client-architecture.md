# Client architecture

## Client role

The client is the primary trust anchor. It generates identities, stores local encrypted conversation state, verifies contacts, establishes sessions, encrypts messages, and decrypts payloads before display.

## Flutter architecture

The Flutter application should be organized by layer and responsibility rather than by screen alone.

```text
Flutter UI
  ├─ Screens / Widgets
  ├─ View models / controllers
  ├─ Services
  │   ├─ IdentityService
  │   ├─ SessionManager
  │   ├─ MessagingService
  │   ├─ ContactVerificationService
  │   ├─ StorageService
  │   └─ TransportClient
  └─ ProtocolAdapter
       └─ SecureCryptoAdapter
```

## Layer responsibilities

### UI layer

- Splash screen
- Create identity flow
- QR display and scanning flows
- home and contacts screens
- chat and conversation details screens
- security and privacy dashboards
- settings and device management screens

### Application services

- create and protect local device identity
- manage contacts and verification state
- send and receive encrypted packets
- serialize and store message state through encrypted local storage
- maintain and retry a durable local outbox after reconnect
- deduplicate inbound relay retries and acknowledge after authenticated local persistence
- report security status to the UI

### Protocol engine

- message envelope creation
- session key handling
- per-message key derivation and authenticated encryption
- replay detection
- decryption verification
- key rotation and device revocation steps

The protocol package exposes high-level `sendEncryptedMessage` and `decryptIncomingMessage` operations. The UI-independent `echat_messaging` package composes those operations with `PacketTransport` and `EncryptedMessageStore`; widgets do not access cipher or key primitives. The receiver persists authenticated plaintext before the protocol commits replay state, then acknowledges the relay packet. The protocol composition has not been independently audited.

### Secure crypto adapter

This module should abstract backend-appropriate crypto libraries rather than mixing cryptography with widget code. It is responsible for key generation, key agreement, message encryption, authentication, and key derivation.

## Local-first design

The client stores:

- conversations
- contacts
- message state
- device identity
- session state
- attachment references
- offline queue items

Message records and outbox entries are encrypted per record with AES-256-GCM before the file backend writes them. The encryption key is supplied through an injected provider. A platform secure-storage provider and durable identity/session adapters are not yet wired, so the current app does not yet meet the complete local-first persistence design.

## Security status model

The app must distinguish between protocol states, not just display encryption icons:

- NOT VERIFIED
- VERIFIED
- IDENTITY CHANGED
- DEVICE REVOKED
- SECURITY ERROR

This state is derived from actual protocol verification and device records, not from a boolean set in the UI.

## First-run experience

The first-run flow should be:

1. Create device identity
2. Generate private identity key on the device
3. Protect it in platform secure storage
4. Publish public identity
5. Show QR for verification
6. Route the user to Home

No phone number or other fundamental account identifier is required for the cryptographic identity.

## Important constraints

- Do not place encryption code directly inside widgets.
- Do not use shared preferences for private keys.
- Do not silently accept unauthenticated content.
- Do not show a “secure” label without matching protocol verification state.
