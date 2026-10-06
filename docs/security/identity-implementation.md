# Identity implementation notes

## Chosen cryptographic implementation

The Phase 1 identity foundation uses Ed25519 via the `cryptography` Dart package. This was chosen because it is a mature, well-established public-key primitive with clear APIs for key generation, public-key derivation, and stable fingerprint creation. The implementation does not invent a custom encryption scheme or private key format.

## Why this choice was selected

- established and audited public-key design
- small, clear key material footprint
- good fit for device identity and QR presentation
- mature Dart ecosystem support
- no custom cryptographic code in the UI layer

## Key lifecycle

1. `IdentityService.createIdentity()` generates a new Ed25519 keypair.
2. The private key is written to secure platform storage via `FlutterSecureStorage`.
3. The public identity is stored separately as public metadata in app preferences.
4. A SHA-256 fingerprint is derived from the public key bytes.
5. `loadIdentity()` validates the stored public key and fingerprint on restart.
6. `rotateIdentity()` generates and stores a fresh keypair.
7. `deleteIdentity()` removes the private key and public metadata.

## Fingerprint generation

The fingerprint is computed as the SHA-256 digest of the raw public key bytes. It is intended for human verification and QR display only. It is not a private key and is not used for anything cryptographic beyond verification comparison.

## Secure storage implementation

The app-level implementation is intentionally split:

- private key -> `flutter_secure_storage`
- public identity metadata -> `SharedPreferences`

This enforces the separation between cryptographic identity and application preferences. The private key is never written to plaintext JSON, shared preferences, or source code.

## Limitations

The trust core provides strict public QR validation, explicit verification, changed-key candidate tracking, explicit re-verification, local revocation tombstones, and messaging gates tied to the session's pinned peer key. Encrypted contact persistence is available through an adapter with an injected key provider.

The current implementation still does not include:

- multi-device key syncing
- server-side private-key backup
- device registration on a remote backend
- QR scanning/contact-management UI or an independently verified out-of-band fingerprint channel
- wiring the encrypted contact store to the mobile app's secure key provider
- remote revocation distribution or notification
- key recovery via escrow or social recovery

Revocation is local to one installation. The low-level session and protocol APIs remain usable independently; trust enforcement is applied by the messaging coordinator.

## Threat assumptions

The implementation assumes that:

- local device storage is protected by the platform secure storage API
- user endpoints are not fully compromised
- the relay and backend are treated as untrusted infrastructure
- private key material remains on-device and is never sent to infrastructure

The implementation does not claim perfect security if the endpoint device is fully compromised. In such a case, an attacker with local control of the endpoint may access plaintext or local state displayed on that device.
