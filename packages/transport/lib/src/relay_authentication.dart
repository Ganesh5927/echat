import 'dart:convert';

import 'packet_transport.dart';

class RelayAuthChallenge {
  const RelayAuthChallenge({
    required this.challengeId,
    required this.nonce,
    required this.expiresAt,
  });

  final String challengeId;
  final String nonce;
  final DateTime expiresAt;

  factory RelayAuthChallenge.fromJson(Map<String, dynamic> json) {
    if (json.length != 3 ||
        !json.keys.toSet().containsAll(const {
          'challengeId',
          'nonce',
          'expiresAt',
        })) {
      throw const TransportException('malformed_relay_response');
    }
    try {
      final challengeId = json['challengeId'];
      final nonce = json['nonce'];
      final expiresAt = json['expiresAt'];
      if (challengeId is! String ||
          !_tokenPattern.hasMatch(challengeId) ||
          nonce is! String ||
          !_tokenPattern.hasMatch(nonce) ||
          expiresAt is! String) {
        throw const TransportException('malformed_relay_response');
      }
      return RelayAuthChallenge(
        challengeId: challengeId,
        nonce: nonce,
        expiresAt: DateTime.parse(expiresAt).toUtc(),
      );
    } on TransportException {
      rethrow;
    } on Object {
      throw const TransportException('malformed_relay_response');
    }
  }

  List<int> signedMessage({
    required String operation,
    required String deviceId,
  }) => utf8.encode(
    'echat-relay-auth-v1\n$operation\n$deviceId\n$challengeId\n$nonce',
  );
}

final RegExp _tokenPattern = RegExp(r'^[A-Za-z0-9_-]{32,128}$');
