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

1. Malicious or curious relay operator
2. Database attacker
3. Network attacker
4. Man-in-the-middle attacker
5. Malicious client
6. Stolen device
7. Compromised device
8. Malicious contact
9. Replay attacker
10. Traffic-analysis observer
11. Malformed or abusive client
12. Revoked device attempting to reuse old session data

## Implemented Controls

- Ed25519 device identity and authenticated X25519 session establishment
- AES-256-GCM message confidentiality/integrity with authenticated envelope fields
- per-session sequence/message-ID replay checks; gaps are permitted, stale sequences are rejected
- exact public QR schema/fingerprint validation and local verified/changed/revoked trust states
- encrypted local message and contact-trust records with host-provided keys
- HTTPS-only production transport endpoint validation and bounded relay request/queue/rate limits
- generic protocol, transport, and relay errors; no application debug/print logging found in audited Dart source

These are implementation controls, not a production security certification.

## Not Implemented / Not Claimed

- no Double Ratchet or post-compromise security
- no claim of per-message forward secrecy or production-grade anonymity
- no traffic padding, IP hiding, or protection from traffic analysis
- no remote revocation distribution or production relay persistence
- no guarantee of secure deletion or protection from a compromised endpoint
- no independent audit of the project-specific handshake/message composition

## Threat analysis

### 1. Malicious relay server

The relay may inspect, copy, delay, drop, replay, reorder, or tamper with packets and observe route IDs, packet IDs, expiry, queue timing, IP address, and connection metadata. AES-256-GCM should make message tampering fail authentication, but envelope references, sequence, nonce, ciphertext size, and tag remain visible. Relay behavior is tested in-process; no deployed-server claim is made.

### 2. Database attacker

The relay queue is in-memory and volatile. Locally, message and contact-trust records can be encrypted with AES-GCM before file persistence. The host must supply and protect the local key; the contact-store adapter is not yet wired into the mobile application. File counts, sizes, and access patterns remain observable, and deletion is not guaranteed secure erasure.

### 3. Network attacker

A passive or active network attacker may observe IP addresses, timing, sizes, and availability. TLS protects transport connections when correctly deployed; authenticated message encryption detects packet modification at the receiving endpoint. Tests do not validate deployed TLS.

### 4. Man-in-the-middle attacker

A MitM may substitute public identity data before initial verification. QR parsing checks schema and key-fingerprint consistency, but users must compare fingerprints through a trusted channel and explicitly verify the contact. Changed keys block messaging pending explicit re-verification; old sessions remain pinned to the old key. The app does not yet provide the user-facing comparison/scanning flow.

### 5. Malicious client

A malformed client can submit oversized, malformed, unsupported-version, wrong-type, invalid-Base64, or expired packets; relay tests cover bounded rejection behavior. A malicious authenticated client can still abuse authorized access within enforced limits.

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
