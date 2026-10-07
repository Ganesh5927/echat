# Relay service

The relay is an untrusted Shelf HTTP service. It accepts a versioned transport wrapper, binds the sender route to an injected authenticated principal, validates routing/size/expiry/rate/queue limits, and persists encrypted protocol bytes opaquely.

The relay authenticates registered devices using the existing device Ed25519 identity keys. Registration and authentication use short-lived, one-use server challenges; the device signs a domain-separated challenge and never sends its private key. Successful authentication issues an in-memory, short-lived bearer token bound to that device ID. The HTTPS client registers its local public identity idempotently and authenticates during `connect()`.

The API supports:

- `GET /health`
- `POST /v1/auth/challenge`
- `POST /v1/devices/register`
- `POST /v1/authenticate`
- `POST /v1/packets`
- `GET /v1/packets` (one packet per poll)
- `POST /v1/packets/{packetId}/acknowledgement`

Configure `RelayApi` with `RelayDeviceAuthenticator(deviceStore: FileRelayDeviceStore(directory: Directory('.echat-relay-devices')))` to use device authentication. `MemoryRelayDeviceStore` is available for tests. The default development packet backend is a local file queue in `.echat-relay-queue`; callers can inject another `RelayQueueStore`. `serveRelaySecurely` restores queue and registration state before binding its listener, and the HTTP API also waits for initialization before processing requests. Queue records contain only packet identifiers, sender/recipient route bindings, opaque packet bytes, timestamps, a payload digest for duplicate checks, and delivery/ACK/expiry state. Device records contain only device ID, public key, fingerprint, and registration time; bearer tokens and challenge state are memory-only. The file backends atomically replace records. Persistence failures prevent successful registration or queue operations.

The queue is at-least-once: a delivered packet remains available until acknowledgement or expiration. Duplicate submissions with the same packet ID and identical sender, recipient, and payload are idempotent; conflicting reuse is rejected. Acknowledgement clears ciphertext immediately and retains a bounded idempotency tombstone until packet expiry plus retention. Expiration cleanup runs on API activity or explicit `cleanup()` calls.

The relay has no decryption API or message-key access. Device registrations expose public identity metadata to the relay; they do not verify contact trust or authorize message decryption. The local file backends are intended for single-process development, are not encrypted at rest, and do not provide a production database, multi-process locking, revocation management, or production deployment configuration. The relay remains able to observe route and timing/size metadata. Deployments must provide trusted HTTPS/TLS configuration and choose an operational registration-retention/revocation policy.

There is no executable relay composition root in this repository. `serveRelaySecurely` is a library helper that requires the caller to supply its `SecurityContext`; it does not load environment-based bind, storage, or TLS configuration. Do not expose the development file stores as a production deployment.
