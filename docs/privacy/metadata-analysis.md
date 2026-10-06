# Metadata analysis

## Relay-Visible Data

The relay sees, or can infer from normal operation:

- authenticated sender and recipient route IDs
- packet IDs and recipient route IDs
- packet submission, polling, acknowledgement, and expiry times
- IP address or transport-layer information
- packet and HTTP request sizes
- whether a recipient has pending traffic and queue duration
- rate limiting and abuse signals
- HTTPS authorization credentials when validating the transport request
- message-envelope metadata inside the opaque encrypted-packet bytes: device/session IDs, message ID/type, sequence, key epoch, nonce, ciphertext length, and authentication tag

The relay implementation queues packet bytes without parsing the Phase 3 envelope. This is an implementation choice, not a cryptographic protection: envelope fields are visible and could be decoded by a curious or modified relay.

## Client-Visible Data

The sending client handles entered plaintext and its local identity/session state. The receiving client handles authenticated plaintext after decryption, local trust records, and message history. A compromised endpoint can expose these data.

## Protected Content

The relay request contains the versioned transport wrapper and serialized Phase 3 packet. Under correct client behavior and secrecy of endpoint keys, AES-256-GCM protects message content. The packet has no private identity key, session root, per-message key, local storage key, or plaintext field. This is an implementation property covered by local integration tests, not proof against compromised clients, malicious builds, or deployment misconfiguration.

## Implemented Privacy Properties

- messages are encrypted on the sending endpoint before relay submission
- relay packet handling requires only opaque encrypted bytes
- local message and contact-trust records use AES-GCM with a host-provided key
- protocol, transport, and relay errors use bounded codes/messages rather than message content or key values
- no application debug or print logging calls were found in the audited Dart source

## Not Implemented / Unavoidable Metadata

- IP addresses, connection timing, online/availability patterns, packet sizes, routing IDs, and delivery state are not hidden
- no traffic padding, batching, onion routing, proxying, or IP masking
- the relay queue is volatile in-memory state and has no production retention service
- no deployed-network privacy measurement or anonymity property is claimed
- local filesystem activity, record counts, ciphertext sizes, and best-effort deletion remain observable

Contact QR payloads contain a version, device identifier, public key, fingerprint, and creation timestamp. Trust/revocation state is local and is not sent to the relay. Device IDs and fingerprints identify devices when a QR is shared.

## Privacy goals

The system should minimize metadata by:

- using opaque device references
- reducing unnecessary contact-discovery metadata
- avoiding unnecessary log retention
- limiting push metadata
- using default opt-in analytics only where required

## Explicit non-claims

eChat is not 100% anonymous, untraceable, or impossible to monitor. This project does not claim forward secrecy, post-compromise security, Double Ratchet, or production-grade anonymity. Tests use local/in-process transports and do not establish production deployment properties.
