# API specification

## Transport requirements

The backend must use secure authenticated transport. Production deployment should require TLS with validated certificates and strict connection authentication.

## API categories

### Identity API

- register-device
- publish-public-identity
- verify-device-identity
- revoke-device
- get-public-identity

### Relay API

- send-encrypted-packet
- fetch-pending-packets
- acknowledge-receipt
- notify-reconnect
- queue-status

### Delivery API

- push-trigger
- offline-delivery-check
- queue-cleanup

### Abuse API

- rate-limit-check
- block-status
- report-device

## Message flow contract

The client sends only encrypted packets to the relay. The relay never receives plaintext message bodies or attachments.

### Example request

```json
{
  "protocol_version": 1,
  "message_id": "opaque-message-id",
  "sender_device_reference": "device-ref",
  "recipient_device_reference": "device-ref",
  "session_reference": "session-ref",
  "sequence_number": 7,
  "timestamp": 1730000000,
  "ciphertext": "base64-encoded-encrypted-message",
  "authentication": {
    "tag": "base64-encoded-auth-tag"
  },
  "transport_metadata": {
    "route_hint": "queue-id",
    "ack_id": "opaque-ack-id"
  }
}
```

## Security requirements

- no plaintext content endpoints
- no /decrypt-message service
- no /plaintext-message endpoint
- strict validation of identity and session references
- rate limiting and abuse controls
- minimal logging and sensitive-data filtering
