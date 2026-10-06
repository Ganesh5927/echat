# Trust model

## Principle

The relay server is not a trusted party. It is considered untrusted infrastructure that may route packets and maintain minimal metadata, but it must never become able to read conversation content or private identity material.

## Implemented Relay Scope

The current relay authenticates through an injected callback, accepts versioned transport packets, queues opaque bytes in memory, and supports polling, acknowledgement, expiry, and bounded request/queue/rate limits. It has no database, public-identity directory, push service, message decryption API, or built-in production credential authority. Base64 is transport encoding only; message confidentiality comes from endpoint encryption.

## What the server may do

The relay implementation currently may:

- authenticate inbound client connections
- route encrypted packets between devices
- temporarily queue ciphertext for offline recipients
- enforce rate limits and abuse controls
- maintain minimal delivery metadata for message routing

Public identity discovery, push notifications, and durable queueing are future work, not current relay capabilities.

## What the server must not do

The server must not be able to:

- decrypt user messages
- decrypt attachments
- access private identity keys
- obtain session encryption keys
- read local conversation history
- receive plaintext message content intentionally or accidentally
- act as a decryption authority

## Necessary metadata

The server necessarily sees some metadata, including at minimum:

- account identifiers or device references
- public identity records used for contact discovery
- timestamps of packet arrival and queue processing
- packet sizes and connection timing
- IP addresses and transport-layer identifiers
- push notification metadata
- rate-limit and abuse evaluation signals

This is not zero metadata. The goal is metadata minimization, not metadata elimination.

## Mitigations

To minimize exposure:

- use pseudonymous or opaque device references when possible
- avoid keeping unnecessary social graph data
- maintain short retention periods for queued encrypted packets
- avoid logging plaintext or decrypted message content
- use minimal server-side metadata and explicit retention policies

## Local Contact Trust

The client validates the QR schema and recomputes the public-key fingerprint. Observing a contact does not verify it; explicit confirmation is required. A changed key remains a candidate until explicit re-verification, and a session pinned to the old key remains blocked. Local revocation is retained as a tombstone and checked by the messaging coordinator before sends, inbound processing, and duplicate acknowledgements.

Contact records are persisted through the AES-GCM encrypted trust-store adapter using the mobile app's Flutter Secure Storage-backed key provider. The UI accepts a pasted public identity payload and requires the user to enter an independently compared fingerprint; camera QR scanning is not configured. Revocation is local and not propagated to other devices or the server. Low-level session APIs do not enforce contact policy by themselves; the application messaging controller does.

The mobile UI is one-to-one only. Session-control JSON is staged by the application controller, but the app has no configured session-exchange delivery channel; a request stays pending and the composer remains blocked until the existing handshake completes.

## Security assumptions

The trust model assumes that:

- transport security is enabled with validated TLS certificates
- servers implement strict access controls and key isolation
- the cryptographic protocol is end-to-end authenticated and encrypted
- the client performs local verification before accepting data as valid

## Limitations

The server is still able to observe patterns such as:

- whether the client is online
- when packets were sent
- which devices or account identifiers communicated
- approximate packet size and timing

This does not make the server a trusted decryption endpoint, but it does mean the system cannot claim perfect untraceability or complete metadata elimination unless those claims are proven with real traffic analysis and operational controls.
