# Server architecture

## Server role

The server in eChat is transport and routing infrastructure, not a trusted authentication or decryption authority. It exists to authenticate clients, relay encrypted packets, retain minimal routing state, and assist with delivery and abuse prevention.

## Proposed components

```text
Gateway
  ├─ TLS termination
  ├─ authentication
  ├─ HTTP/WebSocket routing
  ├─ rate limiting
  └─ request validation

Identity service
  ├─ public identity publication
  ├─ device record validation
  ├─ revocation records
  └─ contact discovery metadata

Relay service
  ├─ encrypted packet routing
  ├─ queueing
  ├─ offline message persistence
  └─ delivery acknowledgements

Delivery service
  ├─ push triggers
  ├─ recipient online checks
  ├─ retry policies
  └─ stale packet cleanup

Abuse service
  ├─ rate limits
  ├─ block handling
  ├─ connection throttling
  └─ reports / revocation requests
```

## Database design principles

The server database should not become a social-media graph or message archive. It stores only the minimum required to route encrypted packets and maintain account/device records.

At minimum the database may contain:

- devices
- public_identity_records
- delivery_queue
- relay_packets
- revoked_devices
- rate_limits
- audit/security_events

It should not store:

- plaintext messages
- plaintext attachments
- private keys
- private session state
- conversation history beyond the minimum required for operational support

## Encrypted packet handling

The backend does not expose a plaintext decryption service and should not have endpoints such as:

- POST /decrypt-message
- GET /plaintext-message

All payloads that reach the server are encrypted protocol data. The server may need to record message IDs, routing metadata, expiry information, and queue state, but it must not be able to decrypt the content.

## Queue and retention policy

Temporary encrypted packets are stored in a queue until the recipient acknowledges receipt or the packet expires. Retention must be explicitly bounded and documented.

Recommended policy:

- enqueue only ciphertext
- no plaintext attachments or message bodies
- delete successfully delivered packets promptly
- enforce expiration windows for stale undelivered items
- purge expired data according to defined operational retention rules

## Security controls

The server should include:

- TLS enforcement
- connection authentication
- strict input validation
- signing and replay protections for important administrative operations
- abuse detection and throttling
- minimal logging with sensitive-field filtering

## Operational limits

The server can be compromised or the database can be stolen without exposing message plaintext. Compromise of the server does not automatically equal compromise of the conversation; this is only true if the protocol itself is flawed or if a client endpoint is compromised.
