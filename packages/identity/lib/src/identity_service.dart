import 'dart:async';
import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:echat_secure_core/echat_secure_core.dart';
import 'package:uuid/uuid.dart';

import 'device_identity.dart';
import 'public_identity_qr.dart';
import 'secure_identity_store.dart';

class IdentityService {
  IdentityService({SecureIdentityStore? store})
    : _store = store ?? MemorySecureIdentityStore();

  final SecureIdentityStore _store;
  Future<DeviceIdentity>? _createFuture;

  Future<DeviceIdentity> createIdentity({bool overwrite = false}) async {
    if (_createFuture != null) {
      return _createFuture!;
    }

    final completer = Completer<DeviceIdentity>();
    _createFuture = completer.future;

    try {
      final existing = await loadIdentity();
      if (existing != null && !overwrite) {
        completer.complete(existing);
        return existing;
      }

      final keyPair = await Ed25519().newKeyPair();
      final privateKey = await keyPair.extractPrivateKeyBytes();
      final publicKey = await keyPair.extractPublicKey();
      final publicKeyBytes = publicKey.bytes;
      final fingerprint = DeviceIdentity.pivotFingerprint(publicKeyBytes);
      final publicKeyPem = DeviceIdentity.formatPublicKeyPem(publicKeyBytes);
      final privateKeyPem = DeviceIdentity.formatPrivateKeyPem(privateKey);
      final deviceId = const Uuid().v4();
      final createdAt = DateTime.now().toUtc();

      final identity = DeviceIdentity(
        deviceId: deviceId,
        publicKeyPem: publicKeyPem,
        fingerprint: fingerprint,
        createdAt: createdAt,
        status: IdentityStatus.created,
        publicKeyBase64: base64Encode(publicKeyBytes),
      );

      await _store.savePrivateKey(privateKeyPem);
      await _store.savePublicIdentity(identity.toMap());
      completer.complete(identity);
      return identity;
    } catch (error, stackTrace) {
      completer.completeError(error, stackTrace);
      rethrow;
    } finally {
      _createFuture = null;
    }
  }

  Future<DeviceIdentity?> loadIdentity() async {
    final publicIdentity = await _store.loadPublicIdentity();
    final privateKeyPem = await _store.loadPrivateKey();

    if (publicIdentity == null ||
        privateKeyPem == null ||
        privateKeyPem.isEmpty) {
      return null;
    }

    try {
      final parsed = Map<String, dynamic>.from(publicIdentity);
      final identity = DeviceIdentity.fromMap(parsed);
      final publicKeyBytes = _decodePublicKeyPem(identity.publicKeyPem);
      if (identity.fingerprint !=
          DeviceIdentity.pivotFingerprint(publicKeyBytes)) {
        throw const FormatException('Public identity fingerprint mismatch');
      }
      return identity;
    } on FormatException {
      throw const SecureStorageException(
        'Stored identity is damaged or corrupted.',
      );
    } on Exception {
      throw const SecureStorageException(
        'Stored identity could not be loaded securely.',
      );
    }
  }

  Future<PublicIdentity> getPublicIdentity() async {
    final identity = await loadIdentity();
    if (identity == null) {
      throw StateError('No device identity has been created yet.');
    }

    return PublicIdentity(
      deviceId: identity.deviceId,
      publicKeyPem: identity.publicKeyPem,
      fingerprint: identity.fingerprint,
      createdAt: identity.createdAt,
      status: identity.status.name,
    );
  }

  Future<String> getVerificationFingerprint() async {
    final identity = await loadIdentity();
    if (identity == null) {
      throw StateError('No device identity has been created yet.');
    }
    return identity.fingerprint;
  }

  Future<bool> hasIdentity() async {
    try {
      return await _store.hasIdentity();
    } on SecureStorageException {
      return false;
    }
  }

  Future<void> deleteIdentity() async {
    await _store.deleteAll();
  }

  Future<DeviceIdentity> rotateIdentity() async {
    final previous = await loadIdentity();
    final next = await createIdentity(overwrite: true);
    if (previous != null) {
      final rotatedIdentity = DeviceIdentity(
        deviceId: next.deviceId,
        publicKeyPem: next.publicKeyPem,
        fingerprint: next.fingerprint,
        createdAt: next.createdAt,
        status: IdentityStatus.identityChanged,
        publicKeyBase64: next.publicKeyBase64,
      );
      await _store.savePublicIdentity(rotatedIdentity.toMap());
      return rotatedIdentity;
    }
    return next;
  }

  PublicIdentityQrPayload createQrPayload(DeviceIdentity identity) {
    return PublicIdentityQrPayload(
      version: 1,
      deviceId: identity.deviceId,
      publicKeyPem: identity.publicKeyPem,
      fingerprint: identity.fingerprint,
      createdAt: identity.createdAt,
    );
  }

  List<int> _decodePublicKeyPem(String publicKeyPem) {
    final sanitized = publicKeyPem
        .replaceAll('-----BEGIN ECHAT DEVICE PUBLIC KEY-----', '')
        .replaceAll('-----END ECHAT DEVICE PUBLIC KEY-----', '')
        .replaceAll('\n', '')
        .replaceAll('\r', '')
        .trim();

    final bytes = base64Decode(sanitized);
    if (bytes.isEmpty) {
      throw const FormatException('Public key is empty.');
    }
    return bytes;
  }
}

class IdentityServiceException implements Exception {
  const IdentityServiceException(this.message);

  final String message;

  @override
  String toString() => 'IdentityServiceException: $message';
}
