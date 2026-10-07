import 'dart:convert';
import 'dart:io';

import 'package:echat_relay/echat_relay.dart';
import 'package:echat_transport/echat_transport.dart';
import 'package:test/test.dart';
import 'package:uuid/uuid.dart';

const _sender = 'sender_route_123456';
const _recipient = 'recipient_route_1234';

class _FailingRelayQueueStore implements RelayQueueStore {
  @override
  Future<void> delete(String packetId) async {}

  @override
  Future<List<RelayQueueRecord>> loadAll() async => const [];

  @override
  Future<void> save(RelayQueueRecord record) async {
    throw FileSystemException('queue persistence failed');
  }
}

PacketSubmission _packet({
  String? packetId,
  DateTime? expiresAt,
  List<int> encryptedPacket = const [0, 1, 2, 3, 250, 251, 252],
}) => PacketSubmission(
  packetId: packetId ?? const Uuid().v4(),
  recipientRouteId: _recipient,
  expiresAt: expiresAt ?? DateTime.now().toUtc().add(const Duration(hours: 1)),
  encryptedPacket: encryptedPacket,
);

void main() {
  test('opaque queued packet survives relay restart unchanged', () async {
    final directory = await Directory.systemTemp.createTemp(
      'echat-relay-queue-restart-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final store = FileRelayQueueStore(directory: directory);
    final packet = _packet();
    final first = RelayService(queueStore: store);

    await first.submit(authenticatedSenderRouteId: _sender, packet: packet);
    final restarted = RelayService(queueStore: store);
    await restarted.initialize();

    expect(restarted.pendingPacketCount, 1);
    final delivered = await restarted.receive(
      authenticatedRecipientRouteId: _recipient,
    );
    expect(delivered, hasLength(1));
    expect(delivered.single.packetId, packet.packetId);
    expect(delivered.single.encryptedPacket, packet.encryptedPacket);
    expect(delivered.single.senderRouteId, _sender);
    expect(delivered.single.recipientRouteId, _recipient);
  });

  test('expired queued packet is not restored for delivery', () async {
    final directory = await Directory.systemTemp.createTemp(
      'echat-relay-queue-expiry-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final store = FileRelayQueueStore(directory: directory);
    var now = DateTime.utc(2026, 10, 7, 12);
    final packet = _packet(expiresAt: now.add(const Duration(minutes: 1)));
    final first = RelayService(queueStore: store, clock: () => now);
    await first.submit(authenticatedSenderRouteId: _sender, packet: packet);

    now = now.add(const Duration(minutes: 2));
    final restarted = RelayService(queueStore: store, clock: () => now);
    await restarted.initialize();

    expect(restarted.pendingPacketCount, 0);
    expect(
      await restarted.receive(authenticatedRecipientRouteId: _recipient),
      isEmpty,
    );
    expect(
      (await restarted.submit(
        authenticatedSenderRouteId: _sender,
        packet: packet,
      )).state,
      'expired',
    );
  });

  test(
    'ACK persists an idempotency tombstone without retaining ciphertext',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'echat-relay-queue-ack-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final store = FileRelayQueueStore(directory: directory);
      final packet = _packet();
      final first = RelayService(queueStore: store);
      await first.submit(authenticatedSenderRouteId: _sender, packet: packet);
      final acknowledged = await first.acknowledge(
        authenticatedRecipientRouteId: _recipient,
        packetId: packet.packetId,
      );
      expect(acknowledged.state, 'acknowledged');

      final recordFile = (await directory.list().toList())
          .whereType<File>()
          .single;
      final savedText = await recordFile.readAsString();
      expect(savedText, contains('"encryptedPacket":""'));

      final restarted = RelayService(queueStore: store);
      await restarted.initialize();
      expect(restarted.pendingPacketCount, 0);
      expect(
        (await restarted.submit(
          authenticatedSenderRouteId: _sender,
          packet: packet,
        )).state,
        'acknowledged',
      );
      expect(
        (await restarted.acknowledge(
          authenticatedRecipientRouteId: _recipient,
          packetId: packet.packetId,
        )).state,
        'already_acknowledged',
      );
    },
  );

  test('duplicate submission remains idempotent after restart', () async {
    final directory = await Directory.systemTemp.createTemp(
      'echat-relay-queue-duplicate-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final store = FileRelayQueueStore(directory: directory);
    final packet = _packet();
    final first = RelayService(queueStore: store);
    await first.submit(authenticatedSenderRouteId: _sender, packet: packet);

    final restarted = RelayService(queueStore: store);
    final duplicate = await restarted.submit(
      authenticatedSenderRouteId: _sender,
      packet: packet,
    );
    expect(duplicate.state, 'duplicate');
    expect(restarted.pendingPacketCount, 1);
    await expectLater(
      restarted.submit(
        authenticatedSenderRouteId: _sender,
        packet: _packet(
          packetId: packet.packetId,
          encryptedPacket: const [9, 8, 7],
        ),
      ),
      throwsA(isA<RelayServiceException>()),
    );
  });

  test(
    'queue persistence contains only opaque packet and delivery metadata',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'echat-relay-queue-opacity-',
      );
      addTearDown(() => directory.delete(recursive: true));
      const opaquePacket = 'opaque-encrypted-packet-bytes';
      const forbiddenMaterial = [
        'plaintext-message-body',
        'private-key-material',
        'session-key-material',
      ];
      final packet = _packet(encryptedPacket: utf8.encode(opaquePacket));
      final service = RelayService(
        queueStore: FileRelayQueueStore(directory: directory),
      );
      await service.submit(authenticatedSenderRouteId: _sender, packet: packet);
      final file = (await directory.list().toList()).whereType<File>().single;
      final savedText = await file.readAsString();

      expect(savedText, contains(base64Encode(utf8.encode(opaquePacket))));
      for (final secret in forbiddenMaterial) {
        expect(savedText, isNot(contains(secret)));
      }
      final decoded = jsonDecode(savedText) as Map<String, dynamic>;
      expect(decoded.keys.toSet(), {
        'packetId',
        'senderRouteId',
        'recipientRouteId',
        'encryptedPacket',
        'encryptedPacketDigest',
        'queuedAt',
        'expiresAt',
        'deliveryCount',
        'deliveredAt',
        'acknowledged',
        'expired',
      });
    },
  );

  test('malformed persisted records fail startup closed', () async {
    final directory = await Directory.systemTemp.createTemp(
      'echat-relay-queue-malformed-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final store = FileRelayQueueStore(directory: directory);
    final packetId = const Uuid().v4();
    await store.save(
      RelayQueueRecord(
        packetId: packetId,
        senderRouteId: _sender,
        recipientRouteId: _recipient,
        encryptedPacket: const [1, 2, 3],
        encryptedPacketDigest: 'not-a-valid-digest',
        queuedAt: DateTime.now().toUtc(),
        expiresAt: DateTime.now().toUtc().add(const Duration(hours: 1)),
        deliveryCount: 0,
        deliveredAt: null,
        acknowledged: false,
        expired: false,
      ),
    );
    final service = RelayService(queueStore: store);

    await expectLater(service.initialize(), throwsFormatException);
    await expectLater(
      service.receive(authenticatedRecipientRouteId: _recipient),
      throwsFormatException,
    );
  });

  test(
    'failed durable write does not accept packet into the live queue',
    () async {
      final service = RelayService(queueStore: _FailingRelayQueueStore());

      await expectLater(
        service.submit(authenticatedSenderRouteId: _sender, packet: _packet()),
        throwsA(isA<FileSystemException>()),
      );
      expect(service.pendingPacketCount, 0);
      expect(
        await service.receive(authenticatedRecipientRouteId: _recipient),
        isEmpty,
      );
    },
  );
}
