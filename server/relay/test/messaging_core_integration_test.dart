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

const _senderToken = 'messaging-test-sender-token';
const _receiverToken = 'messaging-test-receiver-token';

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

class _Harness {
  _Harness({
    required this.sender,
    required this.receiver,
    required this.sessionId,
    required this.senderMessaging,
    required this.receiverMessaging,
    required this.receiverStore,
    required this.senderTransport,
    required this.receiverTransport,
    required this.service,
    required this.submissionBodies,
  });

  final DeviceIdentity sender;
  final DeviceIdentity receiver;
  final String sessionId;
  final MessagingService senderMessaging;
  final MessagingService receiverMessaging;
  final EncryptedMessageStore receiverStore;
  final HttpsRelayTransport senderTransport;
  final HttpsRelayTransport receiverTransport;
  final RelayService service;
  final List<String> submissionBodies;

  static Future<_Harness> create() async {
    final senderIdentity = IdentityService(store: MemorySecureIdentityStore());
    final receiverIdentity = IdentityService(
      store: MemorySecureIdentityStore(),
    );
    final sender = await senderIdentity.createIdentity();
    final receiver = await receiverIdentity.createIdentity();
    final senderSession = SessionService(
      identityService: senderIdentity,
      sessionStore: MemorySecureSessionStore(),
    );
    final receiverSession = SessionService(
      identityService: receiverIdentity,
      sessionStore: MemorySecureSessionStore(),
    );
    final initiation = await senderSession.createSession(
      remoteDeviceId: receiver.deviceId,
      remoteIdentityPublicKeyPem: receiver.publicKeyPem,
      localDeviceId: sender.deviceId,
    );
    final accepted = await receiverSession.acceptSession(
      message: initiation,
      localDeviceId: receiver.deviceId,
      expectedRemoteIdentityPublicKeyPem: sender.publicKeyPem,
    );
    await senderSession.establishAcceptedSession(
      message: accepted.response,
      localDeviceId: sender.deviceId,
    );

    final service = RelayService();
    final api = RelayApi(
      service: service,
      authenticator: CallbackRelayAuthenticator((header) async {
        return switch (header) {
          'Bearer $_senderToken' => sender.deviceId,
          'Bearer $_receiverToken' => receiver.deviceId,
          _ => null,
        };
      }),
      config: const RelayConfig(),
    );
    final submissionBodies = <String>[];
    HttpsRelayTransport createTransport(
      String token, {
      bool observeSend = false,
    }) {
      return HttpsRelayTransport.forTesting(
        endpoint: Uri.https('relay.test'),
        credentialProvider: () async => token,
        clientFactory: () => MockClient((request) async {
          final relayRequest = request;
          if (observeSend &&
              relayRequest.method == 'POST' &&
              relayRequest.url.path == '/v1/packets') {
            submissionBodies.add(relayRequest.body);
          }
          return _sendToShelf(api, relayRequest);
        }),
      );
    }

    final senderTransport = createTransport(_senderToken, observeSend: true);
    final receiverTransport = createTransport(_receiverToken);
    final senderMessages = MessageService(
      sessionService: senderSession,
      localDeviceId: sender.deviceId,
    );
    final receiverMessages = MessageService(
      sessionService: receiverSession,
      localDeviceId: receiver.deviceId,
    );
    final receiverStore = EncryptedMessageStore(
      backend: MemoryEncryptedRecordBackend(),
      keyProvider: () async => SecretKey(List<int>.filled(32, 32)),
    );
    return _Harness(
      sender: sender,
      receiver: receiver,
      sessionId: initiation.sessionId,
      senderMessaging: MessagingService(
        protocol: senderMessages,
        transport: senderTransport,
        store: EncryptedMessageStore(
          backend: MemoryEncryptedRecordBackend(),
          keyProvider: () async => SecretKey(List<int>.filled(32, 31)),
        ),
        localDeviceId: sender.deviceId,
      ),
      receiverMessaging: MessagingService(
        protocol: receiverMessages,
        transport: receiverTransport,
        store: receiverStore,
        localDeviceId: receiver.deviceId,
      ),
      receiverStore: receiverStore,
      senderTransport: senderTransport,
      receiverTransport: receiverTransport,
      service: service,
      submissionBodies: submissionBodies,
    );
  }
}

void main() {
  test(
    '1-to-1 message crosses HTTPS transport and relay as ciphertext only',
    () async {
      final harness = await _Harness.create();
      const plaintext = 'only-the-endpoints-know-this';
      final queued = await harness.senderMessaging.sendTextMessage(
        sessionId: harness.sessionId,
        plaintext: plaintext,
      );

      expect(queued.state, MessageState.queued);
      final sent = await harness.senderMessaging.synchronize();
      expect(sent.submitted, 1);
      expect(harness.service.pendingPacketCount, 1);
      expect(harness.submissionBodies, hasLength(1));
      expect(harness.submissionBodies.single, isNot(contains(plaintext)));
      expect(harness.submissionBodies.single, isNot(contains('sessionKey')));
      expect(harness.submissionBodies.single, isNot(contains('privateKey')));

      final received = await harness.receiverMessaging.synchronize();
      expect(received.received, 1);
      expect(harness.service.pendingPacketCount, 0);
      final message = await harness.receiverStore.getMessage(queued.messageId);
      expect(message?.plaintext, plaintext);
      expect(message?.state, MessageState.received);

      await harness.senderTransport.disconnect();
      await harness.receiverTransport.disconnect();
    },
  );
}
