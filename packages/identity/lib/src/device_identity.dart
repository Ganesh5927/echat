import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:echat_secure_core/echat_secure_core.dart';

class DeviceIdentity {
  const DeviceIdentity({
    required this.deviceId,
    required this.publicKeyPem,
    required this.fingerprint,
    required this.createdAt,
    required this.status,
    this.publicKeyBase64 = '',
  });

  final String deviceId;
  final String publicKeyPem;
  final String fingerprint;
  final DateTime createdAt;
  final IdentityStatus status;
  final String publicKeyBase64;

  factory DeviceIdentity.fromMap(Map<String, dynamic> json) {
    return DeviceIdentity(
      deviceId: json['deviceId'] as String,
      publicKeyPem: json['publicKeyPem'] as String,
      fingerprint: json['fingerprint'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String),
      status: IdentityStatus.values.firstWhere(
        (value) =>
            value.name ==
            (json['status'] as String? ?? IdentityStatus.created.name),
        orElse: () => IdentityStatus.created,
      ),
      publicKeyBase64: json['publicKeyBase64'] as String? ?? '',
    );
  }

  Map<String, dynamic> toMap() => {
    'deviceId': deviceId,
    'publicKeyPem': publicKeyPem,
    'fingerprint': fingerprint,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'status': status.name,
    'publicKeyBase64': publicKeyBase64,
  };

  String get statusLabel => status.label;

  static String pivotFingerprint(List<int> bytes) {
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  static String formatPublicKeyPem(List<int> publicKeyBytes) {
    final base64 = base64Encode(publicKeyBytes);
    final wrapped = _wrapInLines(base64, 64);
    return '-----BEGIN ECHAT DEVICE PUBLIC KEY-----\n$wrapped\n-----END ECHAT DEVICE PUBLIC KEY-----';
  }

  static String formatPrivateKeyPem(List<int> privateKeyBytes) {
    final base64 = base64Encode(privateKeyBytes);
    final wrapped = _wrapInLines(base64, 64);
    return '-----BEGIN ECHAT DEVICE PRIVATE KEY-----\n$wrapped\n-----END ECHAT DEVICE PRIVATE KEY-----';
  }

  static String _wrapInLines(String data, int chunkSize) {
    final buffer = StringBuffer();
    for (var index = 0; index < data.length; index += chunkSize) {
      final end = index + chunkSize;
      buffer.write(
        data.substring(index, end < data.length ? end : data.length),
      );
      if (end < data.length) {
        buffer.writeln();
      }
    }
    return buffer.toString();
  }
}
