import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:echat_identity/echat_identity.dart';
import 'package:echat_transport/echat_transport.dart';

import 'relay_device_store.dart';
import 'relay_service.dart';

class RelayDeviceAuthenticator extends RelayAuthenticator {
  RelayDeviceAuthenticator({
    required RelayDeviceStore deviceStore,
    DateTime Function()? clock,
    this.challengeLifetime = const Duration(minutes: 2),
    this.tokenLifetime = const Duration(minutes: 15),
    this.maxPendingChallenges = 10000,
  }) : _deviceStore = deviceStore,
       _clock = clock ?? DateTime.now {
    if (challengeLifetime <= Duration.zero ||
        tokenLifetime <= Duration.zero ||
        maxPendingChallenges < 1) {
      throw ArgumentError('Relay authentication configuration is invalid.');
    }
  }

  static const _deviceIdPattern =
      r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-4[0-9a-fA-F]{3}-[89aAbB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$';

  final RelayDeviceStore _deviceStore;
  final DateTime Function() _clock;
  final Duration challengeLifetime;
  final Duration tokenLifetime;
  final int maxPendingChallenges;
  final Random _random = Random.secure();
  final Map<String, _PendingChallenge> _challenges = {};
  final Map<String, _BearerToken> _tokens = {};
  final Map<String, RelayRegisteredDevice> _devices = {};
  Future<void>? _initialization;
  Future<void> _registrationTail = Future<void>.value();

  Future<void> initialize() => _initialization ??= _restoreDevices();

  @override
  Future<String?> authenticate(String? authorizationHeader) async {
    await initialize();
    if (authorizationHeader == null ||
        !authorizationHeader.startsWith('Bearer ')) {
      return null;
    }
    final token = authorizationHeader.substring(7);
    if (!_tokenPattern.hasMatch(token)) return null;
    final bearer = _tokens[token];
    if (bearer == null || !bearer.expiresAt.isAfter(_clock().toUtc())) {
      _tokens.remove(token);
      return null;
    }
    return bearer.deviceId;
  }

  @override
  Future<bool> isRegisteredDeviceRoute(String routeId) async {
    await initialize();
    return _devices.containsKey(routeId);
  }

  Future<RelayAuthChallenge> issueChallenge({
    required String deviceId,
    required String operation,
  }) async {
    await initialize();
    _validateDeviceIdOrThrow(deviceId);
    if (operation != 'register' && operation != 'authenticate') {
      throw const RelayAuthenticationException('invalid_auth_request', 400);
    }
    if (operation == 'authenticate' && !_devices.containsKey(deviceId)) {
      throw const RelayAuthenticationException('unauthorized', 401);
    }
    _removeExpiredState();
    if (_challenges.length >= maxPendingChallenges) {
      throw const RelayAuthenticationException('server_busy', 503);
    }
    final challengeId = _randomToken();
    final nonce = _randomToken();
    final expiresAt = _clock().toUtc().add(challengeLifetime);
    _challenges[challengeId] = _PendingChallenge(
      deviceId: deviceId,
      operation: operation,
      nonce: nonce,
      expiresAt: expiresAt,
    );
    return RelayAuthChallenge(
      challengeId: challengeId,
      nonce: nonce,
      expiresAt: expiresAt,
    );
  }

  Future<void> registerDevice({
    required String deviceId,
    required String publicKeyPem,
    required String fingerprint,
    required DateTime createdAt,
    required String challengeId,
    required String signature,
  }) {
    final previous = _registrationTail;
    final release = Completer<void>();
    _registrationTail = release.future;
    return () async {
      await previous;
      try {
        await _registerDevice(
          deviceId: deviceId,
          publicKeyPem: publicKeyPem,
          fingerprint: fingerprint,
          createdAt: createdAt,
          challengeId: challengeId,
          signature: signature,
        );
      } finally {
        release.complete();
      }
    }();
  }

  Future<void> _registerDevice({
    required String deviceId,
    required String publicKeyPem,
    required String fingerprint,
    required DateTime createdAt,
    required String challengeId,
    required String signature,
  }) async {
    final challenge = _takeChallenge(
      challengeId: challengeId,
      deviceId: deviceId,
      operation: 'register',
    );
    final payload = PublicIdentityQrPayload(
      version: PublicIdentityQrPayload.currentVersion,
      deviceId: deviceId,
      publicKeyPem: publicKeyPem,
      fingerprint: fingerprint,
      createdAt: createdAt.toUtc(),
    );
    try {
      payload.validate();
    } on PublicIdentityFormatException {
      throw const RelayAuthenticationException('invalid_registration', 400);
    }
    final publicKeyBytes = _publicKeyBytes(publicKeyPem);
    if (!await _verifySignature(
      publicKeyBytes: publicKeyBytes,
      signature: signature,
      message: RelayAuthChallenge(
        challengeId: challengeId,
        nonce: challenge.nonce,
        expiresAt: challenge.expiresAt,
      ).signedMessage(operation: 'register', deviceId: deviceId),
    )) {
      throw const RelayAuthenticationException('invalid_signature', 401);
    }

    final existing = _devices[deviceId];
    if (existing != null &&
        (existing.publicKeyPem != publicKeyPem ||
            existing.fingerprint != fingerprint)) {
      throw const RelayAuthenticationException('device_id_conflict', 409);
    }
    if (existing != null) return;
    final registration = RelayRegisteredDevice(
      deviceId: deviceId,
      publicKeyPem: publicKeyPem,
      fingerprint: fingerprint,
      registeredAt: _clock().toUtc(),
    );
    await _deviceStore.save(registration);
    _devices[deviceId] = registration;
  }

  Future<RelayBearerCredential> authenticateDevice({
    required String deviceId,
    required String challengeId,
    required String signature,
  }) async {
    await initialize();
    final registration = _devices[deviceId];
    if (registration == null) {
      throw const RelayAuthenticationException('unauthorized', 401);
    }
    final challenge = _takeChallenge(
      challengeId: challengeId,
      deviceId: deviceId,
      operation: 'authenticate',
    );
    if (!await _verifySignature(
      publicKeyBytes: _publicKeyBytes(registration.publicKeyPem),
      signature: signature,
      message: RelayAuthChallenge(
        challengeId: challengeId,
        nonce: challenge.nonce,
        expiresAt: challenge.expiresAt,
      ).signedMessage(operation: 'authenticate', deviceId: deviceId),
    )) {
      throw const RelayAuthenticationException('invalid_signature', 401);
    }
    final token = _randomToken();
    final expiresAt = _clock().toUtc().add(tokenLifetime);
    _tokens[token] = _BearerToken(deviceId: deviceId, expiresAt: expiresAt);
    return RelayBearerCredential(token: token, expiresAt: expiresAt);
  }

  _PendingChallenge _takeChallenge({
    required String challengeId,
    required String deviceId,
    required String operation,
  }) {
    final challenge = _challenges.remove(challengeId);
    if (challenge == null ||
        challenge.deviceId != deviceId ||
        challenge.operation != operation ||
        !challenge.expiresAt.isAfter(_clock().toUtc())) {
      throw const RelayAuthenticationException('invalid_auth_challenge', 401);
    }
    return challenge;
  }

  Future<void> _restoreDevices() async {
    for (final device in await _deviceStore.loadAll()) {
      final existing = _devices[device.deviceId];
      if (existing != null) {
        throw const FormatException('Duplicate relay device registration.');
      }
      _devices[device.deviceId] = device;
    }
  }

  void _removeExpiredState() {
    final now = _clock().toUtc();
    _challenges.removeWhere(
      (_, challenge) => !challenge.expiresAt.isAfter(now),
    );
    _tokens.removeWhere((_, token) => !token.expiresAt.isAfter(now));
  }

  void _validateDeviceIdOrThrow(String deviceId) {
    if (!RegExp(_deviceIdPattern).hasMatch(deviceId)) {
      throw const RelayAuthenticationException('invalid_registration', 400);
    }
  }

  String _randomToken() {
    final bytes = List<int>.generate(32, (_) => _random.nextInt(256));
    return base64UrlEncode(bytes).replaceAll('=', '');
  }

  static final _tokenPattern = RegExp(r'^[A-Za-z0-9_-]{43}$');

  static List<int> _publicKeyBytes(String pem) {
    const begin = '-----BEGIN ECHAT DEVICE PUBLIC KEY-----\n';
    const end = '\n-----END ECHAT DEVICE PUBLIC KEY-----';
    final encoded = pem
        .substring(begin.length, pem.length - end.length)
        .replaceAll('\n', '')
        .replaceAll('\r', '');
    return base64Decode(encoded);
  }

  static Future<bool> _verifySignature({
    required List<int> publicKeyBytes,
    required String signature,
    required List<int> message,
  }) async {
    try {
      final bytes = base64Decode(signature);
      if (bytes.length != 64 || base64Encode(bytes) != signature) return false;
      return await Ed25519().verify(
        message,
        signature: Signature(
          bytes,
          publicKey: SimplePublicKey(publicKeyBytes, type: KeyPairType.ed25519),
        ),
      );
    } on Object {
      return false;
    }
  }
}

class RelayBearerCredential {
  const RelayBearerCredential({required this.token, required this.expiresAt});

  final String token;
  final DateTime expiresAt;
}

class RelayAuthenticationException implements Exception {
  const RelayAuthenticationException(this.code, this.statusCode);

  final String code;
  final int statusCode;
}

class _PendingChallenge {
  const _PendingChallenge({
    required this.deviceId,
    required this.operation,
    required this.nonce,
    required this.expiresAt,
  });

  final String deviceId;
  final String operation;
  final String nonce;
  final DateTime expiresAt;
}

class _BearerToken {
  const _BearerToken({required this.deviceId, required this.expiresAt});

  final String deviceId;
  final DateTime expiresAt;
}
