# Message envelope format

## Design goal

The protocol uses a versioned message envelope so that the transport metadata and cryptographic content are cleanly separated.

## Envelope structure

```text
MessageEnvelope {
  protocol_version: u16,
  message_id: string,
  sender_device_reference: string,
  recipient_device_reference: string,
  session_reference: string,
  sequence_number: u64,
  timestamp: u64,
  freshness: { epoch, nonce, ack_state },
  ciphertext: bytes,
  authentication: { tag, signature_or_mac },
  transport_metadata: { route_hint, queue_id, ack_id }
}
```

## Separation of concerns

### Transport metadata

Visible to the relay and required for routing, such as:

- destination device reference
- queue and routing identifiers
- timestamps or freshness markers
- delivery metadata required for retries

### Cryptographic content

Not exposed to the relay as plaintext and not usable to decrypt the message:

- ciphertext
- authentication tag
- session references that are not identity-revealing
- message sequence / anti-replay state

## Relay visibility

The relay can see enough to deliver the packet but not enough to learn the message body or decrypt content. The relay must not be able to derive plaintext from the packet envelope.

## Versioning

The protocol must define a version field so it can evolve safely. Each version should specify:

- schema layout
- required fields
- compatibility rules
- transformation rules for legacy messages
- rejection criteria for unsupported versions

## Security properties

The envelope must support:

- integrity protection
- sender authenticity
- recipient binding
- replay resistance
- session state tracking
- safe handling of invalid or unsupported messages

## Minimal metadata principle

Do not include unnecessary plaintext information in the message envelope. Avoid advertising user identity details or sending extra metadata that the relay does not need to perform transport.

## Validation rules

The receiver must reject a message when:

- the protocol version is unsupported
- the sender identity is not verified for the session
- the session reference is invalid
- the authentication tag fails
- the sequence number is invalid or duplicated
- the recipient identity does not match the session state
