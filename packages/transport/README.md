# Transport package

This package defines the Phase 4 opaque packet transport boundary.

- `PacketTransport` exposes connection state, connect/disconnect, submit, receive, and acknowledgement operations.
- `HttpsRelayTransport` uses HTTPS only and the platform HTTP client’s default certificate and hostname validation.
- `PacketSubmission` and `DeliveredPacket` carry Phase 3 serialized protocol bytes unchanged; this package does not import or decrypt the message protocol.

Bearer transport credentials are supplied through a callback and are separate from Phase 3 cryptographic message authentication. The production constructor does not accept a custom HTTP client or certificate callback. A test-only factory is provided for local tests.

There is no WebSocket, P2P, offline mobile background sync, or credential-provider implementation in this package.
