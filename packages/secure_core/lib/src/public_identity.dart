import 'dart:convert';

class PublicIdentity {
  const PublicIdentity({
    required this.deviceId,
    required this.publicKeyPem,
    required this.fingerprint,
    required this.createdAt,
    this.status = 'created',
  });

  final String deviceId;
  final String publicKeyPem;
  final String fingerprint;
  final DateTime createdAt;
  final String status;

  factory PublicIdentity.fromJson(Map<String, dynamic> json) {
    return PublicIdentity(
      deviceId: json['deviceId'] as String,
      publicKeyPem: json['publicKeyPem'] as String,
      fingerprint: json['fingerprint'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String),
      status: json['status'] as String? ?? 'created',
    );
  }

  Map<String, dynamic> toJson() => {
        'deviceId': deviceId,
        'publicKeyPem': publicKeyPem,
        'fingerprint': fingerprint,
        'createdAt': createdAt.toUtc().toIso8601String(),
        'status': status,
      };

  String get qrPayloadJson => jsonEncode(toJson());
}
