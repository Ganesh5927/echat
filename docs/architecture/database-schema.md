# Database schema

## Design goals

The server database stores only the minimum operational data required for routing and account integrity. It does not store conversation contents.

## Core entities

### devices

- id
- account_ref
- device_ref
- public_identity_fingerprint
- created_at
- last_seen_at
- status
- revoked_at

### public_identity_records

- id
- device_ref
- public_key
- fingerprint
- verification_state
- created_at
- updated_at

### delivery_queue

- id
- recipient_device_ref
- message_id
- encrypted_payload
- expires_at
- status
- created_at
- delivered_at

### relay_packets

- id
- sender_device_ref
- recipient_device_ref
- session_ref
- message_id
- transport_meta
- ciphertext
- created_at
- expires_at

### revoked_devices

- id
- device_ref
- reason
- created_at
- effective_at

### rate_limits

- id
- actor_ref
- scope
- window_start
- count
- blocked_until

### audit_security_events

- id
- event_type
- source_ref
- severity
- message_hash
- timestamp

## Retention policy

- delete successfully delivered queue items promptly
- purge expired packets after a bounded retention window
- avoid storing plaintext conversations
- restrict audit logs to minimal security metadata only

## Constraints

- no plaintext messages
- no user chat archives in the server database
- no private keys or session keys
- no plaintext attachments
- no broad social graph representations beyond what is necessary for contact verification and routing
