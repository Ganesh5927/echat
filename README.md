# eChat

## Mission

eChat is a privacy-first communication platform designed around one principle: communication belongs to the communicating devices. Infrastructure transports encrypted traffic; it does not become a trusted authority that can read user conversations.

This repository is the foundational architecture and MVP plan for a secure 1-to-1 messaging product built with Flutter on the client side and a minimal, untrusted relay backend.

## Current implementation

- Device identity, authenticated session establishment, and contact trust with verification, revocation, and identity-change handling.
- Versioned 1-to-1 encrypted messaging with replay protection, encrypted local message/contact/session records, a persisted outgoing queue, and stable-ID retries.
- HTTPS relay transport with public-device registration and signed device authentication. The relay stores opaque packets in a durable local queue and does not decrypt message content.
- Flutter client with first-run identity onboarding, Conversations, Contacts, Identity, Chat, Settings, and a local profile editor. Public identity QR display/copy, validated paste import, local contact names, and local conversation search are available.
- A local profile display name and optional avatar are encrypted in the app's local record store and are not published to the relay.

This is a development-stage implementation, not a production-approved messaging service. The project-specific protocol composition has not been independently audited. The mobile package has a generated Android host but no iOS host; the camera-based QR scanner, push notifications, and background synchronization are not implemented. Relay deployment requires an HTTPS endpoint, and the mobile app does not configure a session-exchange gateway by default. Temporary/in-memory mode can lose identity and local data on restart.

The Flutter mobile package now includes a Flutter-generated Android host with
application ID `com.echat.echat`. Android build requirements and commands are
documented in [apps/mobile/README.md](./apps/mobile/README.md). Development APK
release signing uses the generated debug key and is not suitable for store
distribution. Real relay use requires `ECHAT_RELAY_ORIGIN`; establishing
sessions between two devices additionally requires a configured
`SessionExchangeGateway` delivery path for the existing signed session-control
messages. The development relay files are plaintext at rest, and a supported
production relay deployment/composition is not yet provided.

## Product capability status

- **Implemented:** public identity QR rendering and clipboard export; strict identity payload import; local encrypted contact display names; contact fingerprint verification, re-verification, and revocation; local search over contacts and conversation summaries/recent previews; foreground synchronization; distinct relay connection, authentication, and authenticated states.
- **Partially implemented:** conversation search is not a full historical message index. Gallery avatar selection is implemented for the Android-hosted app; target-device interaction still needs validation.
- **Requires external infrastructure:** live relay use requires an HTTPS relay origin. Session exchange requires a configured exchange gateway. Remote push requires a provider/backend, platform credentials, and native configuration.
- **Not implemented:** camera QR scanning, operating-system notifications, and background synchronization. Settings identifies notifications as unavailable and sync as foreground-only; it does not claim these features are enabled.

## Design priorities

1. Security
2. Correctness
3. Privacy
4. Reliability
5. Maintainability
6. Performance
7. Features

The project intentionally does not implement groups, calls, or social features in the initial milestone.

## Target security model

- Private identity keys remain on the device.
- Relay servers only handle encrypted packets and minimal routing metadata.
- Message plaintext is never stored on the server.
- Session keys are derived from authenticated key agreement. Per-message keys are derived for Phase 3, but no ratchet or post-compromise security is implemented.
- Contact verification is based on cryptographic identity verification, not phone numbers.
- Local storage is encrypted and protected by platform secure storage.

## Repository structure

- apps/mobile - Flutter mobile client
- apps/desktop - desktop client shell
- packages/protocol - message and session protocol definitions
- packages/secure_core - cryptographic and security primitives
- packages/transport - transport abstraction layer
- packages/storage - encrypted local persistence
- packages/identity - device identity and verification logic
- server/gateway - API / gateway
- server/identity - identity publication and lookup
- server/relay - encrypted packet relay and queue
- server/delivery - delivery and acknowledgements
- server/abuse - rate limiting and abuse controls
- docs - architecture, protocol, security, privacy, setup guides
- tests - protocol, security, integration, client, server
- tools - build and automation utilities

## Planned MVP scope

The intended MVP includes:

- device identity creation
- public identity publication
- QR contact exchange
- contact verification
- secure session establishment
- 1-to-1 encrypted messaging
- local encrypted conversation storage
- relay server
- offline delivery queue
- message acknowledgements
- replay protection
- device removal and revocation
- basic block
- security information screen

## Documentation map

- docs/architecture/system-overview.md
- docs/architecture/client-architecture.md
- docs/architecture/server-architecture.md
- docs/architecture/trust-model.md
- docs/protocol/identity.md
- docs/protocol/session.md
- docs/protocol/message-format.md
- docs/protocol/message-flow.md
- docs/security/threat-model.md
- docs/security/key-management.md
- docs/security/local-storage.md
- docs/security/security-testing.md
- docs/privacy/metadata-analysis.md
- docs/privacy/privacy-model.md
- docs/development/setup.md

## Security status model

The application is expected to distinguish among:

- NOT VERIFIED
- VERIFIED
- IDENTITY CHANGED
- DEVICE REVOKED
- SECURITY ERROR

This status must reflect protocol state, not the existence of a cryptographic library in the codebase.

## Important constraints

- No private keys in source code.
- No plaintext messages on the server.
- No custom cryptographic primitives.
- No fake encryption shims.
- No security by obscurity.
- No claim of perfect anonymity or zero metadata without proof.

See the architecture and security documents for the detailed trust model, threat model, and protocol design.
