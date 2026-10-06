import 'dart:convert';

import 'package:echat_transport/echat_transport.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

void main() {
  group('HttpsRelayTransport', () {
    const packetId = '7b3a7b00-9d98-4f47-9334-cbcd1f8342cd';
    const senderRoute = 'device_A_00001';
    const recipientRoute = 'device_B_00002';
    final expiresAt = DateTime.utc(2026, 10, 7);
    final encryptedBytes = <int>[0, 1, 2, 254, 255];

    PacketSubmission submission() => PacketSubmission(
      packetId: packetId,
      recipientRouteId: recipientRoute,
      expiresAt: expiresAt,
      encryptedPacket: encryptedBytes,
    );

    HttpsRelayTransport transport(
      Future<http.Response> Function(http.Request) handler, {
      Duration timeout = const Duration(seconds: 1),
    }) {
      return HttpsRelayTransport.forTesting(
        endpoint: Uri.https('relay.test'),
        credentialProvider: () async => 'local-test-token',
        requestTimeout: timeout,
        clientFactory: () => MockClient(handler),
      );
    }

    test('production endpoint rejects HTTP and URI-embedded credentials', () {
      expect(
        () => HttpsRelayTransport(
          endpoint: Uri.http('relay.test'),
          credentialProvider: () async => 'token',
        ),
        throwsArgumentError,
      );
      expect(
        () => HttpsRelayTransport(
          endpoint: Uri.parse('https://user:password@relay.test'),
          credentialProvider: () async => 'token',
        ),
        throwsArgumentError,
      );
    });

    test('connect, submit, fetch, acknowledge, disconnect and reconnect', () async {
      final requests = <http.Request>[];
      final client = transport((request) async {
        requests.add(request);
        if (request.url.path == '/health') {
          return http.Response('{"status":"ok"}', 200);
        }
        if (request.method == 'POST' && request.url.path == '/v1/packets') {
          final sent = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response(
            jsonEncode({
              'packetId': sent['packetId'],
              'state': 'queued',
              'queuedAt': DateTime.utc(2026, 10, 6).toIso8601String(),
              'expiresAt': DateTime.utc(2026, 10, 7).toIso8601String(),
            }),
            202,
          );
        }
        if (request.method == 'GET' && request.url.path == '/v1/packets') {
          return http.Response(jsonEncode({'packets': []}), 200);
        }
        if (request.url.path.endsWith('/acknowledgement')) {
          return http.Response('', 204);
        }
        return http.Response('', 404);
      });

      final states = <TransportConnectionState>[];
      final subscription = client.connectionStates.listen(states.add);
      await client.connect();
      expect(client.connectionState, TransportConnectionState.connected);

      final receipt = await client.sendPacket(submission());
      expect(receipt.state, 'queued');
      expect(await client.receivePackets(), isEmpty);
      await client.acknowledge(packetId);
      expect(
        requests.where((request) => request.url.path == '/v1/packets').length,
        2,
      );
      expect(
        requests
            .where((request) => request.url.path == '/v1/packets')
            .every(
              (request) =>
                  request.headers['authorization'] == 'Bearer local-test-token',
            ),
        isTrue,
      );
      expect(requests.first.url.scheme, 'https');

      await client.disconnect();
      expect(client.connectionState, TransportConnectionState.disconnected);
      await client.connect();
      expect(client.connectionState, TransportConnectionState.connected);
      await client.disconnect();
      await subscription.cancel();
      expect(states, contains(TransportConnectionState.connecting));
      expect(states, contains(TransportConnectionState.disconnected));
    });

    test('send before connect and missing credentials fail closed', () async {
      final offlineClient = transport((_) async => http.Response('', 200));
      await expectLater(
        offlineClient.sendPacket(submission()),
        throwsA(isA<TransportException>()),
      );

      final noCredential = HttpsRelayTransport.forTesting(
        endpoint: Uri.https('relay.test'),
        credentialProvider: () async => null,
        clientFactory: () => MockClient((request) async {
          if (request.url.path == '/health') {
            return http.Response('{"status":"ok"}', 200);
          }
          return http.Response('', 200);
        }),
      );
      await noCredential.connect();
      await expectLater(
        noCredential.sendPacket(submission()),
        throwsA(isA<TransportException>()),
      );
      await noCredential.disconnect();
    });

    test('server rejection status maps to a safe transport error', () async {
      final client = transport((request) async {
        if (request.url.path == '/health') {
          return http.Response('{"status":"ok"}', 200);
        }
        return http.Response('{"error":"secret internal detail"}', 401);
      });
      await client.connect();
      try {
        await client.sendPacket(submission());
        fail('Expected unauthorized response.');
      } on TransportException catch (error) {
        expect(error.code, 'transport_unauthorized');
        expect(error.toString(), isNot(contains('secret internal detail')));
      }
      await client.disconnect();
    });

    test('timeout and malformed relay response fail safely', () async {
      final timeoutClient = transport(
        (request) async {
          if (request.url.path == '/health') {
            return http.Response('{"status":"ok"}', 200);
          }
          await Future<void>.delayed(const Duration(milliseconds: 30));
          return http.Response('', 200);
        },
        timeout: const Duration(milliseconds: 2),
      );
      await expectLater(timeoutClient.connect(), completes);
      await expectLater(
        timeoutClient.sendPacket(submission()),
        throwsA(isA<TransportException>()),
      );

      final malformed = transport((_) async => http.Response('not-json', 200));
      await expectLater(
        malformed.connect(),
        throwsA(isA<TransportException>()),
      );
    });

    test('opaque protocol bytes survive transport serialization exactly', () {
      final packet = submission();
      final decoded = PacketSubmission.fromJson(packet.toJson());
      expect(decoded.encryptedPacket, encryptedBytes);
      expect(decoded.packetId, packetId);
      expect(decoded.recipientRouteId, recipientRoute);
      expect(packet.toJson(), isNot(contains('plaintext')));
      expect(packet.toJson(), isNot(contains('sessionKey')));
      expect(packet.toJson(), isNot(contains('senderRouteId')));
    });

    test('malformed and oversized transport packets are rejected', () {
      expect(
        () => PacketSubmission.fromJson({'packetId': packetId}),
        throwsA(isA<TransportException>()),
      );
      expect(
        () => PacketSubmission(
          packetId: packetId,
          recipientRouteId: recipientRoute,
          expiresAt: expiresAt,
          encryptedPacket: List<int>.filled(
            PacketSubmission.maxEncryptedPacketBytes + 1,
            1,
          ),
        ),
        throwsA(isA<TransportException>()),
      );
    });
  });
}