import 'dart:async';
import 'dart:convert';

import 'package:echat_identity/echat_identity.dart';
import 'package:echat_protocol/echat_protocol.dart';
import 'package:echat_relay/echat_relay.dart';
import 'package:echat_transport/echat_transport.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';
import 'package:uuid/uuid.dart';

const _senderRoute = 'device_route_sender_01';
const _recipientRoute = 'device_route_receiver_1';
const _senderToken = 'test-token-sender';
const _recipientToken = 'test-token-recipient';

class _Harness {
  _Harness({
    required this.aDevice,
    required this.bDevice,
    required this.aSession,
    required this.bSession,
    required this.bIdentity,
    required this.bStore,
    required this.aMessages,
    required this.bMessages,
    required this.sessionId,
  });

  final DeviceIdentity aDevice;
  final DeviceIdentity bDevice;
  final SessionService aSession;
  final SessionService bSession;
  final IdentityService bIdentity;
  final MemorySecureSessionStore bStore;
  final MessageService aMessages;
  final MessageService bMessages;
  final String sessionId;

  static Future<_Harness> create() async {
    final aIdentity = IdentityService(store: MemorySecureIdentityStore());
    final bIdentity = IdentityService(store: MemorySecureIdentityStore());
    final aDevice = await aIdentity.createIdentity();
    final bDevice = await bIdentity.createIdentity();
    final aStore = MemorySecureSessionStore();
    final bStore = MemorySecureSessionStore();
    final aSession = SessionService(identityService: aIdentity, sessionStore: aStore);
    final bSession = SessionService(identityService: bIdentity, sessionStore: bStore);
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
    await aSession.establishAcceptedSession(message: result.response, localDeviceId: aDevice.deviceId);
    return _Harness(
      aDevice: aDevice,
      bDevice: bDevice,
      aSession: aSession,
      bSession: bSession,
      bIdentity: bIdentity,
      bStore: bStore,
      aMessages: MessageService(sessionService: aSession, localDeviceId: aDevice.deviceId),
      bMessages: MessageService(sessionService: bSession, localDeviceId: bDevice.deviceId),
      sessionId: initiation.sessionId,
    );
  }
}

RelayAuthenticator _authenticator() => CallbackRelayAuthenticator((header) async {
  return switch (header) {
    'Bearer $_senderToken' => _senderRoute,
    'Bearer $_recipientToken' => _recipientRoute,
    _ => null,
  };
});

class _ApiFixture {
  _ApiFixture({required this.api, required this.service});

  final RelayApi api;
  final RelayService service;

  Future<Response> call(
    String method,
    String path, {
    String? token,
    List<int>? body,
    int? contentLength,
    String contentType = 'application/json',
  }) async {
    final headers = <String, Object>{'content-type': contentType};
    if (token != null) headers['authorization'] = 'Bearer $token';
    if (contentLength != null) {
      headers['content-length'] = contentLength.toString();
    }
    return await api.handler(
      Request(
        method,
        Uri.https('relay.test', path.startsWith('/') ? path : '/$path'),
        headers: headers,
        body: body ?? const <int>[],
      ),
    );
  }
}

_ApiFixture _api({RelayConfig config = const RelayConfig(), DateTime Function()? clock}) {
  final service = RelayService(config: config, clock: clock);
  return _ApiFixture(
    service: service,
    api: RelayApi(service: service, authenticator: _authenticator(), config: config),
  );
}

PacketSubmission _packet({
  String? packetId,
  String recipientRouteId = _recipientRoute,
  DateTime? expiresAt,
  List<int> encryptedPacket = const [0, 1, 2, 3, 250, 251, 252],
}) {
  return PacketSubmission(
    packetId: packetId ?? const Uuid().v4(),
    recipientRouteId: recipientRouteId,
    expiresAt: expiresAt ?? DateTime.now().toUtc().add(const Duration(hours: 1)),
    encryptedPacket: encryptedPacket,
  );
}

String _body(PacketSubmission packet) => jsonEncode(packet.toJson());

Future<http.Response> _sendToShelf(RelayApi api, http.Request request) async {
  final shelfResponse = await api.handler(
    Request(request.method, request.url, headers: request.headers, body: request.bodyBytes),
  );
  return http.Response(await shelfResponse.readAsString(), shelfResponse.statusCode, headers: shelfResponse.headers);
}

void main() {
  group('RelayService', () {
    test('accepts encrypted packet and duplicate submission is idempotent', () async {
      final api = _api();
      final packet = _packet();
      final first = await api.service.submit(authenticatedSenderRouteId: _senderRoute, packet: packet);
      final duplicate = await api.service.submit(authenticatedSenderRouteId: _senderRoute, packet: packet);

      expect(first.state, 'queued');
      expect(duplicate.state, 'duplicate');
      expect(api.service.pendingPacketCount, 1);
    });

    test('conflicting packet ID is rejected without replacing the original', () async {
      final api = _api();
      final packetId = const Uuid().v4();
      await api.service.submit(
        authenticatedSenderRouteId: _senderRoute,
        packet: _packet(packetId: packetId),
      );
      await expectLater(
        api.service.submit(
          authenticatedSenderRouteId: _senderRoute,
          packet: _packet(packetId: packetId, encryptedPacket: [8, 8, 8]),
        ),
        throwsA(isA<RelayServiceException>()),
      );
      expect(api.service.pendingPacketCount, 1);
    });

    test('offline recipient receives queued packet unchanged and at least once', () async {
      final api = _api();
      final packet = _packet();
      await api.service.submit(authenticatedSenderRouteId: _senderRoute, packet: packet);

      final first = await api.service.receive(authenticatedRecipientRouteId: _recipientRoute);
      final retry = await api.service.receive(authenticatedRecipientRouteId: _recipientRoute);

      expect(first, hasLength(1));
      expect(first.single.encryptedPacket, packet.encryptedPacket);
      expect(retry.single.encryptedPacket, packet.encryptedPacket);
      expect(api.service.pendingPacketCount, 1);
    });

    test('acknowledgement removes ciphertext and lost ack is idempotent', () async {
      final api = _api();
      final packet = _packet();
      await api.service.submit(authenticatedSenderRouteId: _senderRoute, packet: packet);
      final first = await api.service.acknowledge(
        authenticatedRecipientRouteId: _recipientRoute,
        packetId: packet.packetId,
      );
      final retry = await api.service.acknowledge(
        authenticatedRecipientRouteId: _recipientRoute,
        packetId: packet.packetId,
      );
      final duplicateSubmit = await api.service.submit(authenticatedSenderRouteId: _senderRoute, packet: packet);

      expect(first.state, 'acknowledged');
      expect(retry.state, 'already_acknowledged');
      expect(duplicateSubmit.state, 'acknowledged');
      expect(api.service.pendingPacketCount, 0);
    });

    test('acknowledged packet stays idempotent until packet expiry', () async {
      var now = DateTime.utc(2026, 10, 6, 12);
      final api = _api(
        config: const RelayConfig(acknowledgementRetention: Duration(minutes: 5)),
        clock: () => now,
      );
      final packet = _packet(expiresAt: now.add(const Duration(hours: 3)));
      await api.service.submit(authenticatedSenderRouteId: _senderRoute, packet: packet);
      await api.service.acknowledge(authenticatedRecipientRouteId: _recipientRoute, packetId: packet.packetId);
      now = now.add(const Duration(hours: 1));
      api.service.cleanup();

      expect(
        (await api.service.submit(authenticatedSenderRouteId: _senderRoute, packet: packet)).state,
        'acknowledged',
      );
      expect(api.service.pendingPacketCount, 0);
    });

    test('expired packets are removed and idempotent retries report expiry', () async {
      var now = DateTime.utc(2026, 10, 6, 12);
      final api = _api(clock: () => now);
      final packet = _packet(expiresAt: now.add(const Duration(minutes: 1)));
      await api.service.submit(authenticatedSenderRouteId: _senderRoute, packet: packet);
      now = now.add(const Duration(minutes: 2));

      expect(api.service.cleanup(), 0);
      expect(api.service.pendingPacketCount, 0);
      expect((await api.service.submit(authenticatedSenderRouteId: _senderRoute, packet: packet)).state, 'expired');
      await expectLater(api.service.receive(authenticatedRecipientRouteId: _recipientRoute), completion(isEmpty));
    });

    test('wrong recipient cannot acknowledge another route packet', () async {
      final api = _api();
      final packet = _packet();
      await api.service.submit(authenticatedSenderRouteId: _senderRoute, packet: packet);
      await expectLater(
        api.service.acknowledge(authenticatedRecipientRouteId: _senderRoute, packetId: packet.packetId),
        throwsA(isA<RelayServiceException>()),
      );
    });

    test('bounded queue rejects overflow', () async {
      final api = _api(config: const RelayConfig(maxPackets: 1));
      await api.service.submit(authenticatedSenderRouteId: _senderRoute, packet: _packet());
      await expectLater(
        api.service.submit(authenticatedSenderRouteId: _senderRoute, packet: _packet()),
        throwsA(isA<RelayServiceException>()),
      );
    });
  });

  group('RelayApi', () {
    test('health is public, relay endpoints require transport authentication', () async {
      final api = _api();
      expect((await api.call('GET', '/health')).statusCode, 200);
      expect((await api.call('GET', '/v1/packets')).statusCode, 401);
      expect((await api.call('POST', '/v1/packets', body: utf8.encode('{}'))).statusCode, 401);
    });

    test('accepts packet with sender route bound to authenticated principal', () async {
      final api = _api();
      final packet = _packet();
      final response = await api.call('POST', '/v1/packets', token: _senderToken, body: utf8.encode(_body(packet)));
      expect(response.statusCode, 202);
      final receipt = jsonDecode(await response.readAsString()) as Map<String, dynamic>;
      expect(receipt['packetId'], packet.packetId);
      expect(receipt['state'], 'queued');

      final delivered = await api.call('GET', '/v1/packets', token: _recipientToken);
      expect(delivered.statusCode, 200);
      final envelope = (jsonDecode(await delivered.readAsString()) as Map<String, dynamic>)['packets'] as List<dynamic>;
      final bytes = DeliveredPacket.fromJson(envelope.single as Map<String, dynamic>);
      expect(bytes.encryptedPacket, packet.encryptedPacket);
      expect(bytes.senderRouteId, _senderRoute);
    });

    test('malformed packets, unsupported versions and routing errors are rejected', () async {
      final api = _api();
      final malformed = await api.call('POST', '/v1/packets', token: _senderToken, body: utf8.encode('{not json'));
      expect(malformed.statusCode, 400);

      final packet = _packet();
      final body = packet.toJson()..['transportVersion'] = 99;
      final unsupported = await api.call(
        'POST',
        '/v1/packets',
        token: _senderToken,
        body: utf8.encode(jsonEncode(body)),
      );
      expect(unsupported.statusCode, 400);

      final wrongRoute = await api.call(
        'POST',
        '/v1/packets',
        token: _senderToken,
        body: utf8.encode(jsonEncode({...packet.toJson(), 'recipientRouteId': '../personal-data'})),
      );
      expect(wrongRoute.statusCode, 400);

      final invalidBase64 = await api.call(
        'POST',
        '/v1/packets',
        token: _senderToken,
        body: utf8.encode(jsonEncode({...packet.toJson(), 'encryptedPacket': 'not-base64!'})),
      );
      expect(invalidBase64.statusCode, 400);

      final unsupportedField = await api.call(
        'POST',
        '/v1/packets',
        token: _senderToken,
        body: utf8.encode(jsonEncode({...packet.toJson(), 'plaintext': 'must-not-be-accepted'})),
      );
      expect(unsupportedField.statusCode, 400);

      final invalidFieldType = await api.call(
        'POST',
        '/v1/packets',
        token: _senderToken,
        body: utf8.encode(jsonEncode({...packet.toJson(), 'transportVersion': '1'})),
      );
      expect(invalidFieldType.statusCode, 400);
    });

    test('request, packet, expiry, queue and rate limits are enforced', () async {
      final api = _api(config: const RelayConfig(maxRequestBytes: 1200, maxPacketBytes: 128, rateLimitRequests: 10));
      final oversizedPacket = PacketSubmission(
        packetId: const Uuid().v4(),
        recipientRouteId: _recipientRoute,
        expiresAt: DateTime.now().toUtc().add(const Duration(hours: 1)),
        encryptedPacket: List<int>.filled(129, 7),
      );
      expect(
        (await api.call(
          'POST',
          '/v1/packets',
          token: _senderToken,
          body: utf8.encode(_body(oversizedPacket)),
        )).statusCode,
        413,
      );
      expect(
        (await api.call('POST', '/v1/packets', token: _senderToken, body: List<int>.filled(1201, 32))).statusCode,
        413,
      );
      expect(
        (await api.call(
          'POST',
          '/v1/packets',
          token: _senderToken,
          contentType: 'text/plain',
          body: utf8.encode('not json'),
        )).statusCode,
        415,
      );

      final expired = _packet(expiresAt: DateTime.utc(2020));
      expect(
        (await api.call('POST', '/v1/packets', token: _senderToken, body: utf8.encode(_body(expired)))).statusCode,
        410,
      );
    });

    test('rate limiter activates and unauthorized routes cannot fetch packets', () async {
      final api = _api(config: const RelayConfig(rateLimitRequests: 1));
      final first = await api.call('GET', '/v1/packets', token: _recipientToken);
      final second = await api.call('GET', '/v1/packets', token: _recipientToken);
      expect(first.statusCode, 200);
      expect(second.statusCode, 429);

      final wrongAck = await _api().call(
        'POST',
        '/v1/packets/${const Uuid().v4()}/acknowledgement',
        token: _recipientToken,
      );
      expect(wrongAck.statusCode, 404);
    });

    test('concurrent request limit activates', () async {
      final enteredAuthentication = Completer<void>();
      final continueAuthentication = Completer<void>();
      final service = RelayService();
      final api = RelayApi(
        service: service,
        authenticator: CallbackRelayAuthenticator((header) async {
          if (!enteredAuthentication.isCompleted) {
            enteredAuthentication.complete();
            await continueAuthentication.future;
          }
          return _recipientRoute;
        }),
        config: const RelayConfig(maxConcurrentRequests: 1),
      );
      final firstRequest = api.handler(
        Request('GET', Uri.https('relay.test', '/v1/packets'), headers: {'authorization': 'Bearer local-test-token'}),
      );
      await enteredAuthentication.future;
      final overflowResponse = await api.handler(
        Request('GET', Uri.https('relay.test', '/v1/packets'), headers: {'authorization': 'Bearer local-test-token'}),
      );
      continueAuthentication.complete();
      final firstResponse = await firstRequest;

      expect(overflowResponse.statusCode, 503);
      expect(firstResponse.statusCode, 200);
    });

    test('no plaintext, crypto secret, or decrypt endpoint exists in relay behavior', () async {
      final api = _api();
      final packet = _packet(encryptedPacket: utf8.encode('ciphertext-only-bytes'));
      final response = await api.call('POST', '/v1/packets', token: _senderToken, body: utf8.encode(_body(packet)));
      expect(response.statusCode, 202);
      expect(await response.readAsString(), isNot(contains('ciphertext-only-bytes')));
      expect((await api.call('POST', '/decrypt-message', token: _senderToken)).statusCode, 404);
      expect((await api.call('GET', '/messages/plaintext', token: _recipientToken)).statusCode, 404);
    });
  });

  test('end-to-end local transport preserves and delivers Phase 3 ciphertext', () async {
    final harness = await _Harness.create();
    const plaintext = 'Phase 4 local integration secret';
    final messagePacket = await harness.aMessages.sendEncryptedMessage(
      sessionId: harness.sessionId,
      plaintext: plaintext,
    );
    final serializedEnvelope = utf8.encode(messagePacket.toCanonicalJson());
    final request = PacketSubmission(
      packetId: messagePacket.envelope.messageId,
      recipientRouteId: harness.bDevice.deviceId,
      expiresAt: DateTime.now().toUtc().add(const Duration(hours: 1)),
      encryptedPacket: serializedEnvelope,
    );
    final service = RelayService();
    final api = RelayApi(
      service: service,
      authenticator: CallbackRelayAuthenticator((header) async {
        return switch (header) {
          'Bearer $_senderToken' => _senderRoute,
          'Bearer $_recipientToken' => harness.bDevice.deviceId,
          _ => null,
        };
      }),
      config: const RelayConfig(),
    );
    final observedBodies = <String>[];
    final senderTransport = HttpsRelayTransport.forTesting(
      endpoint: Uri.https('relay.test'),
      credentialProvider: () async => _senderToken,
      clientFactory: () => MockClient((httpRequest) async {
        final request = httpRequest;
        observedBodies.add(request.body);
        return _sendToShelf(api, request);
      }),
    );
    final receiverTransport = HttpsRelayTransport.forTesting(
      endpoint: Uri.https('relay.test'),
      credentialProvider: () async => _recipientToken,
      clientFactory: () => MockClient((httpRequest) async {
        return _sendToShelf(api, httpRequest);
      }),
    );

    await senderTransport.connect();
    await receiverTransport.connect();
    final receipt = await senderTransport.sendPacket(request);
    expect(receipt.state, 'queued');
    expect(observedBodies.last, isNot(contains(plaintext)));
    expect(observedBodies.last, isNot(contains('sessionKey')));
    expect(observedBodies.last, isNot(contains('privateKey')));
    expect(observedBodies.last, isNot(contains('EphemeralPrivateKey')));
    expect(observedBodies.last, isNot(contains('localStorageKey')));
    expect(observedBodies.last, isNot(contains(_senderToken)));
    expect((jsonDecode(observedBodies.last) as Map<String, dynamic>).keys.toSet(), {
      'transportVersion',
      'packetId',
      'recipientRouteId',
      'expiresAt',
      'encryptedPacket',
    });
    final received = await receiverTransport.receivePackets();
    expect(received, hasLength(1));
    expect(received.single.encryptedPacket, serializedEnvelope);
    final recovered = await harness.bMessages.decryptIncomingMessage(utf8.decode(received.single.encryptedPacket));
    expect(recovered, plaintext);
    await receiverTransport.acknowledge(request.packetId);
    expect(await receiverTransport.receivePackets(), isEmpty);
    await senderTransport.disconnect();
    await receiverTransport.disconnect();
  });

  test('tampering with relayed opaque bytes fails Phase 3 AEAD', () async {
    final harness = await _Harness.create();
    final messagePacket = await harness.aMessages.sendEncryptedMessage(
      sessionId: harness.sessionId,
      plaintext: 'tamper detection',
    );
    final originalBytes = utf8.encode(messagePacket.toCanonicalJson());
    final api = _api();
    await api.service.submit(
      authenticatedSenderRouteId: _senderRoute,
      packet: PacketSubmission(
        packetId: messagePacket.envelope.messageId,
        recipientRouteId: harness.bDevice.deviceId,
        expiresAt: DateTime.now().toUtc().add(const Duration(hours: 1)),
        encryptedPacket: originalBytes,
      ),
    );
    final relayed = (await api.service.receive(authenticatedRecipientRouteId: harness.bDevice.deviceId)).single;
    expect(relayed.encryptedPacket, originalBytes);

    final json = jsonDecode(utf8.decode(relayed.encryptedPacket)) as Map<String, dynamic>;
    final envelope = json['envelope'] as Map<String, dynamic>;
    final ciphertext = base64Decode(envelope['ciphertext'] as String);
    ciphertext[0] ^= 1;
    envelope['ciphertext'] = base64Encode(ciphertext);
    final modifiedPacket = jsonEncode(json);

    await expectLater(
      harness.bMessages.decryptIncomingMessage(modifiedPacket),
      throwsA(isA<MessageProtocolException>()),
    );
  });
}
