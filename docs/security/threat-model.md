# Threat model

## Assets

The system defines the following assets:

- Plaintext messages
- Ciphertext
- Identity private keys
- Identity public keys
- Session state
- Contacts
- Device information
- Message metadata
- Attachments
- Authentication state

## Threat actors

1. Malicious relay server
2. Database attacker
3. Network attacker
4. Man-in-the-middle attacker
5. Malicious client
6. Stolen device
7. Compromised device
8. Malicious contact
9. Replay attacker
10. Traffic-analysis observer

## Security goals

- Confidentiality
- Integrity
- Authentication
- Forward secrecy
- Replay protection
- Key compromise resilience
- Secure device identity
- Local key protection
- Metadata minimization
- Secure deletion where technically possible

## Threat analysis

### 1. Malicious relay server

The future relay may inspect packet metadata and ciphertext. Phase 3 locally encrypts text content with AES-256-GCM, but no relay exists yet. Device/session references, type, message ID, sequence, nonce, ciphertext size, tag, and optional transport hints remain visible in the packet.

### 2. Database attacker

No message database exists yet. A future database must contain ciphertext packets only and must not contain plaintext conversation history or private keys.

### 3. Network attacker

A passive or active network attacker should not be able to read message contents or alter ciphertext without detection. TLS and authenticated packet validation mitigate this risk.

### 4. Man-in-the-middle attacker

A MitM attacker cannot succeed if the session is authenticated and identity verification is enforced. The receiver must validate identity and message authentication before decryption.

### 5. Malicious client

A malicious client may misbehave, but it cannot read encrypted content that is not meant for it. This system expects authenticated sessions and device verification to constrain what a client can do.

### 6. Stolen device

A stolen device compromises local key material if the device is unlocked or the secure local storage is bypassed. Device revocation and secure local key storage reduce impact but do not eliminate this risk.

### 7. Compromised device

A fully compromised endpoint can read plaintext displayed locally, monitor keys in memory, or exfiltrate stored data. This is an unavoidable limitation of client trust.

### 8. Malicious contact

A malicious contact may send invalid content, social-engineer users, or attempt to exploit replay conditions. The system mitigates this with verification, authenticated sessions, recipient validation, and replay protection.

### 9. Replay attacker

A replay attacker re-sends prior valid packets to trigger duplicate processing. The protocol must detect duplicates via message IDs and session sequence state.

### 10. Traffic-analysis observer

An observer can infer timing, packet sizes, and connection metadata. eChat minimizes metadata but cannot claim complete elimination of traffic patterns.

## Explicit limitations

The following are unavoidable in a real system:

- if a device is fully compromised, the attacker may read plaintext shown by that device
- full anonymity is not guaranteed by the design unless proven with additional engineering and threat analysis
- metadata such as timing, packet size, and account identifiers may still reveal information
- local key protection depends on the platform security model and user device integrity

## Security goals and residual risk

The project must document both the goals and residual risk. Security is not claimed by adding a cryptographic library to the stack; it is only valid when the protocol, storage, validation, and operational controls are correct and tested.

Phase 3 uses mature cryptographic primitives from `cryptography`, but the eChat handshake, message-key derivation, and envelope composition are project-specific and have not been independently audited. This does not implement Double Ratchet, post-compromise security, per-message forward secrecy, relay integration, or a production message lifecycle. Passing unit tests does not make the messaging protocol production-approved.
