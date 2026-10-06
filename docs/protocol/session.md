# Session design

## Purpose

A session establishes authenticated keys for a pair of devices and supports ongoing message encryption, authentication, and replay protection across time.

## Session model

Each 1-to-1 conversation uses an authenticated session between two device identities. A session includes:

- device A identity
- device B identity
- session identifier
- message sequence state
- replay window
- key evolution state
- last verified identity status
- revocation state

## Session establishment

The session should begin with an authenticated key agreement using a mature, audited implementation. A typical design uses a key agreement protocol with authentication properties and then derives message keys from the shared secret using a KDF.

The process includes:

1. device identity validation
2. contact verification confirmation
3. key agreement
4. transcript authentication
5. deriving session keys
6. establishing initial message sequence state
7. storing encrypted session record locally

## Session key derivation

A session must derive:

- root secret
- update chain or ratchet state
- message encryption keys
- message authentication keys
- associated key metadata

The session key must evolve over time so that compromise of a later state does not automatically expose earlier message content.

## Forward secrecy

Forward secrecy is not achieved by merely rotating keys; it requires that each message or key epoch be derived from prior state without allowing an attacker who steals one state to derive earlier keys.

The design should use established ratcheting patterns from vetted secure messaging protocols, not a custom implementation.

## Key evolution and ratcheting

The session is expected to support:

- message key evolution
- session key updates
- key destruction / retirement after safe transition
- rekey after suspicious state
- recovery after temporary communication loss

When a key change occurs, device state must be updated and the contact must be re-verified according to the protocol state engine.

## Replay protection

Replay protection is not only time-based. Each message should include a unique message identifier and a session sequencing mechanism. The receiver tracks:

- message IDs already seen
- highest accepted sequence number or equivalent monotonic state
- duplicate detection
- out-of-order handling rules

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

When connectivity returns, clients should recover by:

- resuming the existing authenticated session
- processing queued encrypted packets
- acknowledging messages safely
- detecting duplicates and expired packets
- re-synchronizing sequence state if needed

## Security assumptions

The protocol assumes mature libraries and tested key derivation and ratchet logic. If a cryptographic decision is uncertain, the project must document the uncertainty and avoid inventing a custom solution.
