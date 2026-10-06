# Session Foundation

## Purpose

A session foundation establishes shared key material between two previously verified device identities. This phase does not encrypt chat messages or implement a ratchet.

## Session model

The current 1-to-1 foundation records:

- device A identity
- device B identity
- session identifier
- independent send and receive sequence state
- highest accepted sequence per direction and seen protocol message IDs
- derived-key fingerprint
- pending, established, or closed lifecycle state

## Session establishment

The implementation uses Ed25519 signatures, ephemeral X25519, and HKDF-SHA256 through the `cryptography` package. Device identity public keys must be verified out of band before session initiation; the responder API requires the expected verified initiator key. This code composes those standard primitives into a versioned two-message exchange, but the exchange itself has not received an independent protocol audit and must not be treated as production-approved.

The process includes:

1. The initiator creates a session ID and ephemeral X25519 keypair.
2. The initiator signs the versioned initiation transcript with its Ed25519 device key.
3. The responder checks the pinned initiator identity, recipient device ID, and its own identity key.
4. The responder creates an ephemeral X25519 keypair, derives key material with HKDF-SHA256, and signs the acceptance transcript.
5. The initiator verifies the pinned responder identity and key fingerprint before establishing the session.
6. Protocol message IDs and monotonically increasing sequence values reject duplicates and stale packets.
7. The mobile adapter stores public session metadata in SharedPreferences and secret bundles in FlutterSecureStorage.

## Session key derivation

HKDF-SHA256 derives a 256-bit session key with a context containing the session ID, both device IDs, and both identity public keys in canonical order. The fingerprint is retained for handshake confirmation. Session secrets are persisted only through `SecureSessionStore`; the mobile implementation uses FlutterSecureStorage. `MemorySecureSessionStore` is for tests and must not be used for persistent application sessions.

## Forward secrecy

Ephemeral DH contributes per-session forward secrecy, subject to secure deletion and device storage assumptions. This phase does not provide per-message forward secrecy.

Message encryption, authenticated message records, and ratcheting are explicitly deferred. They must use a vetted protocol/library rather than a custom ratchet.

## Key evolution and ratcheting

Future ratcheting work must support:

- message key evolution
- session key updates
- key destruction / retirement after safe transition
- rekey after suspicious state
- recovery after temporary communication loss

When a key change occurs, device state must be updated and the contact must be re-verified according to the protocol state engine.

## Replay protection

Handshake and foundation packet replay protection is not time-based. The receiver tracks:

- message IDs already seen
- highest accepted sequence number or equivalent monotonic state
- duplicate message-ID detection
- a strict increasing sequence per direction (gaps are currently permitted)

Example behavior:

- 001 accepted
- 002 accepted
- 003 accepted
- 002 rejected as a duplicate

## Session termination

A session ends when:

- the user blocks the contact
- the device is revoked
- the identity changes and re-verification is required
- a protocol error occurs
- the conversation is intentionally deleted

Termination must be explicit and should fail closed for any message that cannot be validated.

## Recovery after temporary communication loss

Offline recovery is not implemented. A future client must:

- resuming the existing authenticated session
- processing queued encrypted packets
- acknowledging messages safely
- detecting duplicates and expired packets
- re-synchronizing sequence state if needed

## Security assumptions

The cryptographic operations are provided by the mature `cryptography` package. The message exchange composition remains unaudited. Before production use, it requires independent protocol review, secure-store integration on every supported platform, and a vetted messaging ratchet. The current session foundation must not be used to claim end-to-end encrypted messaging.
