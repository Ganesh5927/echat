# Metadata analysis

## What the server can know

The relay server may necessarily know:

- account or device identifiers
- approximate connection timing
- IP address or transport-layer information
- packet sizes
- queue duration and delivery timestamps
- rate limiting and abuse signals
- push notification metadata
- contact lookup or public identity availability records

## What the server mathematically cannot know

Given a correct end-to-end encrypted design, the server cannot know:

- message plaintext
- attachment plaintext
- session keys
- private identity keys
- local conversation history
- the exact contents of encrypted payloads

## Why metadata still matters

Even when the server cannot decrypt content, the following patterns can still be observed:

- who connected to whom
- when communication took place
- how frequently traffic occurs
- whether a device is online
- how large the encrypted blob is
- whether a packet is queued or delivered

This is a real limitation of the design and must be openly documented.

In the current local Phase 3 packet, device and session references, message type and ID, sequence, key epoch, nonce, ciphertext length, authentication tag, and optional transport hints are visible. No relay currently receives these packets. The message body is encrypted locally, but this testable package behavior is not a deployment or anonymity claim.

## Privacy goals

The system should minimize metadata by:

- using opaque device references
- reducing unnecessary contact-discovery metadata
- avoiding unnecessary log retention
- limiting push metadata
- using default opt-in analytics only where required

## Explicit non-claims

The project must not claim that eChat is fully untraceable or that metadata is eliminated unless it is proven with actual traffic and deployment analysis.
