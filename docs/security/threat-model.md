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

The relay receives and queues opaque Phase 3 packets. AES-256-GCM protects text content, but device/session references, type, message ID, sequence, nonce, ciphertext size, tag, and optional transport hints remain visible. The relay also sees route IDs, packet IDs, expiry, queue timing, and connection metadata. Relay-side ciphertext-only behavior is tested in-process; no anonymity claim is made.

### 2. Database attacker

The relay queue is in-memory and volatile. Locally, message and contact-trust records can be encrypted with AES-GCM before file persistence. The host must supply and protect the local key; the contact-store adapter is not yet wired into the mobile application. File counts, sizes, and access patterns remain observable, and deletion is not guaranteed secure erasure.

### 3. Network attacker

A passive or active network attacker should not be able to read message contents or alter ciphertext without detection. TLS and authenticated packet validation mitigate this risk.

### 4. Man-in-the-middle attacker

A MitM may substitute public identity data before initial verification. QR parsing checks schema and key-fingerprint consistency, but users must compare fingerprints through a trusted channel and explicitly verify the contact. Changed keys block messaging pending explicit re-verification; old sessions remain pinned to the old key. The app does not yet provide the user-facing comparison/scanning flow.

### 5. Malicious client

A malicious client may misbehave, but it cannot read encrypted content that is not meant for it. This system expects authenticated sessions and device verification to constrain what a client can do.

### 6. Stolen device

A stolen device compromises local key material if the device is unlocked or the secure local storage is bypassed. Device revocation and secure local key storage reduce impact but do not eliminate this risk.

### 7. Compromised device

A fully compromised endpoint can read plaintext displayed locally, monitor keys in memory, or exfiltrate stored data. This is an unavoidable limitation of client trust.

### 8. Malicious contact

A malicious contact may send invalid content, social-engineer users, or attempt to exploit replay conditions. The system mitigates this with verification, authenticated sessions, recipient validation, and replay protection.

### 9. Revoked or changed contact device

Local revocation and changed-key states are enforced by the messaging coordinator before sends, inbound decryption, and acknowledgements. Revoked records remain tombstones and cannot be restored by rescanning. Revocation is local only; it is not broadcast to other contacts or devices. Direct use of lower-level protocol/session APIs can bypass this application trust gate.

### 10. Replay attacker

A replay attacker re-sends prior valid packets to trigger duplicate processing. The protocol must detect duplicates via message IDs and session sequence state.

### 11. Traffic-analysis observer

An observer can infer timing, packet sizes, and connection metadata. eChat minimizes metadata but cannot claim complete elimination of traffic patterns.

## Explicit limitations

The following are unavoidable in a real system:

- if a device is fully compromised, the attacker may read plaintext shown by that device
- full anonymity is not guaranteed by the design unless proven with additional engineering and threat analysis
- metadata such as timing, packet size, and account identifiers may still reveal information
- local key protection depends on the platform security model and user device integrity

## Security goals and residual risk

The project must document both the goals and residual risk. Security is not claimed by adding a cryptographic library to the stack; it is only valid when the protocol, storage, validation, and operational controls are correct and tested.

The eChat handshake, message-key derivation, and envelope composition are project-specific and have not been independently audited. This does not implement Double Ratchet, post-compromise security, per-message forward secrecy, remote revocation propagation, or a production contact-management workflow. Passing unit tests does not make the messaging protocol production-approved.
