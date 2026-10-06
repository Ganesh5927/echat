# Identity architecture

## Implementation status: Phase 1

The repository currently implements the device identity foundation for a single eChat device. The actual code uses the `cryptography` Dart package with `Ed25519` key generation, stores private key material in secure platform-backed storage, exposes a public identity representation, generates a verification fingerprint, supports persistence/reload/deletion/rotation, and keeps private material out of the QR payload.

This milestone intentionally does not include server-side private-key backup, multi-device synchronization, or full contact agreement flows.

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

The QR code contains public identity information only. It must never expose private keys.

The user should be able to compare:

- device fingerprint
- public identity key fingerprint
- contact name or alias
- verification metadata

The goal is to ensure that the public key they received corresponds to the intended contact.

## Device registration

When a device is first created:

1. generate local identity keypair
2. register device record with a unique device identifier
3. associate the public key with a user account or local profile
4. display the QR or public identity record
5. store local device metadata in encrypted storage

## Identity verification

Contact verification is a cryptographic step, not a phone-number check. The flow should include:

- scan contact QR
- fetch public identity bundle
- verify fingerprint against the expected contact identifier
- confirm the user wants to trust the identity
- establish an authenticated session

If verification fails, the session must not proceed.

## Device revocation

A device may be revoked when:

- it is lost or stolen
- it is no longer trusted
- a malicious or compromised state is detected
- a user removes the device from their account

Revocation must invalidate the device identity and lead to a session failure or a re-verification flow for that device.

## Identity changes and rotation

Identity changes are not a simple “rekey everything” operation. The system should support:

- key rotation for a device when a compromise is suspected
- re-verification of contacts after key change
- explicit notification that identity changed
- a bounded state where old keys remain valid until re-establishment

This must be documented and tested. The system must not silently continue with a changed identity while claiming verification.

## Security assumptions and limitations

This design assumes the user’s client platform provides secure key storage to protect private keys. If a device is fully compromised, the attacker may control the identity material on that device and read anything displayed locally.

The architecture intentionally separates:

- cryptographic identity
- application account
- device authorization
- transport authentication
