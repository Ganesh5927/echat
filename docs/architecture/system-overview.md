# System overview

## Purpose

eChat is a privacy-first communication platform for secure person-to-person messaging. The central design principle is that the user device owns identity, private keys, plaintext, and local conversation state. The server owns transport capacity, routing, and temporary queueing; it does not become a trusted authority with access to conversation contents.

## Current implementation status

The repository contains the Phase 1 device identity foundation, Phase 2 authenticated session foundation, and Phase 3 local encrypted-text-message foundation. The relay, WebSocket delivery, chat UI, offline queue, message database, and ratchet are not implemented. The Phase 2/3 protocol composition is project-specific and unaudited; this repository does not claim production-ready secure messaging.

## Core trust model

The relay is treated as untrusted infrastructure. It may authenticate a transport connection, route packets, and hold encrypted queue items, but it must not be able to read message contents, session keys, attachments, or conversation history.

This means the protocol is intentionally built around:

- device-bound identities
- end-to-end encryption
- authenticated handshakes and session keys
- encrypted attachments
- signed or authenticated packets
- local-first encrypted storage
- offline retry semantics with idempotent message identifiers

## High-level architecture

```text
User device A
  ├─ Identity keypair
  ├─ Local encrypted storage
  ├─ Session state
  ├─ Outbox / queue
  └─ UI / messaging service
        │
        │ encrypted packets
        v
     Untrusted relay infrastructure
        │
        │ encrypted packets
        v
User device B
  ├─ Verify identity
  ├─ Decrypt locally
  ├─ Message validation
  └─ Display plaintext only on device
```

## Security principles

### Device ownership

Each device has a distinct cryptographic identity. A user may have multiple devices, but each one has its own identity keypair and its own session state. Private identity material never leaves the device.

### Minimal server knowledge

The server may know transport metadata such as:

- user account identifier
- device identifiers
- timestamps of packet arrival
- packet sizes
- relay routing information
- push notification metadata
- rate-limit signals

The server does not have the right to learn the plaintext message, attachment content, or session secrets.

### Local-first data ownership

Each client stores local conversations in encrypted storage. To the extent possible, the server stores only temporary encrypted relay packets and supporting metadata for delivery.

## Functional layers

### 1. UI layer

Flutter screens, user input, contact verification, chat list, security status, and settings.

### 2. Application service layer

Responsible for orchestrating messaging functions, local state updates, contact verification, offline queue, and session management.

### 3. Protocol layer

Defines message envelope format, session lifecycle, replay protection, identity verification, and decryption flow.

### 4. Cryptographic layer

Uses established, audited cryptographic primitives and mature libraries. No custom algorithms.

### 5. Storage layer

Keeps local encrypted conversation state, certificates, contacts, session records, and outbox data.

### 6. Transport layer

Handles authenticated transport (HTTPS/WebSocket), queueing, retries, acknowledgements, and future direct transport abstraction.

## MVP scope

The initial milestone is intentionally narrow:

- identity creation
- QR contact exchange
- contact verification
- secure 1-to-1 messaging
- offline delivery queue
- replay protection
- local encrypted storage
- device revocation
- basic blocking

The first delivery does not include groups, calls, or social features.

## Non-goals for MVP

- group messaging
- video or voice calls
- direct peer-to-peer mandatory transport
- multi-device full support
- public profile/social graph

These are deferred to later milestones after the protocol and security model are validated.

## Security assumptions

The design assumes:

- user devices are not fully compromised
- TLS is correctly configured for transport security
- cryptographic libraries are professionally reviewed
- the server is not trusted with plaintext data
- clients validate device identity before displaying messages

## Explicit limitations

If an endpoint device is fully compromised, the attacker may read plaintext messages displayed on that device or from local storage. eChat cannot prevent a compromised client from misbehaving. The security model depends on secure endpoint behavior and secure local key protection.

## Future architecture path

The protocol is designed to allow later support for:

- multi-device identities
- encrypted attachments
- direct/local transport
- secure group research
- voice/video protocols
- optional peer-to-peer communication

The design goal is to keep the application protocol transport-agnostic as far as practical.
