import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' show sha256;
import 'package:cryptography/cryptography.dart';
import 'package:uuid/uuid.dart';

import 'identity_service.dart';

enum SessionState { pending, established, closed }

class SessionRecord {
  const SessionRecord({
    required this.sessionId,
    required this.localDeviceId,
    required this.remoteDeviceId,
    required this.localIdentityPublicKeyPem,
    required this.remoteIdentityPublicKeyPem,
    required this.sessionStatus,
    required this.createdAt,
    required this.updatedAt,
    required this.sendSequence,
    required this.receiveSequence,
    this.derivedKeyFingerprint = '',
    this.closedReason,
    this.seenMessageIds = const <String>{},
  });

  final String sessionId;
  final String localDeviceId;
  final String remoteDeviceId;
  final String localIdentityPublicKeyPem;
  final String remoteIdentityPublicKeyPem;
  final SessionState sessionStatus;
  final DateTime createdAt;
  final DateTime updatedAt;
  final int sendSequence;
  final int receiveSequence;
  final String derivedKeyFingerprint;
  final String? closedReason;
  final Set<String> seenMessageIds;

  bool get isClosed => sessionStatus == SessionState.closed;
  bool get isEstablished => sessionStatus == SessionState.established;
  bool get isPending => sessionStatus == SessionState.pending;

  SessionRecord copyWith({
    String? sessionId,
    String? localDeviceId,
    String? remoteDeviceId,
    String? localIdentityPublicKeyPem,
    String? remoteIdentityPublicKeyPem,
    SessionState? sessionStatus,
    DateTime? createdAt,
    DateTime? updatedAt,
    int? sendSequence,
    int? receiveSequence,
    String? derivedKeyFingerprint,
    String? closedReason,
    Set<String>? seenMessageIds,
  }) {
    return SessionRecord(
      sessionId: sessionId ?? this.sessionId,
      localDeviceId: localDeviceId ?? this.localDeviceId,
      remoteDeviceId: remoteDeviceId ?? this.remoteDeviceId,
      localIdentityPublicKeyPem:
          localIdentityPublicKeyPem ?? this.localIdentityPublicKeyPem,
      remoteIdentityPublicKeyPem:
          remoteIdentityPublicKeyPem ?? this.remoteIdentityPublicKeyPem,
      sessionStatus: sessionStatus ?? this.sessionStatus,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      sendSequence: sendSequence ?? this.sendSequence,
      receiveSequence: receiveSequence ?? this.receiveSequence,
      derivedKeyFingerprint:
          derivedKeyFingerprint ?? this.derivedKeyFingerprint,
      closedReason: closedReason ?? this.closedReason,
      seenMessageIds: seenMessageIds ?? this.seenMessageIds,
    );
  }

  Map<String, dynamic> toJson() => {
    'sessionId': sessionId,
    'localDeviceId': localDeviceId,
    'remoteDeviceId': remoteDeviceId,
    'localIdentityPublicKeyPem': localIdentityPublicKeyPem,
    'remoteIdentityPublicKeyPem': remoteIdentityPublicKeyPem,
    'sessionStatus': sessionStatus.name,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'updatedAt': updatedAt.toUtc().toIso8601String(),
    'sendSequence': sendSequence,
    'receiveSequence': receiveSequence,
    'derivedKeyFingerprint': derivedKeyFingerprint,
    'closedReason': closedReason,
    'seenMessageIds': seenMessageIds.toList(),
  };

  factory SessionRecord.fromJson(Map<String, dynamic> json) {
    return SessionRecord(
      sessionId: json['sessionId'] as String,
      localDeviceId: json['localDeviceId'] as String,
      remoteDeviceId: json['remoteDeviceId'] as String,
      localIdentityPublicKeyPem: json['localIdentityPublicKeyPem'] as String,
      remoteIdentityPublicKeyPem: json['remoteIdentityPublicKeyPem'] as String,
      sessionStatus: SessionState.values.firstWhere(
        (state) =>
            state.name ==
            (json['sessionStatus'] as String? ?? SessionState.pending.name),
        orElse: () => SessionState.pending,
      ),
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
      sendSequence: json['sendSequence'] as int? ?? 0,
      receiveSequence: json['receiveSequence'] as int? ?? 0,
      derivedKeyFingerprint: json['derivedKeyFingerprint'] as String? ?? '',
      closedReason: json['closedReason'] as String?,
      seenMessageIds: (json['seenMessageIds'] as List<dynamic>? ?? const [])
          .map((entry) => entry.toString())
          .toSet(),
    );
  }
}

class SessionProtocolMessage {
  const SessionProtocolMessage({
    required this.protocolVersion,
    required this.messageType,
    required this.messageId,
    required this.sessionId,
    required this.senderDeviceId,
    required this.recipientDeviceId,
    required this.senderIdentityPublicKeyPem,
    required this.ephemeralPublicKeyBase64,
    required this.sequence,
    required this.nonce,
    required this.payload,
    required this.signature,
    required this.createdAt,
  });

  final int protocolVersion;
  final String messageType;
  final String messageId;
  final String sessionId;
  final String senderDeviceId;
  final String recipientDeviceId;
  final String senderIdentityPublicKeyPem;
  final String ephemeralPublicKeyBase64;
  final int sequence;
  final String nonce;
  final String payload;
  final String signature;
  final DateTime createdAt;

  Map<String, dynamic> toJson() => {
    'protocolVersion': protocolVersion,
    'messageType': messageType,
    'messageId': messageId,
    'sessionId': sessionId,
    'senderDeviceId': senderDeviceId,
    'recipientDeviceId': recipientDeviceId,
    'senderIdentityPublicKeyPem': senderIdentityPublicKeyPem,
    'ephemeralPublicKeyBase64': ephemeralPublicKeyBase64,
    'sequence': sequence,
    'nonce': nonce,
    'payload': payload,
    'signature': signature,
    'createdAt': createdAt.toUtc().toIso8601String(),
  };

  factory SessionProtocolMessage.fromJson(Map<String, dynamic> json) {
    return SessionProtocolMessage(
      protocolVersion: json['protocolVersion'] as int? ?? 2,
      messageType: json['messageType'] as String,
      messageId: json['messageId'] as String,
      sessionId: json['sessionId'] as String,
      senderDeviceId: json['senderDeviceId'] as String,
      recipientDeviceId: json['recipientDeviceId'] as String,
      senderIdentityPublicKeyPem: json['senderIdentityPublicKeyPem'] as String,
      ephemeralPublicKeyBase64: json['ephemeralPublicKeyBase64'] as String,
      sequence: json['sequence'] as int? ?? 0,
      nonce: json['nonce'] as String? ?? '',
      payload: json['payload'] as String? ?? '',
      signature: json['signature'] as String? ?? '',
      createdAt: DateTime.parse(json['createdAt'] as String),
    );
  }

  Map<String, dynamic> unsignedPayload() => {
    'protocolVersion': protocolVersion,
    'messageType': messageType,
    'messageId': messageId,
    'sessionId': sessionId,
    'senderDeviceId': senderDeviceId,
    'recipientDeviceId': recipientDeviceId,
    'senderIdentityPublicKeyPem': senderIdentityPublicKeyPem,
    'ephemeralPublicKeyBase64': ephemeralPublicKeyBase64,
    'sequence': sequence,
    'nonce': nonce,
    'payload': payload,
    'createdAt': createdAt.toUtc().toIso8601String(),
  };
}

class SessionSecretBundle {
  const SessionSecretBundle({
    required this.sessionId,
    required this.sessionKeyHex,
    required this.localEphemeralPrivateKeyBase64,
    required this.remoteEphemeralPublicKeyBase64,
    required this.localIdentityPublicKeyPem,
    required this.remoteIdentityPublicKeyPem,
    required this.derivedKeyFingerprint,
    required this.createdAt,
    required this.updatedAt,
    required this.seenMessageIds,
  });

  final String sessionId;
  final String sessionKeyHex;
  final String localEphemeralPrivateKeyBase64;
  final String remoteEphemeralPublicKeyBase64;
  final String localIdentityPublicKeyPem;
  final String remoteIdentityPublicKeyPem;
  final String derivedKeyFingerprint;
  final DateTime createdAt;
  final DateTime updatedAt;
  final Set<String> seenMessageIds;

  Map<String, dynamic> toJson() => {
    'sessionId': sessionId,
    'sessionKeyHex': sessionKeyHex,
    'localEphemeralPrivateKeyBase64': localEphemeralPrivateKeyBase64,
    'remoteEphemeralPublicKeyBase64': remoteEphemeralPublicKeyBase64,
    'localIdentityPublicKeyPem': localIdentityPublicKeyPem,
    'remoteIdentityPublicKeyPem': remoteIdentityPublicKeyPem,
    'derivedKeyFingerprint': derivedKeyFingerprint,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'updatedAt': updatedAt.toUtc().toIso8601String(),
    'seenMessageIds': seenMessageIds.toList(),
  };

  factory SessionSecretBundle.fromJson(Map<String, dynamic> json) {
    return SessionSecretBundle(
      sessionId: json['sessionId'] as String,
      sessionKeyHex: json['sessionKeyHex'] as String,
      localEphemeralPrivateKeyBase64:
          json['localEphemeralPrivateKeyBase64'] as String,
      remoteEphemeralPublicKeyBase64:
          json['remoteEphemeralPublicKeyBase64'] as String,
      localIdentityPublicKeyPem: json['localIdentityPublicKeyPem'] as String,
      remoteIdentityPublicKeyPem: json['remoteIdentityPublicKeyPem'] as String,
      derivedKeyFingerprint: json['derivedKeyFingerprint'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
      seenMessageIds: (json['seenMessageIds'] as List<dynamic>? ?? const [])
          .map((entry) => entry.toString())
          .toSet(),
    );
  }
}

class SessionEstablishmentResult {
  const SessionEstablishmentResult({
    required this.record,
    required this.response,
  });

  final SessionRecord record;
  final SessionProtocolMessage response;
}

class SessionSendContext {
  const SessionSendContext({
    required this.sequence,
    required this.senderDeviceId,
    required this.recipientDeviceId,
  });

  final int sequence;
  final String senderDeviceId;
  final String recipientDeviceId;
}

class _DerivedSessionKey {
  const _DerivedSessionKey({required this.keyHex, required this.fingerprint});

  final String keyHex;
  final String fingerprint;
}

abstract class SecureSessionStore {
  Future<void> saveSessionRecord(String sessionId, SessionRecord record);
  Future<SessionRecord?> loadSessionRecord(String sessionId);
  Future<void> saveSessionSecret(String sessionId, SessionSecretBundle bundle);
  Future<SessionSecretBundle?> loadSessionSecret(String sessionId);
  Future<void> deleteSession(String sessionId);
  Future<void> deleteSessionSecret(String sessionId);
  Future<bool> hasSession(String sessionId);
}

class MemorySecureSessionStore implements SecureSessionStore {
  final Map<String, SessionRecord> _records = {};
  final Map<String, SessionSecretBundle> _secrets = {};

  @override
  Future<void> saveSessionRecord(String sessionId, SessionRecord record) async {
    _records[sessionId] = record;
  }

  @override
  Future<SessionRecord?> loadSessionRecord(String sessionId) async {
    return _records[sessionId];
  }

  @override
  Future<void> saveSessionSecret(
    String sessionId,
    SessionSecretBundle bundle,
  ) async {
    _secrets[sessionId] = bundle;
  }

  @override
  Future<SessionSecretBundle?> loadSessionSecret(String sessionId) async {
    return _secrets[sessionId];
  }

  @override
  Future<void> deleteSession(String sessionId) async {
    _records.remove(sessionId);
    _secrets.remove(sessionId);
  }

  @override
  Future<void> deleteSessionSecret(String sessionId) async {
    _secrets.remove(sessionId);
  }

  @override
  Future<bool> hasSession(String sessionId) async {
    return _records.containsKey(sessionId) || _secrets.containsKey(sessionId);
  }
}

class SessionService {
  static final Map<String, Future<void>> _sessionLocks = {};

  SessionService({
    required IdentityService identityService,
    required SecureSessionStore sessionStore,
  }) : _identityService = identityService,
       _sessionStore = sessionStore;

  final IdentityService _identityService;
  final SecureSessionStore _sessionStore;

  Future<SessionProtocolMessage> createSession({
    required String remoteDeviceId,
    required String remoteIdentityPublicKeyPem,
    String? localDeviceId,
  }) async {
    final deviceId =
        localDeviceId ?? (await _identityService.loadIdentity())?.deviceId;
    if (deviceId == null) {
      throw StateError(
        'No local device identity available to create a session.',
      );
    }

    final localIdentity = await _identityService.loadIdentity();
    if (localIdentity == null) {
      throw StateError('No local identity is available for session creation.');
    }
    if (deviceId != localIdentity.deviceId) {
      throw const SessionValidationException(
        'The supplied local device ID does not match this identity.',
      );
    }

    final sessionId = const Uuid().v4();
    final ephemeralKeyPair = await X25519().newKeyPair();
    final ephemeralPublicKeyBytes =
        (await ephemeralKeyPair.extractPublicKey()).bytes;
    final ephemeralPublicKeyBase64 = base64Encode(ephemeralPublicKeyBytes);
    final now = DateTime.now().toUtc();

    final payload = {
      'protocolVersion': 2,
      'messageType': 'session-init',
      'messageId': const Uuid().v4(),
      'sessionId': sessionId,
      'senderDeviceId': deviceId,
      'recipientDeviceId': remoteDeviceId,
      'senderIdentityPublicKeyPem': localIdentity.publicKeyPem,
      'ephemeralPublicKeyBase64': ephemeralPublicKeyBase64,
      'sequence': 0,
      'nonce': const Uuid().v4(),
      'payload': jsonEncode({
        'purpose': 'session-init',
        'remoteIdentityPublicKeyPem': remoteIdentityPublicKeyPem,
      }),
      'createdAt': now.toIso8601String(),
    };

    final signature = await _identityService.signIdentityMessage(
      utf8.encode(jsonEncode(payload)),
    );

    final message = SessionProtocolMessage(
      protocolVersion: 2,
      messageType: 'session-init',
      messageId: payload['messageId'] as String,
      sessionId: sessionId,
      senderDeviceId: deviceId,
      recipientDeviceId: remoteDeviceId,
      senderIdentityPublicKeyPem: localIdentity.publicKeyPem,
      ephemeralPublicKeyBase64: ephemeralPublicKeyBase64,
      sequence: 0,
      nonce: payload['nonce'] as String,
      payload: payload['payload'] as String,
      signature: base64Encode(signature.bytes),
      createdAt: now,
    );

    final pendingRecord = SessionRecord(
      sessionId: sessionId,
      localDeviceId: deviceId,
      remoteDeviceId: remoteDeviceId,
      localIdentityPublicKeyPem: localIdentity.publicKeyPem,
      remoteIdentityPublicKeyPem: remoteIdentityPublicKeyPem,
      sessionStatus: SessionState.pending,
      createdAt: now,
      updatedAt: now,
      sendSequence: 0,
      receiveSequence: -1,
      seenMessageIds: <String>{message.messageId},
    );

    final secretBundle = SessionSecretBundle(
      sessionId: sessionId,
      sessionKeyHex: '',
      localEphemeralPrivateKeyBase64: base64Encode(
        (await ephemeralKeyPair.extractPrivateKeyBytes()),
      ),
      remoteEphemeralPublicKeyBase64: '',
      localIdentityPublicKeyPem: localIdentity.publicKeyPem,
      remoteIdentityPublicKeyPem: remoteIdentityPublicKeyPem,
      derivedKeyFingerprint: '',
      createdAt: now,
      updatedAt: now,
      seenMessageIds: <String>{message.messageId},
    );

    await _sessionStore.saveSessionRecord(sessionId, pendingRecord);
    await _sessionStore.saveSessionSecret(sessionId, secretBundle);
    ephemeralKeyPair.destroy();
    return message;
  }

  Future<SessionEstablishmentResult> acceptSession({
    required SessionProtocolMessage message,
    required String localDeviceId,
    required String expectedRemoteIdentityPublicKeyPem,
  }) {
    return _withSessionLock(
      message.sessionId,
      () => _acceptSession(
        message: message,
        localDeviceId: localDeviceId,
        expectedRemoteIdentityPublicKeyPem: expectedRemoteIdentityPublicKeyPem,
      ),
    );
  }

  Future<SessionEstablishmentResult> _acceptSession({
    required SessionProtocolMessage message,
    required String localDeviceId,
    required String expectedRemoteIdentityPublicKeyPem,
  }) async {
    _validateProtocolMessage(message);

    if (message.messageType != 'session-init' || message.sequence != 0) {
      throw const SessionValidationException(
        'Unsupported session initiation message.',
      );
    }

    if (message.recipientDeviceId != localDeviceId) {
      throw const SessionValidationException(
        'Session initiation was not addressed to this device.',
      );
    }
    if (message.senderIdentityPublicKeyPem !=
        expectedRemoteIdentityPublicKeyPem) {
      throw const SessionValidationException(
        'Session initiation identity does not match the verified contact key.',
      );
    }

    final existingRecord = await getSession(message.sessionId);
    if (existingRecord != null &&
        existingRecord.sessionStatus != SessionState.pending) {
      throw const SessionReplayException(
        'Session initiation has already been received.',
      );
    }

    final unsignedJson = jsonEncode(message.unsignedPayload());
    final isValid = await _verifyMessageSignature(
      message: message,
      signedBytes: utf8.encode(unsignedJson),
    );
    if (!isValid) {
      throw const SessionValidationException(
        'Remote identity authentication failed for session establishment.',
      );
    }

    final localIdentity = await _identityService.loadIdentity();
    if (localIdentity == null) {
      throw StateError(
        'No local identity is available for session acceptance.',
      );
    }
    final initiationPayload =
        jsonDecode(message.payload) as Map<String, dynamic>;
    if (initiationPayload['remoteIdentityPublicKeyPem'] !=
        localIdentity.publicKeyPem) {
      throw const SessionValidationException(
        'Session initiation targets a different device identity.',
      );
    }

    final now = DateTime.now().toUtc();
    final localEphemeralKeyPair = await X25519().newKeyPair();
    final localEphemeralPublicKeyBytes =
        (await localEphemeralKeyPair.extractPublicKey()).bytes;
    final remoteEphemeralPublicKey = SimplePublicKey(
      base64Decode(message.ephemeralPublicKeyBase64),
      type: KeyPairType.x25519,
    );
    final sharedSecret = await X25519().sharedSecretKey(
      keyPair: localEphemeralKeyPair,
      remotePublicKey: remoteEphemeralPublicKey,
    );
    final sessionKey = await _deriveSessionKey(
      sharedSecret: sharedSecret,
      sessionId: message.sessionId,
      localDeviceId: localDeviceId,
      remoteDeviceId: message.senderDeviceId,
      localIdentityPem: localIdentity.publicKeyPem,
      remoteIdentityPem: message.senderIdentityPublicKeyPem,
    );
    localEphemeralKeyPair.destroy();

    final sessionKeyFingerprint = sessionKey.fingerprint;
    final sessionRecord = SessionRecord(
      sessionId: message.sessionId,
      localDeviceId: localDeviceId,
      remoteDeviceId: message.senderDeviceId,
      localIdentityPublicKeyPem: localIdentity.publicKeyPem,
      remoteIdentityPublicKeyPem: message.senderIdentityPublicKeyPem,
      sessionStatus: SessionState.established,
      createdAt: now,
      updatedAt: now,
      sendSequence: 0,
      receiveSequence: message.sequence,
      derivedKeyFingerprint: sessionKeyFingerprint,
      seenMessageIds: <String>{message.messageId},
    );

    final responsePayload = {
      'protocolVersion': 2,
      'messageType': 'session-accept',
      'messageId': const Uuid().v4(),
      'sessionId': message.sessionId,
      'senderDeviceId': localDeviceId,
      'recipientDeviceId': message.senderDeviceId,
      'senderIdentityPublicKeyPem': localIdentity.publicKeyPem,
      'ephemeralPublicKeyBase64': base64Encode(localEphemeralPublicKeyBytes),
      'sequence': 0,
      'nonce': const Uuid().v4(),
      'payload': jsonEncode({
        'sessionKeyFingerprint': sessionKeyFingerprint,
        'derivedFrom': 'session-key-derivation',
      }),
      'createdAt': now.toIso8601String(),
    };

    final responseSignature = await _identityService.signIdentityMessage(
      utf8.encode(jsonEncode(responsePayload)),
    );
    final responseMessage = SessionProtocolMessage(
      protocolVersion: 2,
      messageType: 'session-accept',
      messageId: responsePayload['messageId'] as String,
      sessionId: message.sessionId,
      senderDeviceId: localDeviceId,
      recipientDeviceId: message.senderDeviceId,
      senderIdentityPublicKeyPem: localIdentity.publicKeyPem,
      ephemeralPublicKeyBase64:
          responsePayload['ephemeralPublicKeyBase64'] as String,
      sequence: 0,
      nonce: responsePayload['nonce'] as String,
      payload: responsePayload['payload'] as String,
      signature: base64Encode(responseSignature.bytes),
      createdAt: now,
    );

    final secretBundle = SessionSecretBundle(
      sessionId: message.sessionId,
      sessionKeyHex: sessionKey.keyHex,
      localEphemeralPrivateKeyBase64: '',
      remoteEphemeralPublicKeyBase64: message.ephemeralPublicKeyBase64,
      localIdentityPublicKeyPem: localIdentity.publicKeyPem,
      remoteIdentityPublicKeyPem: message.senderIdentityPublicKeyPem,
      derivedKeyFingerprint: sessionKeyFingerprint,
      createdAt: now,
      updatedAt: now,
      seenMessageIds: <String>{message.messageId, responseMessage.messageId},
    );

    await _sessionStore.saveSessionRecord(message.sessionId, sessionRecord);
    await _sessionStore.saveSessionSecret(message.sessionId, secretBundle);

    final result = SessionEstablishmentResult(
      record: sessionRecord,
      response: responseMessage,
    );
    return result;
  }

  Future<SessionRecord> establishAcceptedSession({
    required SessionProtocolMessage message,
    required String localDeviceId,
  }) {
    return _withSessionLock(
      message.sessionId,
      () => _establishAcceptedSession(
        message: message,
        localDeviceId: localDeviceId,
      ),
    );
  }

  Future<SessionRecord> _establishAcceptedSession({
    required SessionProtocolMessage message,
    required String localDeviceId,
  }) async {
    _validateProtocolMessage(message);

    if (message.messageType != 'session-accept') {
      throw const SessionValidationException(
        'Only session-accept messages may be used to finalize a session.',
      );
    }

    final currentSession = await getSession(message.sessionId);
    if (currentSession == null) {
      throw const SessionValidationException('Unknown session reference.');
    }
    if (currentSession.isClosed) {
      throw const SessionReplayException(
        'Session is closed and cannot be resumed.',
      );
    }
    if (!currentSession.isPending ||
        localDeviceId != currentSession.localDeviceId ||
        message.senderDeviceId != currentSession.remoteDeviceId ||
        message.recipientDeviceId != localDeviceId ||
        message.senderIdentityPublicKeyPem !=
            currentSession.remoteIdentityPublicKeyPem ||
        message.sequence <= currentSession.receiveSequence ||
        currentSession.seenMessageIds.contains(message.messageId)) {
      throw const SessionValidationException(
        'Session accept message does not match the pending session.',
      );
    }

    final unsignedJson = jsonEncode(message.unsignedPayload());
    final isValid = await _verifyMessageSignature(
      message: message,
      signedBytes: utf8.encode(unsignedJson),
    );
    if (!isValid) {
      throw const SessionValidationException(
        'Session accept message authentication failed.',
      );
    }

    final sessionSecret = await _sessionStore.loadSessionSecret(
      message.sessionId,
    );
    if (sessionSecret == null) {
      throw const SessionValidationException(
        'Session secret material is missing.',
      );
    }

    final localEphemeralKeyPair = await X25519().newKeyPairFromSeed(
      base64Decode(sessionSecret.localEphemeralPrivateKeyBase64),
    );
    final remoteEphemeralPublicKey = SimplePublicKey(
      base64Decode(message.ephemeralPublicKeyBase64),
      type: KeyPairType.x25519,
    );
    final sharedSecret = await X25519().sharedSecretKey(
      keyPair: localEphemeralKeyPair,
      remotePublicKey: remoteEphemeralPublicKey,
    );
    localEphemeralKeyPair.destroy();
    final sessionKey = await _deriveSessionKey(
      sharedSecret: sharedSecret,
      sessionId: message.sessionId,
      localDeviceId: currentSession.localDeviceId,
      remoteDeviceId: currentSession.remoteDeviceId,
      localIdentityPem: currentSession.localIdentityPublicKeyPem,
      remoteIdentityPem: currentSession.remoteIdentityPublicKeyPem,
    );
    final derivedFingerprint = sessionKey.fingerprint;

    final payloadMap = jsonDecode(message.payload) as Map<String, dynamic>;
    final expectedFingerprint =
        payloadMap['sessionKeyFingerprint'] as String? ?? '';
    if (expectedFingerprint != derivedFingerprint) {
      throw const SessionValidationException(
        'Session key derivation mismatch for accepted session.',
      );
    }

    final updatedSession = currentSession.copyWith(
      sessionStatus: SessionState.established,
      updatedAt: DateTime.now().toUtc(),
      derivedKeyFingerprint: derivedFingerprint,
      receiveSequence: message.sequence,
      sendSequence: 0,
    );

    final updatedSecret = SessionSecretBundle(
      sessionId: sessionSecret.sessionId,
      sessionKeyHex: sessionKey.keyHex,
      localEphemeralPrivateKeyBase64: '',
      remoteEphemeralPublicKeyBase64: message.ephemeralPublicKeyBase64,
      localIdentityPublicKeyPem: sessionSecret.localIdentityPublicKeyPem,
      remoteIdentityPublicKeyPem: sessionSecret.remoteIdentityPublicKeyPem,
      derivedKeyFingerprint: derivedFingerprint,
      createdAt: sessionSecret.createdAt,
      updatedAt: DateTime.now().toUtc(),
      seenMessageIds: sessionSecret.seenMessageIds.union(<String>{
        message.messageId,
      }),
    );

    await _sessionStore.saveSessionRecord(message.sessionId, updatedSession);
    await _sessionStore.saveSessionSecret(message.sessionId, updatedSecret);
    return updatedSession;
  }

  Future<T> withNextSendMessageKey<T>({
    required String sessionId,
    required String messageId,
    int keyEpoch = 0,
    required Future<T> Function(SecretKey key, SessionSendContext context)
    encryptAndBuild,
  }) {
    return _withSessionLock(sessionId, () async {
      if (messageId.isEmpty || keyEpoch != 0) {
        throw const SessionValidationException(
          'Message ID or key epoch is invalid.',
        );
      }
      final record = await getSession(sessionId);
      if (record == null || !record.isEstablished) {
        throw const SessionValidationException('Session is not established.');
      }
      final secret = await _sessionStore.loadSessionSecret(sessionId);
      if (secret == null) {
        throw const SessionValidationException(
          'Session key material is missing.',
        );
      }
      final sequence = record.sendSequence + 1;
      final key = await _deriveMessageKey(
        secret,
        sessionId: sessionId,
        senderDeviceId: record.localDeviceId,
        recipientDeviceId: record.remoteDeviceId,
        messageId: messageId,
        sequence: sequence,
        keyEpoch: keyEpoch,
      );
      try {
        await _sessionStore.saveSessionRecord(
          sessionId,
          record.copyWith(
            sendSequence: sequence,
            updatedAt: DateTime.now().toUtc(),
          ),
        );
      } on Object {
        key.destroy();
        rethrow;
      }
      try {
        return await encryptAndBuild(
          key,
          SessionSendContext(
            sequence: sequence,
            senderDeviceId: record.localDeviceId,
            recipientDeviceId: record.remoteDeviceId,
          ),
        );
      } finally {
        key.destroy();
      }
    });
  }

  Future<T> processReceivedMessage<T>({
    required String sessionId,
    required String senderDeviceId,
    required String recipientDeviceId,
    required String messageId,
    required int sequence,
    int keyEpoch = 0,
    required Future<T> Function(SecretKey messageKey) authenticateAndDecrypt,
  }) {
    return _withSessionLock(sessionId, () async {
      if (messageId.isEmpty || sequence < 1 || keyEpoch != 0) {
        throw const SessionValidationException(
          'Message key context is invalid.',
        );
      }
      final record = await getSession(sessionId);
      if (record == null || !record.isEstablished) {
        throw const SessionValidationException('Session is not established.');
      }
      if (senderDeviceId != record.remoteDeviceId ||
          recipientDeviceId != record.localDeviceId) {
        throw const SessionValidationException(
          'Message direction does not match the session peers.',
        );
      }
      if (sequence <= record.receiveSequence ||
          record.seenMessageIds.contains(messageId)) {
        throw const SessionReplayException(
          'Duplicate or stale message rejected.',
        );
      }
      final secret = await _sessionStore.loadSessionSecret(sessionId);
      if (secret == null) {
        throw const SessionValidationException(
          'Session key material is missing.',
        );
      }
      final key = await _deriveMessageKey(
        secret,
        sessionId: sessionId,
        senderDeviceId: senderDeviceId,
        recipientDeviceId: recipientDeviceId,
        messageId: messageId,
        sequence: sequence,
        keyEpoch: keyEpoch,
      );
      try {
        final result = await authenticateAndDecrypt(key);
        await _sessionStore.saveSessionRecord(
          sessionId,
          record.copyWith(
            receiveSequence: sequence,
            updatedAt: DateTime.now().toUtc(),
            seenMessageIds: record.seenMessageIds.union(<String>{messageId}),
          ),
        );
        return result;
      } finally {
        key.destroy();
      }
    });
  }

  Future<SessionRecord?> getSession(String sessionId) async {
    final record = await _sessionStore.loadSessionRecord(sessionId);
    return record;
  }

  Future<bool> hasSession(String sessionId) async {
    return _sessionStore.hasSession(sessionId);
  }

  Future<void> closeSession(String sessionId) async {
    await _withSessionLock(sessionId, () async {
      final current = await getSession(sessionId);
      if (current == null) {
        return;
      }
      final closed = current.copyWith(
        sessionStatus: SessionState.closed,
        updatedAt: DateTime.now().toUtc(),
        closedReason: 'local session closure',
      );
      await _sessionStore.saveSessionRecord(sessionId, closed);
      await _sessionStore.deleteSessionSecret(sessionId);
    });
  }

  Future<void> removeSession(String sessionId) async {
    await _withSessionLock(sessionId, () async {
      await _sessionStore.deleteSession(sessionId);
    });
  }

  Future<void> registerReceivedPacket({
    required String sessionId,
    required int sequence,
    required String messageId,
  }) {
    return _withSessionLock(
      sessionId,
      () => _registerReceivedPacket(
        sessionId: sessionId,
        sequence: sequence,
        messageId: messageId,
      ),
    );
  }

  Future<void> _registerReceivedPacket({
    required String sessionId,
    required int sequence,
    required String messageId,
  }) async {
    final current = await getSession(sessionId);
    if (current == null) {
      throw const SessionValidationException('Unknown session reference.');
    }
    if (current.isClosed) {
      throw const SessionReplayException(
        'Session is closed and cannot accept packets.',
      );
    }
    if (!current.isEstablished) {
      throw const SessionValidationException('Session is not established.');
    }
    if (current.seenMessageIds.contains(messageId)) {
      throw const SessionReplayException(
        'Duplicate packet message ID rejected.',
      );
    }
    if (sequence <= current.receiveSequence) {
      throw const SessionReplayException(
        'Duplicate or stale packet sequence rejected.',
      );
    }

    final updated = current.copyWith(
      receiveSequence: sequence,
      updatedAt: DateTime.now().toUtc(),
      seenMessageIds: current.seenMessageIds.union(<String>{messageId}),
    );
    await _sessionStore.saveSessionRecord(sessionId, updated);
  }

  void _validateProtocolMessage(SessionProtocolMessage message) {
    if (message.protocolVersion != 2) {
      throw const SessionValidationException(
        'Unsupported session protocol version.',
      );
    }
    if (message.messageId.isEmpty || message.sessionId.isEmpty) {
      throw const SessionValidationException('Malformed session message.');
    }
    if (message.senderDeviceId.isEmpty || message.recipientDeviceId.isEmpty) {
      throw const SessionValidationException(
        'Malformed session identity references.',
      );
    }
    if (message.senderIdentityPublicKeyPem.isEmpty ||
        message.ephemeralPublicKeyBase64.isEmpty) {
      throw const SessionValidationException(
        'Session authentication data is incomplete.',
      );
    }
    if (message.signature.isEmpty) {
      throw const SessionValidationException(
        'Session authentication is missing.',
      );
    }
    if (message.sequence < 0) {
      throw const SessionValidationException(
        'Session sequence cannot be negative.',
      );
    }
    try {
      if (base64Decode(message.ephemeralPublicKeyBase64).length != 32) {
        throw const SessionValidationException(
          'Invalid ephemeral public key length.',
        );
      }
      if (jsonDecode(message.payload) is! Map<String, dynamic>) {
        throw const SessionValidationException(
          'Session payload must be a JSON object.',
        );
      }
    } on FormatException {
      throw const SessionValidationException(
        'Session message encoding is invalid.',
      );
    }
  }

  Future<_DerivedSessionKey> _deriveSessionKey({
    required SecretKey sharedSecret,
    required String sessionId,
    required String localDeviceId,
    required String remoteDeviceId,
    required String localIdentityPem,
    required String remoteIdentityPem,
  }) async {
    final keyMaterial = Uint8List.fromList(await sharedSecret.extractBytes());
    final keyMaterialKey = SecretKeyData(
      keyMaterial,
      overwriteWhenDestroyed: true,
    );
    try {
      final derived = await Hkdf(hmac: Hmac.sha256(), outputLength: 32)
          .deriveKey(
            secretKey: keyMaterialKey,
            nonce: utf8.encode(
              _sessionContext(
                sessionId: sessionId,
                localDeviceId: localDeviceId,
                remoteDeviceId: remoteDeviceId,
                localIdentityPem: localIdentityPem,
                remoteIdentityPem: remoteIdentityPem,
              ),
            ),
            info: utf8.encode('echat.session.v2'),
          );
      try {
        final derivedBytes = await derived.extractBytes();
        return _DerivedSessionKey(
          keyHex: _hex(derivedBytes),
          fingerprint: _fingerprintBytes(derivedBytes),
        );
      } finally {
        derived.destroy();
      }
    } finally {
      keyMaterialKey.destroy();
      sharedSecret.destroy();
    }
  }

  Future<SecretKeyData> _deriveMessageKey(
    SessionSecretBundle sessionSecret, {
    required String sessionId,
    required String senderDeviceId,
    required String recipientDeviceId,
    required String messageId,
    required int sequence,
    required int keyEpoch,
  }) async {
    final rootBytes = _decodeHex(sessionSecret.sessionKeyHex);
    if (rootBytes.length != 32) {
      throw const SessionValidationException('Stored session key is invalid.');
    }
    final rootKey = SecretKeyData(rootBytes, overwriteWhenDestroyed: true);
    try {
      final context = jsonEncode({
        'domain': 'echat.message-key.v1',
        'sessionId': sessionId,
        'senderDeviceId': senderDeviceId,
        'recipientDeviceId': recipientDeviceId,
        'messageId': messageId,
        'sequence': sequence,
        'keyEpoch': keyEpoch,
      });
      final derived = await Hkdf(hmac: Hmac.sha256(), outputLength: 32)
          .deriveKey(
            secretKey: rootKey,
            nonce: utf8.encode('echat.message-key.salt.v1'),
            info: utf8.encode(context),
          );
      final derivedBytes = await derived.extractBytes();
      final ownedBytes = Uint8List.fromList(derivedBytes);
      derived.destroy();
      return SecretKeyData(ownedBytes, overwriteWhenDestroyed: true);
    } finally {
      rootKey.destroy();
      rootBytes.fillRange(0, rootBytes.length, 0);
    }
  }

  List<int> _decodeHex(String value) {
    if (value.length.isOdd || !RegExp(r'^[0-9a-fA-F]*$').hasMatch(value)) {
      throw const SessionValidationException(
        'Stored session key is malformed.',
      );
    }
    return [
      for (var index = 0; index < value.length; index += 2)
        int.parse(value.substring(index, index + 2), radix: 16),
    ];
  }

  Future<T> _withSessionLock<T>(
    String sessionId,
    Future<T> Function() operation,
  ) async {
    final previous = _sessionLocks[sessionId] ?? Future<void>.value();
    final release = Completer<void>();
    final queued = previous.then((_) => release.future);
    _sessionLocks[sessionId] = queued;
    await previous;
    try {
      return await operation();
    } finally {
      release.complete();
      if (identical(_sessionLocks[sessionId], queued)) {
        _sessionLocks.remove(sessionId);
      }
    }
  }

  Future<bool> _verifyMessageSignature({
    required SessionProtocolMessage message,
    required List<int> signedBytes,
  }) async {
    try {
      final signatureBytes = base64Decode(message.signature);
      final publicKey = _decodeEd25519PublicKeyPem(
        message.senderIdentityPublicKeyPem,
      );
      if (signatureBytes.length != 64 || publicKey.bytes.length != 32) {
        return false;
      }
      return Ed25519().verify(
        signedBytes,
        signature: Signature(signatureBytes, publicKey: publicKey),
      );
    } on FormatException {
      return false;
    } on ArgumentError {
      return false;
    } on StateError {
      return false;
    }
  }

  String _fingerprintBytes(List<int> bytes) {
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  String _hex(List<int> bytes) =>
      bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();

  SimplePublicKey _decodeEd25519PublicKeyPem(String pem) {
    final sanitized = pem
        .replaceAll('-----BEGIN ECHAT DEVICE PUBLIC KEY-----', '')
        .replaceAll('-----END ECHAT DEVICE PUBLIC KEY-----', '')
        .replaceAll('\n', '')
        .replaceAll('\r', '')
        .trim();
    return SimplePublicKey(base64Decode(sanitized), type: KeyPairType.ed25519);
  }

  String _sessionContext({
    required String sessionId,
    required String localDeviceId,
    required String remoteDeviceId,
    required String localIdentityPem,
    required String remoteIdentityPem,
  }) {
    final peers = <(String, String)>[
      (localDeviceId, localIdentityPem),
      (remoteDeviceId, remoteIdentityPem),
    ]..sort((left, right) => left.$1.compareTo(right.$1));
    return 'echat.session.v2|$sessionId|${peers[0].$1}|${peers[1].$1}|${peers[0].$2}|${peers[1].$2}';
  }
}

class SessionValidationException implements Exception {
  const SessionValidationException(this.message);
  final String message;

  @override
  String toString() => 'SessionValidationException: $message';
}

class SessionReplayException implements Exception {
  const SessionReplayException(this.message);
  final String message;

  @override
  String toString() => 'SessionReplayException: $message';
}
