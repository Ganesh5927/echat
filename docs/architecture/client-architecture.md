# Client architecture

## Client role

The client is the primary trust anchor. It generates identities, stores local encrypted conversation state, verifies contacts, establishes sessions, encrypts messages, and decrypts payloads before display.

## Flutter architecture

The Flutter app now boots through `MobileAppServices` and passes a `MessagingController` to the UI. Widgets render app-facing view models; they do not receive protocol envelopes, session secrets, storage backends, or relay packets.

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

- bootstrap / local identity creation
- Home navigation for Conversations, Contacts, and Identity
- public identity payload paste/import (camera QR scanning is not configured)
- contact detail, independently compared fingerprint confirmation, key re-verification, and local revocation
- conversation list and one-to-one message view with local history, pending/outbox state, sync, and trust/session status

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

The protocol package exposes high-level `sendEncryptedMessage` and `decryptIncomingMessage` operations. The UI-independent `echat_messaging` package composes those operations with `PacketTransport` and `EncryptedMessageStore`; `MessagingController` provides UI-safe contacts, conversations, message history, send, sync, and session-state APIs. The receiver persists authenticated plaintext before replay state commits, then acknowledges the relay packet. The protocol composition has not been independently audited.

`SessionService` can create, accept, and finalize its signed existing handshake. The app controller stages and parses those existing JSON messages behind a `SessionExchangeGateway`; the mobile composition currently injects an unavailable gateway. There is no supported network delivery of session-init/session-accept through the relay, so new sessions remain pending until the signed exchange is supplied through a future supported channel. The UI does not equate a button press or relay connection with an established session.

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

Message and contact-trust records use separate file-backend directories and AES-256-GCM per-record encryption. A random local storage key is created once and held through `FlutterSecureStorage`; identity private keys and session secret bundles also use secure storage. Public identity/session records remain in `SharedPreferences`. Durable session state is thus wired on mobile, but there is no migration, cross-process locking, or secure-erasure guarantee. A credential and HTTPS origin are required before relay transport is configured; none is hardcoded.

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
