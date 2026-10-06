# Development roadmap

## Phase 1: architecture and protocol

- architecture documentation
- trust model
- threat model
- identity design
- session design
- message format
- replay and forward secrecy specification

## Phase 2: cryptographic core

- secure device identity module
- key generation and management
- session establishment
- message encryption and decryption
- replay detection
- security test suite

## Phase 3: relay backend

- envelope handling
- encrypted queue
- ack processing
- relay routing
- abuse controls
- minimal database design

## Phase 4: Flutter client

- identity onboarding screens
- contact verification flow
- secure session setup
- chat UI
- local encrypted storage
- offline sending and retries

## Phase 5: security hardening

- attack simulations
- vulnerability remediation
- protocol review
- security regression checks

## Phase 6: future expansions

- encrypted attachments
- multi-device support
- direct transport abstraction
- group messaging research
- voice and video architecture

## Release gates

V0.1 is not complete until the protocol and security tests prove that:

- the relay cannot decrypt payloads
- the client can verify session integrity
- replay and tampering are rejected
- local storage remains encrypted
- revocation state is enforced
