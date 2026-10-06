# Identity architecture

## Implementation status: identity and local trust core

The repository implements Ed25519 device identities, public fingerprints, and a local contact-trust service. QR payload parsing enforces an exact public-only schema and recomputes the SHA-256 fingerprint from the 32-byte public key. Contact states are `unverified`, `verified`, `identityChanged`, and `revoked`.

Contact trust can use the AES-GCM encrypted storage adapter through an injected local key provider. This adapter is not yet wired into the mobile app or a contact-management UI. There is no server-side private-key backup, contact discovery, remote revocation broadcast, or multi-device synchronization.

## Design goal

Each device has a distinct cryptographic identity. The user is not identified solely by a phone number or a server-issued login. The identity model is built around device-bound keys and verified public identity data.

## Core model

```text
User
├─ Device A
│  ├─ identity keypair
│  ├─ device record
│  └─ session state
├─ Device B
│  ├─ identity keypair
│  ├─ device record
│  └─ session state
└─ Contact verification data
```

## Key material

Each device generates:

- identity private key
- identity public key
- optional signing key for message/auth state
- ephemeral session keys derived as needed

Private key material stays exclusively on the device and is protected by secure platform storage and local encryption.

## Identity generation

The actual implementation uses Ed25519 from the `cryptography` package. The private key is generated locally on the device and persisted through secure platform storage. The server never receives the private key material, and the QR payload contains only public identity metadata.

### Requirements

- generate keys on-device
- protect private key with platform secure storage
- never store private key in plaintext files
- never copy private keys to every device without an explicit secure addition flow

## Public identity

Public identity data is the portion that can be exchanged or published:

- device identifier
- public identity key
- verification fingerprints
- user-visible display name
- optional public metadata for trust signaling

Public identity must be exchanged via a verified channel. QR exchange is the default for MVP.

## QR verification flow

The QR code contains only version, device ID, public-key PEM, fingerprint, and identity creation time. Parsing rejects extra fields, private-key PEM, unsupported versions, malformed public keys, and fingerprint mismatches. It must never expose private keys or session secrets.

The user should be able to compare:

- device fingerprint
- public identity key fingerprint
- contact name or alias
- verification metadata

The user must compare the fingerprint through a trusted channel before explicitly verifying the contact. Parsing or observing a QR marks a new contact `unverified`; it does not establish trust.

## Device registration

When a device is first created:

1. generate local identity keypair
2. register device record with a unique device identifier
3. associate the public key with a user account or local profile
4. display the QR or public identity record
5. store local device metadata in encrypted storage

## Identity verification

Contact verification is a cryptographic step, not a phone-number check. The implemented library flow is:

- parse and validate the exact public QR payload
- observe it locally as `unverified`
- compare its fingerprint with the expected contact through a trusted channel
- explicitly verify the contact
- establish a session pinned to that public key

The messaging coordinator requires a verified contact whose key exactly matches the session's pinned remote identity key before sending or accepting/acknowledging messages. Direct use of lower-level session/protocol APIs does not itself perform contact-trust checks.

## Device revocation

A device may be revoked when:

- it is lost or stolen
- it is no longer trusted
- a malicious or compromised state is detected
- a user removes the device from their account

`revokeContact` records a local revoked tombstone. Messaging operations fail closed for the revoked peer, including queued sends and inbound duplicate acknowledgements. Rescanning or calling normal verification cannot clear the tombstone. Revocation is not broadcast to the peer or relay, and low-level session APIs are not destroyed automatically.

## Identity changes and rotation

When a previously observed device ID presents a different public key, the trust service keeps the previous key pinned, stores the new key as a candidate, and marks the contact `identityChanged`. Messaging is blocked until `reverifyChangedIdentity` explicitly accepts that candidate. Even then, sessions pinned to the old key remain unusable; a new authenticated session is required. Automatic key-change discovery and user-facing notifications do not exist yet.

## Security assumptions and limitations

This design assumes the user’s client platform provides secure key storage to protect private keys. If a device is fully compromised, the attacker may control the identity material on that device and read anything displayed locally.

The architecture intentionally separates:

- cryptographic identity
- application account
- device authorization
- transport authentication
