import 'dart:convert';

import 'package:crypto/crypto.dart';

class PublicIdentityFormatException implements Exception {
  const PublicIdentityFormatException(this.code);

  final String code;

  @override
  String toString() => 'PublicIdentityFormatException: $code';
}

class PublicIdentityQrPayload {
  const PublicIdentityQrPayload({
    required this.version,
    required this.deviceId,
    required this.publicKeyPem,
    required this.fingerprint,
    required this.createdAt,
  });

  final int version;
  final String deviceId;
  final String publicKeyPem;
  final String fingerprint;
  final DateTime createdAt;

  static const int currentVersion = 1;
  static const String _publicKeyBegin =
      '-----BEGIN ECHAT DEVICE PUBLIC KEY-----';
  static const String _publicKeyEnd = '-----END ECHAT DEVICE PUBLIC KEY-----';
  static final RegExp _deviceIdPattern = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
    caseSensitive: false,
  );
  static final RegExp _fingerprintPattern = RegExp(r'^[0-9a-f]{64}$');

  void validate() {
    if (version != currentVersion || !_deviceIdPattern.hasMatch(deviceId)) {
      throw const PublicIdentityFormatException('invalid_public_identity');
    }
    if (!publicKeyPem.startsWith('$_publicKeyBegin\n') ||
        !publicKeyPem.endsWith('\n$_publicKeyEnd') ||
        publicKeyPem.contains('PRIVATE KEY')) {
      throw const PublicIdentityFormatException('invalid_public_key_format');
    }
    try {
      final encoded = publicKeyPem
          .substring(
            _publicKeyBegin.length + 1,
            publicKeyPem.length - _publicKeyEnd.length - 1,
          )
          .replaceAll('\n', '')
          .replaceAll('\r', '');
      final publicKey = base64Decode(encoded);
      final computedFingerprint = sha256.convert(publicKey).toString();
      if (publicKey.length != 32 ||
          base64Encode(publicKey) != encoded ||
          !_fingerprintPattern.hasMatch(fingerprint) ||
          computedFingerprint != fingerprint) {
        throw const PublicIdentityFormatException(
          'public_identity_fingerprint_mismatch',
        );
      }
    } on PublicIdentityFormatException {
      rethrow;
    } on Object {
      throw const PublicIdentityFormatException('invalid_public_key_format');
    }
  }

  factory PublicIdentityQrPayload.fromJson(Map<String, dynamic> json) {
    const fields = {
      'version',
      'deviceId',
      'publicKeyPem',
      'fingerprint',
      'createdAt',
    };
    if (json.length != fields.length ||
        !json.keys.toSet().containsAll(fields)) {
      throw const PublicIdentityFormatException(
        'invalid_public_identity_schema',
      );
    }
    try {
      final payload = PublicIdentityQrPayload(
        version: json['version'] as int,
        deviceId: json['deviceId'] as String,
        publicKeyPem: json['publicKeyPem'] as String,
        fingerprint: json['fingerprint'] as String,
        createdAt: DateTime.parse(json['createdAt'] as String).toUtc(),
      );
      payload.validate();
      return payload;
    } on PublicIdentityFormatException {
      rethrow;
    } on Object {
      throw const PublicIdentityFormatException('invalid_public_identity');
    }
  }

  Map<String, dynamic> toJson() {
    validate();
    return {
      'version': version,
      'deviceId': deviceId,
      'publicKeyPem': publicKeyPem,
      'fingerprint': fingerprint,
      'createdAt': createdAt.toUtc().toIso8601String(),
    };
  }

  String toQrString() => const JsonEncoder.withIndent('  ').convert(toJson());

  factory PublicIdentityQrPayload.fromQrString(String value) {
    try {
      final decoded = jsonDecode(value);
      if (decoded is! Map<String, dynamic>) {
        throw const PublicIdentityFormatException(
          'invalid_public_identity_schema',
        );
      }
      return PublicIdentityQrPayload.fromJson(decoded);
    } on PublicIdentityFormatException {
      rethrow;
    } on Object {
      throw const PublicIdentityFormatException('invalid_public_identity');
    }
  }
}
