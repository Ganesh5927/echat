# Trust model

## Principle

The relay server is not a trusted party. It is considered untrusted infrastructure that may route packets and maintain minimal metadata, but it must never become able to read conversation content or private identity material.

## What the server may do

The server may:

- authenticate inbound client connections
- route encrypted packets between devices
- temporarily queue ciphertext for offline recipients
- keep public identity records needed for discovery and verification
- trigger push notifications or delivery callbacks
- enforce rate limits and abuse controls
- maintain minimal delivery metadata for message routing

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
