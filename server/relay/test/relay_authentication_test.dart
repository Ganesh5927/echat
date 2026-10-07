import 'dart:convert';
import 'dart:io';

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

Future<http.Response> _sendToShelf(RelayApi api, http.Request request) async {
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

class _Fixture {
  _Fixture({
    required this.api,
    required this.authenticator,
    required this.registrationStore,
    required this.queueStore,
  });

  final RelayApi api;
  final RelayDeviceAuthenticator authenticator;
  final RelayDeviceStore registrationStore;
  final MemoryRelayQueueStore queueStore;

  HttpsRelayTransport transport(
    IdentityService identityService, {
    void Function(http.Request request)? observeRequest,
  }) => HttpsRelayTransport.forTesting(
    endpoint: Uri.https('relay.test'),
    identityService: identityService,
    clientFactory: () => MockClient((request) async {
      observeRequest?.call(request);
      return _sendToShelf(api, request);
    }),
  );

  Future<http.Response> unauthenticatedRequest(
    String method,
    String path, {
    Object? body,
  }) async {
    final client = MockClient((request) => _sendToShelf(api, request));
    final request = http.Request(method, Uri.https('relay.test', path))
      ..headers['content-type'] = 'application/json';
    if (body != null) request.body = jsonEncode(body);
    final response = await client.send(request);
    return http.Response.fromStream(response);
  }
}

_Fixture _fixture({RelayDeviceStore? store}) {
  final registrationStore = store ?? MemoryRelayDeviceStore();
  final queueStore = MemoryRelayQueueStore();
  final authenticator = RelayDeviceAuthenticator(
    deviceStore: registrationStore,
  );
  final service = RelayService(queueStore: queueStore);
  final api = RelayApi(
    service: service,
    authenticator: authenticator,
    config: const RelayConfig(),
  );
  return _Fixture(
    api: api,
    authenticator: authenticator,
    registrationStore: registrationStore,
    queueStore: queueStore,
  );
}

void main() {
  test(
    'registration and authentication prove the real identity on connect',
    () async {
      final fixture = _fixture();
      final identityService = IdentityService(
        store: MemorySecureIdentityStore(),
      );
      final identity = await identityService.createIdentity();
      final authRequestBodies = <String>[];
      final transport = fixture.transport(
        identityService,
        observeRequest: (request) {
          if (request.url.path == '/v1/devices/register' ||
              request.url.path == '/v1/authenticate') {
            authRequestBodies.add(request.body);
          }
        },
      );
      final states = <TransportConnectionState>[];
      final stateSubscription = transport.connectionStates.listen(states.add);
      addTearDown(stateSubscription.cancel);
      await transport.connect();
      addTearDown(transport.disconnect);

      final registrations = await fixture.registrationStore.loadAll();
      expect(registrations, hasLength(1));
      expect(registrations.single.deviceId, identity.deviceId);
      expect(registrations.single.publicKeyPem, identity.publicKeyPem);
      expect(registrations.single.fingerprint, identity.fingerprint);
      expect(transport.connectionState, TransportConnectionState.connected);
      expect(transport.isAuthenticated, isTrue);
      expect(states, contains(TransportConnectionState.authenticating));
      expect(states.last, TransportConnectionState.connected);
      expect(authRequestBodies, hasLength(2));
      expect(authRequestBodies.join('\n'), isNot(contains('PRIVATE KEY')));
      expect(authRequestBodies.join('\n'), isNot(contains('sessionKey')));
    },
  );

  test('failed device authentication has a distinct transport state', () async {
    final fixture = _fixture();
    final identityService = IdentityService(store: MemorySecureIdentityStore());
    await identityService.createIdentity();
    final transport = HttpsRelayTransport.forTesting(
      endpoint: Uri.https('relay.test'),
      identityService: identityService,
      clientFactory: () => MockClient((request) async {
        if (request.url.path == '/v1/authenticate') {
          return http.Response('{"error":"unauthorized"}', 401);
        }
        return _sendToShelf(fixture.api, request);
      }),
    );
    final states = <TransportConnectionState>[];
    final subscription = transport.connectionStates.listen(states.add);
    addTearDown(subscription.cancel);
    addTearDown(transport.disconnect);

    await expectLater(transport.connect(), throwsA(isA<TransportException>()));
    expect(states, contains(TransportConnectionState.authenticating));
    expect(states.last, TransportConnectionState.authenticationFailed);
    expect(transport.isAuthenticated, isFalse);
  });

  test('malformed registration request is rejected', () async {
    final fixture = _fixture();
    final response = await fixture.unauthenticatedRequest(
      'POST',
      '/v1/devices/register',
      body: {'deviceId': 'not-an-identity'},
    );
    expect(response.statusCode, 400);
    expect(response.body, contains('malformed_registration'));
    expect(await fixture.registrationStore.loadAll(), isEmpty);
  });

  test(
    'bad registration signature is rejected and challenge cannot be replayed',
    () async {
      final fixture = _fixture();
      final identityService = IdentityService(
        store: MemorySecureIdentityStore(),
      );
      final identity = await identityService.createIdentity();
      final registrationChallenge = await _challenge(
        fixture,
        identity.deviceId,
        'register',
      );
      final badRegistration = await fixture.unauthenticatedRequest(
        'POST',
        '/v1/devices/register',
        body: _registrationBody(
          identity,
          challenge: registrationChallenge,
          signature: base64Encode(List<int>.filled(64, 0)),
        ),
      );
      expect(badRegistration.statusCode, 401);
      expect(badRegistration.body, contains('invalid_signature'));
      expect(await fixture.registrationStore.loadAll(), isEmpty);

      final challenge = await _challenge(
        fixture,
        identity.deviceId,
        'register',
      );
      final signature = await identityService.signIdentityMessage(
        challenge.signedMessage(
          operation: 'register',
          deviceId: identity.deviceId,
        ),
      );
      final body = _registrationBody(
        identity,
        challenge: challenge,
        signature: base64Encode(signature.bytes),
      );
      final first = await fixture.unauthenticatedRequest(
        'POST',
        '/v1/devices/register',
        body: body,
      );
      final replay = await fixture.unauthenticatedRequest(
        'POST',
        '/v1/devices/register',
        body: body,
      );
      expect(first.statusCode, 201);
      expect(replay.statusCode, 401);
      expect(replay.body, contains('invalid_auth_challenge'));
    },
  );

  test('valid authentication token and one-use authentication proof', () async {
    final fixture = _fixture();
    final identityService = IdentityService(store: MemorySecureIdentityStore());
    final identity = await identityService.createIdentity();
    final transport = fixture.transport(identityService);
    await transport.connect();
    addTearDown(transport.disconnect);

    final challenge = await _challenge(
      fixture,
      identity.deviceId,
      'authenticate',
    );
    final signature = await identityService.signIdentityMessage(
      challenge.signedMessage(
        operation: 'authenticate',
        deviceId: identity.deviceId,
      ),
    );
    final requestBody = {
      'deviceId': identity.deviceId,
      'challengeId': challenge.challengeId,
      'signature': base64Encode(signature.bytes),
    };
    final first = await fixture.unauthenticatedRequest(
      'POST',
      '/v1/authenticate',
      body: requestBody,
    );
    expect(first.statusCode, 200);
    final credential = jsonDecode(first.body) as Map<String, dynamic>;
    final replay = await fixture.unauthenticatedRequest(
      'POST',
      '/v1/authenticate',
      body: requestBody,
    );
    expect(replay.statusCode, 401);
    expect(replay.body, contains('invalid_auth_challenge'));

    final authenticated = await fixture.api.handler(
      Request(
        'GET',
        Uri.https('relay.test', '/v1/packets'),
        headers: {'authorization': 'Bearer ${credential['accessToken']}'},
      ),
    );
    expect(authenticated.statusCode, 200);
  });

  test('invalid authentication signature is rejected', () async {
    final fixture = _fixture();
    final identityService = IdentityService(store: MemorySecureIdentityStore());
    final identity = await identityService.createIdentity();
    final transport = fixture.transport(identityService);
    await transport.connect();
    addTearDown(transport.disconnect);

    final challenge = await _challenge(
      fixture,
      identity.deviceId,
      'authenticate',
    );
    final response = await fixture.unauthenticatedRequest(
      'POST',
      '/v1/authenticate',
      body: {
        'deviceId': identity.deviceId,
        'challengeId': challenge.challengeId,
        'signature': base64Encode(List<int>.filled(64, 0)),
      },
    );
    expect(response.statusCode, 401);
    expect(response.body, contains('invalid_signature'));
  });

  test(
    'client reauthenticates after relay restart invalidates tokens',
    () async {
      final firstRelay = _fixture();
      final identityService = IdentityService(
        store: MemorySecureIdentityStore(),
      );
      await identityService.createIdentity();
      var activeApi = firstRelay.api;
      final transport = HttpsRelayTransport.forTesting(
        endpoint: Uri.https('relay.test'),
        identityService: identityService,
        clientFactory: () =>
            MockClient((request) => _sendToShelf(activeApi, request)),
      );
      await transport.connect();
      addTearDown(transport.disconnect);

      final restartedRelay = _fixture(store: firstRelay.registrationStore);
      activeApi = restartedRelay.api;
      expect(await transport.receivePackets(), isEmpty);
      expect(transport.connectionState, TransportConnectionState.connected);
    },
  );

  test(
    'authenticated devices are route-bound; unauthenticated submit is denied',
    () async {
      final fixture = _fixture();
      final senderIdentityService = IdentityService(
        store: MemorySecureIdentityStore(),
      );
      final recipientIdentityService = IdentityService(
        store: MemorySecureIdentityStore(),
      );
      final sender = await senderIdentityService.createIdentity();
      final recipient = await recipientIdentityService.createIdentity();
      final senderTransport = fixture.transport(senderIdentityService);
      final recipientTransport = fixture.transport(recipientIdentityService);
      await senderTransport.connect();
      await recipientTransport.connect();
      addTearDown(senderTransport.disconnect);
      addTearDown(recipientTransport.disconnect);

      final submission = PacketSubmission(
        packetId: const Uuid().v4(),
        recipientRouteId: recipient.deviceId,
        expiresAt: DateTime.now().toUtc().add(const Duration(hours: 1)),
        encryptedPacket: const [13, 37, 99, 201],
      );
      final unauthorized = await fixture.unauthenticatedRequest(
        'POST',
        '/v1/packets',
        body: submission.toJson(),
      );
      expect(unauthorized.statusCode, 401);

      final receipt = await senderTransport.sendPacket(submission);
      expect(receipt.state, 'queued');
      final received = await recipientTransport.receivePackets();
      expect(received, hasLength(1));
      expect(received.single.senderRouteId, sender.deviceId);
      expect(received.single.recipientRouteId, recipient.deviceId);
      expect(received.single.encryptedPacket, submission.encryptedPacket);
      expect(
        await senderTransport.receivePackets(),
        isEmpty,
        reason: 'A device token cannot receive another route’s packets.',
      );
      await recipientTransport.acknowledge(submission.packetId);
      expect(fixture.queueStore.loadAll(), completion(hasLength(1)));

      final unregisteredRoute = PacketSubmission(
        packetId: const Uuid().v4(),
        recipientRouteId: const Uuid().v4(),
        expiresAt: DateTime.now().toUtc().add(const Duration(hours: 1)),
        encryptedPacket: const [1, 2, 3],
      );
      await expectLater(
        senderTransport.sendPacket(unregisteredRoute),
        throwsA(
          isA<TransportException>().having(
            (error) => error.statusCode,
            'statusCode',
            404,
          ),
        ),
      );
    },
  );

  test(
    'authenticated relay carries a real encrypted message without plaintext',
    () async {
      final fixture = _fixture();
      final senderIdentityService = IdentityService(
        store: MemorySecureIdentityStore(),
      );
      final recipientIdentityService = IdentityService(
        store: MemorySecureIdentityStore(),
      );
      final sender = await senderIdentityService.createIdentity();
      final recipient = await recipientIdentityService.createIdentity();
      final senderTrust = ContactTrustService(store: MemoryContactTrustStore());
      final recipientTrust = ContactTrustService(
        store: MemoryContactTrustStore(),
      );
      await senderTrust.verifyContact(
        senderIdentityService.createQrPayload(recipient),
      );
      await recipientTrust.verifyContact(
        recipientIdentityService.createQrPayload(sender),
      );

      final senderSession = SessionService(
        identityService: senderIdentityService,
        sessionStore: MemorySecureSessionStore(),
      );
      final recipientSession = SessionService(
        identityService: recipientIdentityService,
        sessionStore: MemorySecureSessionStore(),
      );
      final initiation = await senderSession.createSession(
        remoteDeviceId: recipient.deviceId,
        remoteIdentityPublicKeyPem: recipient.publicKeyPem,
        localDeviceId: sender.deviceId,
      );
      final accepted = await recipientSession.acceptSession(
        message: initiation,
        localDeviceId: recipient.deviceId,
        expectedRemoteIdentityPublicKeyPem: sender.publicKeyPem,
      );
      await senderSession.establishAcceptedSession(
        message: accepted.response,
        localDeviceId: sender.deviceId,
      );

      final observedSubmissions = <String>[];
      HttpsRelayTransport createTransport(IdentityService identityService) =>
          HttpsRelayTransport.forTesting(
            endpoint: Uri.https('relay.test'),
            identityService: identityService,
            clientFactory: () => MockClient((request) async {
              if (request.method == 'POST' &&
                  request.url.path == '/v1/packets') {
                observedSubmissions.add(request.body);
              }
              return _sendToShelf(fixture.api, request);
            }),
          );
      final senderTransport = createTransport(senderIdentityService);
      final recipientTransport = createTransport(recipientIdentityService);
      final senderStore = EncryptedMessageStore(
        backend: MemoryEncryptedRecordBackend(),
        keyProvider: () async => SecretKey(List<int>.filled(32, 71)),
      );
      final recipientStore = EncryptedMessageStore(
        backend: MemoryEncryptedRecordBackend(),
        keyProvider: () async => SecretKey(List<int>.filled(32, 82)),
      );
      final senderMessaging = MessagingService(
        protocol: MessageService(
          sessionService: senderSession,
          localDeviceId: sender.deviceId,
        ),
        transport: senderTransport,
        store: senderStore,
        contactTrust: senderTrust,
        localDeviceId: sender.deviceId,
      );
      final recipientMessaging = MessagingService(
        protocol: MessageService(
          sessionService: recipientSession,
          localDeviceId: recipient.deviceId,
        ),
        transport: recipientTransport,
        store: recipientStore,
        contactTrust: recipientTrust,
        localDeviceId: recipient.deviceId,
      );

      await recipientTransport.connect();
      const plaintext = 'only-the-two-endpoints-can-read-this';
      final queued = await senderMessaging.sendTextMessage(
        sessionId: initiation.sessionId,
        recipientDeviceId: recipient.deviceId,
        plaintext: plaintext,
      );
      expect(queued.state, MessageState.queued);
      final sent = await senderMessaging.synchronize();
      expect(sent.submitted, 1);
      expect(observedSubmissions, hasLength(1));
      expect(observedSubmissions.single, isNot(contains(plaintext)));
      expect(observedSubmissions.single, isNot(contains('privateKey')));
      expect(observedSubmissions.single, isNot(contains('sessionKey')));
      expect(fixture.queueStore.loadAll(), completion(hasLength(1)));

      final received = await recipientMessaging.synchronize();
      expect(received.received, 1);
      final stored = await recipientStore.getMessage(queued.messageId);
      expect(stored?.plaintext, plaintext);
      expect(stored?.state, MessageState.received);

      await senderTransport.disconnect();
      await recipientTransport.disconnect();
    },
  );

  test(
    'only public identity metadata is persisted by relay registration',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'echat-relay-device-registry-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final store = FileRelayDeviceStore(directory: directory);
      final fixture = _fixture(store: store);
      final identityService = IdentityService(
        store: MemorySecureIdentityStore(),
      );
      final identity = await identityService.createIdentity();
      final transport = fixture.transport(identityService);
      await transport.connect();
      addTearDown(transport.disconnect);

      final files = await directory
          .list()
          .where((entry) => entry is File)
          .toList();
      expect(files, hasLength(1));
      final saved = await (files.single as File).readAsString();
      final registration = jsonDecode(saved) as Map<String, dynamic>;
      expect(registration['publicKeyPem'], identity.publicKeyPem);
      expect(saved, isNot(contains('PRIVATE KEY')));
      expect(saved, isNot(contains('sessionKey')));
      expect(saved, isNot(contains('plaintext')));
      expect(registration.keys.toSet(), {
        'deviceId',
        'publicKeyPem',
        'fingerprint',
        'registeredAt',
      });

      final restartedFixture = _fixture(store: store);
      final restartedTransport = restartedFixture.transport(identityService);
      await restartedTransport.connect();
      addTearDown(restartedTransport.disconnect);
      expect(await store.loadAll(), hasLength(1));
    },
  );
}

Future<RelayAuthChallenge> _challenge(
  _Fixture fixture,
  String deviceId,
  String operation,
) async {
  final response = await fixture.unauthenticatedRequest(
    'POST',
    '/v1/auth/challenge',
    body: {'deviceId': deviceId, 'operation': operation},
  );
  expect(response.statusCode, 200);
  return RelayAuthChallenge.fromJson(
    jsonDecode(response.body) as Map<String, dynamic>,
  );
}

Map<String, Object?> _registrationBody(
  DeviceIdentity identity, {
  required RelayAuthChallenge challenge,
  required String signature,
}) => {
  'deviceId': identity.deviceId,
  'publicKeyPem': identity.publicKeyPem,
  'fingerprint': identity.fingerprint,
  'createdAt': identity.createdAt.toUtc().toIso8601String(),
  'challengeId': challenge.challengeId,
  'signature': signature,
};
