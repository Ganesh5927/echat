# eChat

## Mission

eChat is a privacy-first communication platform designed around one principle: communication belongs to the communicating devices. Infrastructure transports encrypted traffic; it does not become a trusted authority that can read user conversations.

This repository is the foundational architecture and MVP plan for a secure 1-to-1 messaging product built with Flutter on the client side and a minimal, untrusted relay backend.

## Design priorities

1. Security
2. Correctness
3. Privacy
4. Reliability
5. Maintainability
6. Performance
7. Features

The project intentionally does not implement groups, calls, or social features in the initial milestone.

## Core security model

- Private identity keys remain on the device.
- Relay servers only handle encrypted packets and minimal routing metadata.
- Message plaintext is never stored on the server.
- Session keys are derived from authenticated key agreement and evolve over time.
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

## MVP scope

Version 0.1 contains only:

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
