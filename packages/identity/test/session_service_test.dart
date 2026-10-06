import 'dart:convert';

import 'package:echat_identity/echat_identity.dart';
import 'package:test/test.dart';

void main() {
  group('SessionService', () {
    Future<List<dynamic>> _createPair() async {
      final aIdentityService = IdentityService(
        store: MemorySecureIdentityStore(),
      );
      final bIdentityService = IdentityService(
        store: MemorySecureIdentityStore(),
      );
      final aDevice = await aIdentityService.createIdentity();
      final bDevice = await bIdentityService.createIdentity();

      final aSessionService = SessionService(
        identityService: aIdentityService,
        sessionStore: MemorySecureSessionStore(),
      );
      final bSessionService = SessionService(
        identityService: bIdentityService,
        sessionStore: MemorySecureSessionStore(),
      );

      return [
        aIdentityService,
        bIdentityService,
        aDevice,
        bDevice,
        aSessionService,
        bSessionService,
      ];
    }

    SessionProtocolMessage _withSignature(
      SessionProtocolMessage message,
      String signature,
    ) {
      return SessionProtocolMessage(
        protocolVersion: message.protocolVersion,
        messageType: message.messageType,
        messageId: message.messageId,
        sessionId: message.sessionId,
        senderDeviceId: message.senderDeviceId,
        recipientDeviceId: message.recipientDeviceId,
        senderIdentityPublicKeyPem: message.senderIdentityPublicKeyPem,
        ephemeralPublicKeyBase64: message.ephemeralPublicKeyBase64,
        sequence: message.sequence,
        nonce: message.nonce,
        payload: message.payload,
        signature: signature,
        createdAt: message.createdAt,
      );
    }

    test('two devices successfully establish a session', () async {
      final items = await _createPair();
      final aSession = items[4] as SessionService;
      final bSession = items[5] as SessionService;
      final aDevice = items[2] as DeviceIdentity;
      final bDevice = items[3] as DeviceIdentity;

      final initiation = await aSession.createSession(
        remoteDeviceId: bDevice.deviceId,
        remoteIdentityPublicKeyPem: bDevice.publicKeyPem,
        localDeviceId: aDevice.deviceId,
      );
      final result = await bSession.acceptSession(
        message: initiation,
        localDeviceId: bDevice.deviceId,
        expectedRemoteIdentityPublicKeyPem: aDevice.publicKeyPem,
      );
      final finalized = await aSession.establishAcceptedSession(
        message: result.response,
        localDeviceId: aDevice.deviceId,
      );

      expect(finalized.sessionStatus, SessionState.established);
      expect(result.record.sessionStatus, SessionState.established);
      expect(finalized.derivedKeyFingerprint, isNotEmpty);
    });

    test('both sides derive matching session material', () async {
      final items = await _createPair();
      final aSession = items[4] as SessionService;
      final bSession = items[5] as SessionService;
      final aDevice = items[2] as DeviceIdentity;
      final bDevice = items[3] as DeviceIdentity;

      final initiation = await aSession.createSession(
        remoteDeviceId: bDevice.deviceId,
        remoteIdentityPublicKeyPem: bDevice.publicKeyPem,
        localDeviceId: aDevice.deviceId,
      );
      final result = await bSession.acceptSession(
        message: initiation,
        localDeviceId: bDevice.deviceId,
        expectedRemoteIdentityPublicKeyPem: aDevice.publicKeyPem,
      );
      final finalized = await aSession.establishAcceptedSession(
        message: result.response,
        localDeviceId: aDevice.deviceId,
      );

      final bStored = await bSession.getSession(initiation.sessionId);
      expect(
        finalized.derivedKeyFingerprint,
        equals(bStored!.derivedKeyFingerprint),
      );
    });

    test('different sessions produce independent key material', () async {
      final items = await _createPair();
      final aSession = items[4] as SessionService;
      final bSession = items[5] as SessionService;
      final aDevice = items[2] as DeviceIdentity;
      final bDevice = items[3] as DeviceIdentity;

      final leftInitiation = await aSession.createSession(
        remoteDeviceId: bDevice.deviceId,
        remoteIdentityPublicKeyPem: bDevice.publicKeyPem,
        localDeviceId: aDevice.deviceId,
      );
      final leftResult = await bSession.acceptSession(
        message: leftInitiation,
        localDeviceId: bDevice.deviceId,
        expectedRemoteIdentityPublicKeyPem: aDevice.publicKeyPem,
      );
      await aSession.establishAcceptedSession(
        message: leftResult.response,
        localDeviceId: aDevice.deviceId,
      );

      final rightInitiation = await aSession.createSession(
        remoteDeviceId: bDevice.deviceId,
        remoteIdentityPublicKeyPem: bDevice.publicKeyPem,
        localDeviceId: aDevice.deviceId,
      );
      final rightResult = await bSession.acceptSession(
        message: rightInitiation,
        localDeviceId: bDevice.deviceId,
        expectedRemoteIdentityPublicKeyPem: aDevice.publicKeyPem,
      );
      await aSession.establishAcceptedSession(
        message: rightResult.response,
        localDeviceId: aDevice.deviceId,
      );

      expect(
        leftResult.record.derivedKeyFingerprint,
        isNot(equals(rightResult.record.derivedKeyFingerprint)),
      );
    });

    test('wrong identity authentication fails', () async {
      final items = await _createPair();
      final aSession = items[4] as SessionService;
      final bSession = items[5] as SessionService;
      final aDevice = items[2] as DeviceIdentity;
      final bDevice = items[3] as DeviceIdentity;

      final initiation = await aSession.createSession(
        remoteDeviceId: bDevice.deviceId,
        remoteIdentityPublicKeyPem: bDevice.publicKeyPem,
        localDeviceId: aDevice.deviceId,
      );

      final tamperedMessage = SessionProtocolMessage(
        protocolVersion: initiation.protocolVersion,
        messageType: initiation.messageType,
        messageId: initiation.messageId,
        sessionId: initiation.sessionId,
        senderDeviceId: initiation.senderDeviceId,
        recipientDeviceId: initiation.recipientDeviceId,
        senderIdentityPublicKeyPem: bDevice.publicKeyPem,
        ephemeralPublicKeyBase64: initiation.ephemeralPublicKeyBase64,
        sequence: initiation.sequence,
        nonce: initiation.nonce,
        payload: initiation.payload,
        signature: initiation.signature,
        createdAt: initiation.createdAt,
      );

      expect(
        () => bSession.acceptSession(
          message: tamperedMessage,
          localDeviceId: bDevice.deviceId,
          expectedRemoteIdentityPublicKeyPem: aDevice.publicKeyPem,
        ),
        throwsA(isA<SessionValidationException>()),
      );
    });

    test('tampered session data is rejected', () async {
      final items = await _createPair();
      final aSession = items[4] as SessionService;
      final bSession = items[5] as SessionService;
      final aDevice = items[2] as DeviceIdentity;
      final bDevice = items[3] as DeviceIdentity;

      final initiation = await aSession.createSession(
        remoteDeviceId: bDevice.deviceId,
        remoteIdentityPublicKeyPem: bDevice.publicKeyPem,
        localDeviceId: aDevice.deviceId,
      );

      final tampered = _withSignature(initiation, initiation.signature);
      final mutatedPayload = jsonEncode({
        ...jsonDecode(tampered.payload) as Map<String, dynamic>,
        'tampered': true,
      });

      final invalid = SessionProtocolMessage(
        protocolVersion: tampered.protocolVersion,
        messageType: tampered.messageType,
        messageId: tampered.messageId,
        sessionId: tampered.sessionId,
        senderDeviceId: tampered.senderDeviceId,
        recipientDeviceId: tampered.recipientDeviceId,
        senderIdentityPublicKeyPem: tampered.senderIdentityPublicKeyPem,
        ephemeralPublicKeyBase64: tampered.ephemeralPublicKeyBase64,
        sequence: tampered.sequence,
        nonce: tampered.nonce,
        payload: mutatedPayload,
        signature: tampered.signature,
        createdAt: tampered.createdAt,
      );

      expect(
        () => bSession.acceptSession(
          message: invalid,
          localDeviceId: bDevice.deviceId,
          expectedRemoteIdentityPublicKeyPem: aDevice.publicKeyPem,
        ),
        throwsA(isA<SessionValidationException>()),
      );
    });

    test('invalid signatures are rejected safely', () async {
      final items = await _createPair();
      final aSession = items[4] as SessionService;
      final bSession = items[5] as SessionService;
      final aDevice = items[2] as DeviceIdentity;
      final bDevice = items[3] as DeviceIdentity;

      final initiation = await aSession.createSession(
        remoteDeviceId: bDevice.deviceId,
        remoteIdentityPublicKeyPem: bDevice.publicKeyPem,
        localDeviceId: aDevice.deviceId,
      );

      final mutated = SessionProtocolMessage(
        protocolVersion: initiation.protocolVersion,
        messageType: initiation.messageType,
        messageId: initiation.messageId,
        sessionId: initiation.sessionId,
        senderDeviceId: initiation.senderDeviceId,
        recipientDeviceId: initiation.recipientDeviceId,
        senderIdentityPublicKeyPem: initiation.senderIdentityPublicKeyPem,
        ephemeralPublicKeyBase64: initiation.ephemeralPublicKeyBase64,
        sequence: initiation.sequence,
        nonce: initiation.nonce,
        payload: initiation.payload,
        signature: base64Encode([0, 1, 2, 3]),
        createdAt: initiation.createdAt,
      );

      expect(
        () => bSession.acceptSession(
          message: mutated,
          localDeviceId: bDevice.deviceId,
          expectedRemoteIdentityPublicKeyPem: aDevice.publicKeyPem,
        ),
        throwsA(isA<SessionValidationException>()),
      );
    });

    test('replay of session-establishment data is rejected', () async {
      final items = await _createPair();
      final aSession = items[4] as SessionService;
      final bSession = items[5] as SessionService;
      final aDevice = items[2] as DeviceIdentity;
      final bDevice = items[3] as DeviceIdentity;

      final initiation = await aSession.createSession(
        remoteDeviceId: bDevice.deviceId,
        remoteIdentityPublicKeyPem: bDevice.publicKeyPem,
        localDeviceId: aDevice.deviceId,
      );

      await bSession.acceptSession(
        message: initiation,
        localDeviceId: bDevice.deviceId,
        expectedRemoteIdentityPublicKeyPem: aDevice.publicKeyPem,
      );

      expect(
        () => bSession.acceptSession(
          message: initiation,
          localDeviceId: bDevice.deviceId,
          expectedRemoteIdentityPublicKeyPem: aDevice.publicKeyPem,
        ),
        throwsA(isA<SessionReplayException>()),
      );
    });

    test('concurrent duplicate initiations are accepted only once', () async {
      final items = await _createPair();
      final aSession = items[4] as SessionService;
      final bSession = items[5] as SessionService;
      final aDevice = items[2] as DeviceIdentity;
      final bDevice = items[3] as DeviceIdentity;
      final initiation = await aSession.createSession(
        remoteDeviceId: bDevice.deviceId,
        remoteIdentityPublicKeyPem: bDevice.publicKeyPem,
        localDeviceId: aDevice.deviceId,
      );

      Future<Object> attemptAcceptance() async {
        try {
          return await bSession.acceptSession(
            message: initiation,
            localDeviceId: bDevice.deviceId,
            expectedRemoteIdentityPublicKeyPem: aDevice.publicKeyPem,
          );
        } on Object catch (error) {
          return error;
        }
      }

      final outcomes = await Future.wait([
        attemptAcceptance(),
        attemptAcceptance(),
      ]);

      expect(outcomes.whereType<SessionEstablishmentResult>(), hasLength(1));
      expect(outcomes.whereType<SessionReplayException>(), hasLength(1));
    });

    test('duplicate session packets are handled safely', () async {
      final items = await _createPair();
      final aSession = items[4] as SessionService;
      final bSession = items[5] as SessionService;
      final aDevice = items[2] as DeviceIdentity;
      final bDevice = items[3] as DeviceIdentity;

      final initiation = await aSession.createSession(
        remoteDeviceId: bDevice.deviceId,
        remoteIdentityPublicKeyPem: bDevice.publicKeyPem,
        localDeviceId: aDevice.deviceId,
      );
      final result = await bSession.acceptSession(
        message: initiation,
        localDeviceId: bDevice.deviceId,
        expectedRemoteIdentityPublicKeyPem: aDevice.publicKeyPem,
      );
      await aSession.establishAcceptedSession(
        message: result.response,
        localDeviceId: aDevice.deviceId,
      );

      await aSession.registerReceivedPacket(
        sessionId: initiation.sessionId,
        sequence: 10,
        messageId: 'dup-1',
      );
      await expectLater(
        aSession.registerReceivedPacket(
          sessionId: initiation.sessionId,
          sequence: 10,
          messageId: 'dup-1',
        ),
        throwsA(isA<SessionReplayException>()),
      );
    });

    test('invalid sequence values are rejected safely', () async {
      final items = await _createPair();
      final aSession = items[4] as SessionService;
      final bSession = items[5] as SessionService;
      final aDevice = items[2] as DeviceIdentity;
      final bDevice = items[3] as DeviceIdentity;

      final initiation = await aSession.createSession(
        remoteDeviceId: bDevice.deviceId,
        remoteIdentityPublicKeyPem: bDevice.publicKeyPem,
        localDeviceId: aDevice.deviceId,
      );
      final result = await bSession.acceptSession(
        message: initiation,
        localDeviceId: bDevice.deviceId,
        expectedRemoteIdentityPublicKeyPem: aDevice.publicKeyPem,
      );
      await aSession.establishAcceptedSession(
        message: result.response,
        localDeviceId: aDevice.deviceId,
      );

      expect(
        () => aSession.registerReceivedPacket(
          sessionId: initiation.sessionId,
          sequence: 0,
          messageId: 'zero-seq',
        ),
        throwsA(isA<SessionReplayException>()),
      );
    });

    test('unknown session references fail safely', () async {
      final items = await _createPair();
      final aSession = items[4] as SessionService;
      final aDevice = items[2] as DeviceIdentity;
      final bDevice = items[3] as DeviceIdentity;

      final initiation = await aSession.createSession(
        remoteDeviceId: bDevice.deviceId,
        remoteIdentityPublicKeyPem: bDevice.publicKeyPem,
        localDeviceId: aDevice.deviceId,
      );

      expect(
        () => aSession.registerReceivedPacket(
          sessionId: 'missing-session',
          sequence: 1,
          messageId: 'x',
        ),
        throwsA(isA<SessionValidationException>()),
      );
      expect(
        () => aSession.establishAcceptedSession(
          message: initiation,
          localDeviceId: aDevice.deviceId,
        ),
        throwsA(isA<SessionValidationException>()),
      );
    });

    test('session closure prevents further use', () async {
      final items = await _createPair();
      final aSession = items[4] as SessionService;
      final bSession = items[5] as SessionService;
      final aDevice = items[2] as DeviceIdentity;
      final bDevice = items[3] as DeviceIdentity;

      final initiation = await aSession.createSession(
        remoteDeviceId: bDevice.deviceId,
        remoteIdentityPublicKeyPem: bDevice.publicKeyPem,
        localDeviceId: aDevice.deviceId,
      );
      final result = await bSession.acceptSession(
        message: initiation,
        localDeviceId: bDevice.deviceId,
        expectedRemoteIdentityPublicKeyPem: aDevice.publicKeyPem,
      );
      await aSession.establishAcceptedSession(
        message: result.response,
        localDeviceId: aDevice.deviceId,
      );

      await aSession.closeSession(initiation.sessionId);
      expect(await aSession.hasSession(initiation.sessionId), isTrue);
      expect(
        (await aSession.getSession(initiation.sessionId))!.sessionStatus,
        SessionState.closed,
      );
    });

    test(
      'session state survives restart when backed by the same store',
      () async {
        final aSessionStore = MemorySecureSessionStore();
        final bSessionStore = MemorySecureSessionStore();
        final aIdentityService = IdentityService(
          store: MemorySecureIdentityStore(),
        );
        final bIdentityService = IdentityService(
          store: MemorySecureIdentityStore(),
        );
        final aDevice = await aIdentityService.createIdentity();
        final bDevice = await bIdentityService.createIdentity();
        final aSessionService = SessionService(
          identityService: aIdentityService,
          sessionStore: aSessionStore,
        );
        final bSessionService = SessionService(
          identityService: bIdentityService,
          sessionStore: bSessionStore,
        );

        final initiation = await aSessionService.createSession(
          remoteDeviceId: bDevice.deviceId,
          remoteIdentityPublicKeyPem: bDevice.publicKeyPem,
          localDeviceId: aDevice.deviceId,
        );
        final result = await bSessionService.acceptSession(
          message: initiation,
          localDeviceId: bDevice.deviceId,
          expectedRemoteIdentityPublicKeyPem: aDevice.publicKeyPem,
        );
        await aSessionService.establishAcceptedSession(
          message: result.response,
          localDeviceId: aDevice.deviceId,
        );

        final reloaded = await SessionService(
          identityService: aIdentityService,
          sessionStore: aSessionStore,
        ).getSession(initiation.sessionId);

        expect(reloaded, isNotNull);
        expect(reloaded!.sessionId, equals(initiation.sessionId));
      },
    );

    test('session secrets never appear in public identity objects', () async {
      final identities = await _createPair();
      final aIdentityService = identities[0] as IdentityService;
      final aDevice = identities[2] as DeviceIdentity;
      final aPublic = await aIdentityService.getPublicIdentity();

      final encoded = jsonEncode(aPublic.toJson());
      expect(encoded, isNot(contains('sessionKey')));
      expect(encoded, isNot(contains('sessionSecret')));
      expect(aDevice.publicKeyPem, isNot(contains('sessionKey')));
    });

    test('session secrets never appear in QR data', () async {
      final identities = await _createPair();
      final aIdentityService = identities[0] as IdentityService;
      final aDevice = identities[2] as DeviceIdentity;
      final payload = aIdentityService.createQrPayload(aDevice).toQrString();

      expect(payload, isNot(contains('sessionKey')));
      expect(payload, isNot(contains('sessionSecret')));
      expect(payload, isNot(contains('privateKey')));
    });

    test('malformed protocol input does not crash the application', () async {
      final items = await _createPair();
      final bSession = items[5] as SessionService;
      final bDevice = items[3] as DeviceIdentity;

      final malformed = SessionProtocolMessage(
        protocolVersion: 99,
        messageType: 'session-init',
        messageId: '',
        sessionId: '',
        senderDeviceId: '',
        recipientDeviceId: bDevice.deviceId,
        senderIdentityPublicKeyPem: '',
        ephemeralPublicKeyBase64: '',
        sequence: -1,
        nonce: '',
        payload: '',
        signature: '',
        createdAt: DateTime.now().toUtc(),
      );

      expect(
        () => bSession.acceptSession(
          message: malformed,
          localDeviceId: bDevice.deviceId,
          expectedRemoteIdentityPublicKeyPem: '',
        ),
        throwsA(isA<SessionValidationException>()),
      );
    });

    test(
      'concurrent session establishment behaves deterministically',
      () async {
        final items = await _createPair();
        final aSession = items[4] as SessionService;
        final bSession = items[5] as SessionService;
        final aDevice = items[2] as DeviceIdentity;
        final bDevice = items[3] as DeviceIdentity;

        final values = await Future.wait([
          aSession.createSession(
            remoteDeviceId: bDevice.deviceId,
            remoteIdentityPublicKeyPem: bDevice.publicKeyPem,
            localDeviceId: aDevice.deviceId,
          ),
          aSession.createSession(
            remoteDeviceId: bDevice.deviceId,
            remoteIdentityPublicKeyPem: bDevice.publicKeyPem,
            localDeviceId: aDevice.deviceId,
          ),
        ]);

        final ids = values.map((message) => message.sessionId).toSet();
        expect(ids.length, equals(2));
        expect(values[0].recipientDeviceId, equals(bDevice.deviceId));
        expect(values[1].recipientDeviceId, equals(bDevice.deviceId));

        final acceptanceOne = await bSession.acceptSession(
          message: values[0],
          localDeviceId: bDevice.deviceId,
          expectedRemoteIdentityPublicKeyPem: aDevice.publicKeyPem,
        );
        await aSession.establishAcceptedSession(
          message: acceptanceOne.response,
          localDeviceId: aDevice.deviceId,
        );

        final acceptanceTwo = await bSession.acceptSession(
          message: values[1],
          localDeviceId: bDevice.deviceId,
          expectedRemoteIdentityPublicKeyPem: aDevice.publicKeyPem,
        );
        await aSession.establishAcceptedSession(
          message: acceptanceTwo.response,
          localDeviceId: aDevice.deviceId,
        );

        expect(acceptanceOne.record.derivedKeyFingerprint, isNotEmpty);
        expect(acceptanceTwo.record.derivedKeyFingerprint, isNotEmpty);
      },
    );
  });
}
