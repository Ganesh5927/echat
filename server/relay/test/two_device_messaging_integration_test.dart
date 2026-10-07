import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:echat_identity/echat_identity.dart';
import 'package:echat_messaging/echat_messaging.dart';
import 'package:echat_protocol/echat_protocol.dart';
import 'package:echat_relay/echat_relay.dart';
import 'package:echat_storage/echat_storage.dart';
import 'package:echat_transport/echat_transport.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';
import 'package:uuid/uuid.dart';

const _deviceAToken = 'two-device-test-device-a-token';
const _deviceBToken = 'two-device-test-device-b-token';

class _Device {
  _Device({
    required this.identityService,
    required this.identity,
    required this.trust,
    required this.sessionStore,
    required this.sessionService,
    required this.messageStore,
    required this.protocol,
    required this.messaging,
    required this.transport,
  });

  final IdentityService identityService;
  final DeviceIdentity identity;
  final ContactTrustService trust;
  final MemorySecureSessionStore sessionStore;
  final SessionService sessionService;
  final EncryptedMessageStore messageStore;
  final MessageService protocol;
  final MessagingService messaging;
  final HttpsRelayTransport transport;
}

class _ObservedSubmission {
  const _ObservedSubmission(this.senderDeviceId, this.body);

  final String senderDeviceId;
  final String body;
}

class _RelayHarness {
  _RelayHarness({
    required this.api,
    required this.service,
    required this.submissions,
  });

  final RelayApi api;
  final RelayService service;
  final List<_ObservedSubmission> submissions;
  bool failNextDeviceASubmission = false;
  bool failNextAcknowledgement = false;
  bool tamperNextDelivery = false;
  int successfulAcknowledgements = 0;

  static Future<http.Response> _sendToShelf(
    RelayApi api,
    http.Request request,
  ) async {
    final response = await api.handler(
      Request(
        request.method,
        request.url,
        headers: request.headers,
        body: request.bodyBytes,
      ),
    );
    return http.Response(
      await response.readAsString(),
      response.statusCode,
      headers: response.headers,
    );
  }

  http.Client clientFor({
    required String token,
    required String deviceId,
  }) => MockClient((request) async {
    if (request.method == 'POST' && request.url.path == '/v1/packets') {
      submissions.add(_ObservedSubmission(deviceId, request.body));
      if (token == _deviceAToken && failNextDeviceASubmission) {
        failNextDeviceASubmission = false;
        return http.Response('{}', 503);
      }
    }

    if (request.method == 'POST' &&
        request.url.path.endsWith('/acknowledgement') &&
        failNextAcknowledgement) {
      failNextAcknowledgement = false;
      return http.Response('{}', 503);
    }

    final response = await _sendToShelf(api, request);
    if (request.method == 'GET' &&
        request.url.path == '/v1/packets' &&
        tamperNextDelivery) {
      tamperNextDelivery = false;
      final responseJson = jsonDecode(response.body) as Map<String, dynamic>;
      final packets = responseJson['packets'] as List<dynamic>;
      expect(packets, isNotEmpty);
      final delivery = Map<String, dynamic>.from(
        packets.single as Map<String, dynamic>,
      );
      final encryptedPacket = base64Decode(
        delivery['encryptedPacket'] as String,
      );
      final decoded = TransportPacket.fromJson(utf8.decode(encryptedPacket));
      final ciphertext = base64Decode(decoded.envelope.ciphertext)..[0] ^= 1;
      final corrupted = TransportPacket(
        envelope: decoded.envelope.copyWith(
          ciphertext: base64Encode(ciphertext),
        ),
        transportMetadata: decoded.transportMetadata,
      );
      delivery['encryptedPacket'] = base64Encode(
        utf8.encode(corrupted.toCanonicalJson()),
      );
      return http.Response(
        jsonEncode({
          'packets': [delivery],
        }),
        response.statusCode,
        headers: response.headers,
      );
    }

    if (request.method == 'POST' &&
        request.url.path.endsWith('/acknowledgement') &&
        response.statusCode == 200) {
      successfulAcknowledgements++;
    }
    return response;
  });
}

Future<void> _enrollVerifiedPeer({
  required IdentityService localIdentityService,
  required DeviceIdentity peerIdentity,
  required ContactTrustService localTrust,
}) async {
  final payload = localIdentityService.createQrPayload(peerIdentity);
  final observed = await localTrust.observeQr(payload.toQrString());
  expect(observed.state, ContactTrustState.unverified);
  expect(observed.fingerprint, peerIdentity.fingerprint);

  // The test's independent fingerprint comparison models the existing
  // out-of-band confirmation required before contact verification.
  final independentlyComparedFingerprint = peerIdentity.fingerprint;
  expect(independentlyComparedFingerprint, observed.fingerprint);
  final verified = await localTrust.verifyContact(payload);
  expect(verified.state, ContactTrustState.verified);
}

Future<_Device> _createDevice({
  required String token,
  required String keyByte,
  required _RelayHarness relay,
  required IdentityService identityService,
  required DeviceIdentity identity,
  required ContactTrustService trust,
  required MemorySecureSessionStore sessionStore,
}) async {
  final sessionService = SessionService(
    identityService: identityService,
    sessionStore: sessionStore,
  );
  final transport = HttpsRelayTransport.forTesting(
    endpoint: Uri.https('relay.test'),
    credentialProvider: () async => token,
    clientFactory: () =>
        relay.clientFor(token: token, deviceId: identity.deviceId),
  );
  final messageStore = EncryptedMessageStore(
    backend: MemoryEncryptedRecordBackend(),
    keyProvider: () async =>
        SecretKey(List<int>.filled(32, keyByte.codeUnitAt(0))),
  );
  final protocol = MessageService(
    sessionService: sessionService,
    localDeviceId: identity.deviceId,
  );
  final messaging = MessagingService(
    protocol: protocol,
    transport: transport,
    store: messageStore,
    contactTrust: trust,
    localDeviceId: identity.deviceId,
  );
  return _Device(
    identityService: identityService,
    identity: identity,
    trust: trust,
    sessionStore: sessionStore,
    sessionService: sessionService,
    messageStore: messageStore,
    protocol: protocol,
    messaging: messaging,
    transport: transport,
  );
}

void main() {
  test(
    'two isolated devices exchange authenticated encrypted messages through relay',
    () async {
      final identityA = IdentityService(store: MemorySecureIdentityStore());
      final identityB = IdentityService(store: MemorySecureIdentityStore());
      final deviceAIdentity = await identityA.createIdentity();
      final deviceBIdentity = await identityB.createIdentity();
      expect(deviceAIdentity.deviceId, isNot(deviceBIdentity.deviceId));
      expect(deviceAIdentity.publicKeyPem, isNot(deviceBIdentity.publicKeyPem));

      final trustA = ContactTrustService(store: MemoryContactTrustStore());
      final trustB = ContactTrustService(store: MemoryContactTrustStore());
      final sessionStoreA = MemorySecureSessionStore();
      final sessionStoreB = MemorySecureSessionStore();
      expect(identical(sessionStoreA, sessionStoreB), isFalse);
      await expectLater(
        trustA.requireVerified(deviceBIdentity.deviceId),
        throwsA(isA<ContactTrustException>()),
      );
      await expectLater(
        trustB.requireVerified(deviceAIdentity.deviceId),
        throwsA(isA<ContactTrustException>()),
      );
      await _enrollVerifiedPeer(
        localIdentityService: identityA,
        peerIdentity: deviceBIdentity,
        localTrust: trustA,
      );
      await _enrollVerifiedPeer(
        localIdentityService: identityB,
        peerIdentity: deviceAIdentity,
        localTrust: trustB,
      );
      await trustA.requireVerified(deviceBIdentity.deviceId);
      await trustB.requireVerified(deviceAIdentity.deviceId);

      final sessionA = SessionService(
        identityService: identityA,
        sessionStore: sessionStoreA,
      );
      final sessionB = SessionService(
        identityService: identityB,
        sessionStore: sessionStoreB,
      );
      final initiation = await sessionA.createSession(
        remoteDeviceId: deviceBIdentity.deviceId,
        remoteIdentityPublicKeyPem: deviceBIdentity.publicKeyPem,
        localDeviceId: deviceAIdentity.deviceId,
      );
      await expectLater(
        sessionB.acceptSession(
          message: initiation,
          localDeviceId: deviceBIdentity.deviceId,
          expectedRemoteIdentityPublicKeyPem: deviceBIdentity.publicKeyPem,
        ),
        throwsA(isA<SessionValidationException>()),
      );
      expect(await sessionB.getSession(initiation.sessionId), isNull);
      final accepted = await sessionB.acceptSession(
        message: initiation,
        localDeviceId: deviceBIdentity.deviceId,
        expectedRemoteIdentityPublicKeyPem: deviceAIdentity.publicKeyPem,
      );
      final establishedA = await sessionA.establishAcceptedSession(
        message: accepted.response,
        localDeviceId: deviceAIdentity.deviceId,
      );
      final establishedB = await sessionB.getSession(initiation.sessionId);
      expect(establishedB, isNotNull);
      expect(establishedA.isEstablished, isTrue);
      expect(establishedB!.isEstablished, isTrue);
      expect(
        establishedA.derivedKeyFingerprint,
        establishedB.derivedKeyFingerprint,
      );
      expect(establishedA.localDeviceId, deviceAIdentity.deviceId);
      expect(establishedA.remoteDeviceId, deviceBIdentity.deviceId);
      expect(establishedB.localDeviceId, deviceBIdentity.deviceId);
      expect(establishedB.remoteDeviceId, deviceAIdentity.deviceId);

      final relayService = RelayService();
      final submissions = <_ObservedSubmission>[];
      late final _RelayHarness relay;
      final api = RelayApi(
        service: relayService,
        authenticator: CallbackRelayAuthenticator((header) async {
          return switch (header) {
            'Bearer $_deviceAToken' => deviceAIdentity.deviceId,
            'Bearer $_deviceBToken' => deviceBIdentity.deviceId,
            _ => null,
          };
        }),
        config: const RelayConfig(),
      );
      relay = _RelayHarness(
        api: api,
        service: relayService,
        submissions: submissions,
      );
      final deviceA = await _createDevice(
        token: _deviceAToken,
        keyByte: 'A',
        relay: relay,
        identityService: identityA,
        identity: deviceAIdentity,
        trust: trustA,
        sessionStore: sessionStoreA,
      );
      final deviceB = await _createDevice(
        token: _deviceBToken,
        keyByte: 'B',
        relay: relay,
        identityService: identityB,
        identity: deviceBIdentity,
        trust: trustB,
        sessionStore: sessionStoreB,
      );
      expect(identical(deviceA.messageStore, deviceB.messageStore), isFalse);
      expect(identical(deviceA.transport, deviceB.transport), isFalse);
      expect(identical(deviceA.trust, deviceB.trust), isFalse);

      const aToBText = 'message from device A to device B';
      final aToBQueued = await deviceA.messaging.sendTextMessage(
        sessionId: initiation.sessionId,
        recipientDeviceId: deviceBIdentity.deviceId,
        plaintext: aToBText,
      );
      expect(aToBQueued.state, MessageState.queued);
      expect(aToBQueued.direction, MessageDirection.outgoing);
      final aStoredBeforeRelay = await deviceA.messageStore.getMessage(
        aToBQueued.messageId,
      );
      expect(aStoredBeforeRelay?.plaintext, aToBText);
      final aPacketBeforeRelay = TransportPacket.fromJson(
        aStoredBeforeRelay!.serializedPacket,
      );
      expect(aPacketBeforeRelay.envelope.sequenceNumber, 1);

      final wrongRecipientPacket = TransportPacket(
        envelope: aPacketBeforeRelay.envelope.copyWith(
          recipientDeviceId: deviceAIdentity.deviceId,
        ),
      );
      await expectLater(
        deviceB.protocol.decryptIncomingMessage(
          wrongRecipientPacket.toCanonicalJson(),
        ),
        throwsA(isA<MessageProtocolException>()),
      );
      final wrongSessionPacket = TransportPacket(
        envelope: aPacketBeforeRelay.envelope.copyWith(
          sessionId: const Uuid().v4(),
        ),
      );
      await expectLater(
        deviceB.protocol.decryptIncomingMessage(
          wrongSessionPacket.toCanonicalJson(),
        ),
        throwsA(isA<MessageProtocolException>()),
      );
      final tamperedCiphertext = base64Decode(
        aPacketBeforeRelay.envelope.ciphertext,
      )..[0] ^= 1;
      final tamperedPacket = TransportPacket(
        envelope: aPacketBeforeRelay.envelope.copyWith(
          ciphertext: base64Encode(tamperedCiphertext),
        ),
      );
      await expectLater(
        deviceB.protocol.decryptIncomingMessage(
          tamperedPacket.toCanonicalJson(),
        ),
        throwsA(isA<MessageProtocolException>()),
      );
      expect(
        (await deviceB.sessionService.getSession(
          initiation.sessionId,
        ))!.receiveSequence,
        0,
      );
      expect(
        await deviceB.messageStore.getMessage(aToBQueued.messageId),
        isNull,
      );

      relay.failNextDeviceASubmission = true;
      final unavailableAttempt = await deviceA.messaging.synchronize();
      expect(unavailableAttempt.submitted, 0);
      expect(
        (await deviceA.messageStore.getMessage(aToBQueued.messageId))?.state,
        MessageState.queued,
      );
      expect(relayService.pendingPacketCount, 0);

      final aToBSubmitted = await deviceA.messaging.synchronize();
      expect(aToBSubmitted.submitted, 1);
      expect(
        (await deviceA.messageStore.getMessage(aToBQueued.messageId))?.state,
        MessageState.submitted,
      );
      expect(relayService.pendingPacketCount, 1);
      final aSubmissions = submissions
          .where(
            (submission) =>
                submission.senderDeviceId == deviceAIdentity.deviceId,
          )
          .toList();
      expect(aSubmissions, hasLength(2));
      final firstAttempt = PacketSubmission.fromJson(
        jsonDecode(aSubmissions.first.body) as Map<String, dynamic>,
      );
      final retryAttempt = PacketSubmission.fromJson(
        jsonDecode(aSubmissions.last.body) as Map<String, dynamic>,
      );
      expect(firstAttempt.packetId, aToBQueued.messageId);
      expect(retryAttempt.packetId, aToBQueued.messageId);
      expect(firstAttempt.encryptedPacket, retryAttempt.encryptedPacket);
      expect(aSubmissions.first.body, aSubmissions.last.body);
      expect(aSubmissions.first.body, isNot(contains(aToBText)));
      expect(
        utf8.decode(firstAttempt.encryptedPacket),
        isNot(contains(aToBText)),
      );

      relay.tamperNextDelivery = true;
      await expectLater(
        deviceB.messaging.synchronize(),
        throwsA(isA<MessageProtocolException>()),
      );
      expect(
        await deviceB.messageStore.getMessage(aToBQueued.messageId),
        isNull,
      );
      expect(relayService.pendingPacketCount, 1);
      expect(
        (await deviceB.sessionService.getSession(
          initiation.sessionId,
        ))!.receiveSequence,
        0,
      );

      relay.failNextAcknowledgement = true;
      await expectLater(
        deviceB.messaging.synchronize(),
        throwsA(isA<TransportException>()),
      );
      final acceptedAtB = await deviceB.messageStore.getMessage(
        aToBQueued.messageId,
      );
      expect(acceptedAtB?.plaintext, aToBText);
      expect(acceptedAtB?.state, MessageState.received);
      expect(acceptedAtB?.direction, MessageDirection.incoming);
      expect(relayService.pendingPacketCount, 1);

      final duplicateDelivery = await deviceB.messaging.synchronize();
      expect(duplicateDelivery.received, 0);
      expect(duplicateDelivery.duplicates, 1);
      expect(relayService.pendingPacketCount, 0);
      expect(
        relay.successfulAcknowledgements,
        1,
        reason:
            'The repeated delivery is acknowledged after local persistence.',
      );
      expect(await deviceB.messageStore.listMessages(), hasLength(1));
      expect(
        (await deviceA.messageStore.getMessage(aToBQueued.messageId))!.state,
        MessageState.submitted,
      );

      const aToBSecondText = 'second ordered message from device A';
      final aToBSecond = await deviceA.messaging.sendTextMessage(
        sessionId: initiation.sessionId,
        recipientDeviceId: deviceBIdentity.deviceId,
        plaintext: aToBSecondText,
      );
      expect(aToBSecond.state, MessageState.submitted);
      final aToBSecondPacket = TransportPacket.fromJson(
        aToBSecond.serializedPacket,
      );
      expect(aToBSecondPacket.envelope.sequenceNumber, 2);
      final secondDelivery = await deviceB.messaging.synchronize();
      expect(secondDelivery.received, 1);
      expect(relayService.pendingPacketCount, 0);
      final bIncoming = (await deviceB.messageStore.listMessages())
          .where((message) => message.direction == MessageDirection.incoming)
          .toList();
      expect(
        bIncoming
            .map(
              (message) => TransportPacket.fromJson(
                message.serializedPacket,
              ).envelope.sequenceNumber,
            )
            .toList(),
        [1, 2],
      );
      expect(bIncoming.last.plaintext, aToBSecondText);

      const bToAText = 'reply from device B to device A';
      final bToAQueued = await deviceB.messaging.sendTextMessage(
        sessionId: initiation.sessionId,
        recipientDeviceId: deviceAIdentity.deviceId,
        plaintext: bToAText,
      );
      expect(bToAQueued.state, MessageState.submitted);
      expect(bToAQueued.direction, MessageDirection.outgoing);
      final bToAPacket = TransportPacket.fromJson(bToAQueued.serializedPacket);
      expect(bToAPacket.envelope.sequenceNumber, 1);
      expect(bToAPacket.envelope.senderDeviceId, deviceBIdentity.deviceId);
      expect(bToAPacket.envelope.recipientDeviceId, deviceAIdentity.deviceId);

      final bToAReceived = await deviceA.messaging.synchronize();
      expect(bToAReceived.received, 1);
      expect(relayService.pendingPacketCount, 0);
      final receivedAtA = await deviceA.messageStore.getMessage(
        bToAQueued.messageId,
      );
      expect(receivedAtA?.plaintext, bToAText);
      expect(receivedAtA?.state, MessageState.received);
      expect(receivedAtA?.direction, MessageDirection.incoming);
      expect(
        (await deviceB.messageStore.getMessage(bToAQueued.messageId))?.state,
        MessageState.submitted,
      );
      expect(await deviceA.messageStore.listMessages(), hasLength(3));
      for (final submission in submissions) {
        expect(submission.body, isNot(contains(aToBText)));
        expect(submission.body, isNot(contains(aToBSecondText)));
        expect(submission.body, isNot(contains(bToAText)));
      }

      final aRecordAfterMessaging = await deviceA.sessionService.getSession(
        initiation.sessionId,
      );
      final bRecordAfterMessaging = await deviceB.sessionService.getSession(
        initiation.sessionId,
      );
      expect(aRecordAfterMessaging?.sendSequence, 2);
      expect(aRecordAfterMessaging?.receiveSequence, 1);
      expect(bRecordAfterMessaging?.sendSequence, 1);
      expect(bRecordAfterMessaging?.receiveSequence, 2);
      expect(
        aRecordAfterMessaging?.derivedKeyFingerprint,
        bRecordAfterMessaging?.derivedKeyFingerprint,
      );

      await deviceA.transport.disconnect();
      await deviceB.transport.disconnect();
    },
  );
}
