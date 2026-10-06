import 'dart:convert';

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

  factory PublicIdentityQrPayload.fromJson(Map<String, dynamic> json) {
    return PublicIdentityQrPayload(
      version: json['version'] as int? ?? 1,
      deviceId: json['deviceId'] as String,
      publicKeyPem: json['publicKeyPem'] as String,
      fingerprint: json['fingerprint'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String),
    );
  }

  Map<String, dynamic> toJson() => {
    'version': version,
    'deviceId': deviceId,
    'publicKeyPem': publicKeyPem,
    'fingerprint': fingerprint,
    'createdAt': createdAt.toUtc().toIso8601String(),
  };

  String toQrString() => const JsonEncoder.withIndent('  ').convert(toJson());

  factory PublicIdentityQrPayload.fromQrString(String value) {
    final decoded = jsonDecode(value) as Map<String, dynamic>;
    return PublicIdentityQrPayload.fromJson(decoded);
  }
}
