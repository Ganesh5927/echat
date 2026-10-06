# Relay service

The Phase 4 relay foundation is an untrusted Shelf HTTP service. It accepts a versioned transport wrapper, binds the sender route to an injected authenticated principal, validates routing/size/expiry/rate/queue limits, and stores encrypted protocol bytes opaquely in memory.

The API supports:

- `GET /health`
- `POST /v1/packets`
- `GET /v1/packets` (one packet per poll)
- `POST /v1/packets/{packetId}/acknowledgement`

The queue is at-least-once: a delivered packet remains available until acknowledgement or expiration. Duplicate submissions with the same packet ID and identical sender, recipient, and payload are idempotent; conflicting reuse is rejected. Acknowledgement clears ciphertext immediately and retains a bounded idempotency tombstone until packet expiry plus retention. Expiration cleanup runs on API activity or explicit `cleanup()` calls.

The relay has no decryption API, cryptographic message dependency, database, durable queue, or built-in credential authority. State is lost on restart. Production deployment is not configured or approved.
