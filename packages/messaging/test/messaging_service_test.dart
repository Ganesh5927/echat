import 'dart:async';
import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:echat_identity/echat_identity.dart';
import 'package:echat_messaging/echat_messaging.dart';
import 'package:echat_protocol/echat_protocol.dart';
import 'package:echat_storage/echat_storage.dart';
import 'package:echat_transport/echat_transport.dart';
import 'package:test/test.dart';

class _Relay {
  final Map<String, DeliveredPacket> _pending = {};
  final List<PacketSubmission> submissions = [];
  int acknowledgements = 0;
  bool failNextAcknowledgement = false;
  bool tamperNextDelivery = false;

  Future<PacketReceipt> submit(
    String senderRoute,
    PacketSubmission packet,
  ) async {
    submissions.add(packet);
    final previous = _pending[packet.packetId];
    if (previous != null) {
      if (previous.senderRouteId != senderRoute ||
          previous.recipientRouteId != packet.recipientRouteId ||
          base64Encode(previous.encryptedPacket) !=
              base64Encode(packet.encryptedPacket)) {
        throw const TransportException('packet_id_conflict');
      }
      return PacketReceipt(
        packetId: packet.packetId,
        state: 'duplicate',
        queuedAt: previous.createdAt,
        expiresAt: previous.expiresAt,
      );
    }
    final now = DateTime.now().toUtc();
    _pending[packet.packetId] = DeliveredPacket(
      packetId: packet.packetId,
      senderRouteId: senderRoute,
      recipientRouteId: packet.recipientRouteId,
      createdAt: now,
      expiresAt: packet.expiresAt,
      state: RelayPacketState.delivered,
      encryptedPacket: packet.encryptedPacket,
    );
    return PacketReceipt(
      packetId: packet.packetId,
      state: 'queued',
      queuedAt: now,
      expiresAt: packet.expiresAt,
    );
  }

  Future<List<DeliveredPacket>> receive(String recipientRoute) async {
    final packet = _pending.values
        .where((entry) => entry.recipientRouteId == recipientRoute)
        .firstOrNull;
    if (packet == null) return const [];
    if (!tamperNextDelivery) return [packet];
    tamperNextDelivery = false;
    final parsed = TransportPacket.fromJson(
      utf8.decode(packet.encryptedPacket),
    );
    final bytes = base64Decode(parsed.envelope.ciphertext)..[0] ^= 1;
    final corrupted = TransportPacket(
      envelope: parsed.envelope.copyWith(ciphertext: base64Encode(bytes)),
    );
    return [
      DeliveredPacket(
        packetId: packet.packetId,
        senderRouteId: packet.senderRouteId,
        recipientRouteId: packet.recipientRouteId,
        createdAt: packet.createdAt,
        expiresAt: packet.expiresAt,
        state: packet.state,
        encryptedPacket: utf8.encode(corrupted.toCanonicalJson()),
      ),
    ];
  }

  Future<void> acknowledge(String recipientRoute, String packetId) async {
    if (failNextAcknowledgement) {
      failNextAcknowledgement = false;
      throw const TransportException('transport_unavailable');
    }
    final packet = _pending[packetId];
    if (packet == null || packet.recipientRouteId != recipientRoute) {
      throw const TransportException('packet_not_found');
    }
    _pending.remove(packetId);
    acknowledgements++;
  }

  int get pendingCount => _pending.length;
}

class _Transport implements PacketTransport {
  _Transport(this._relay, this.routeId);

  final _Relay _relay;
  final String routeId;
  final StreamController<TransportConnectionState> _states =
      StreamController.broadcast(sync: true);
  TransportConnectionState _state = TransportConnectionState.disconnected;

  @override
  TransportConnectionState get connectionState => _state;

  @override
  Stream<TransportConnectionState> get connectionStates => _states.stream;

  @override
  Future<void> connect() async {
    _setState(TransportConnectionState.connecting);
    _setState(TransportConnectionState.connected);
  }

  @override
  Future<void> disconnect() async =>
      _setState(TransportConnectionState.disconnected);

  @override
  Future<PacketReceipt> sendPacket(PacketSubmission packet) {
    _requireConnected();
    return _relay.submit(routeId, packet);
  }

  @override
  Future<List<DeliveredPacket>> receivePackets() {
    _requireConnected();
    return _relay.receive(routeId);
  }

  @override
  Future<void> acknowledge(String packetId) {
    _requireConnected();
    return _relay.acknowledge(routeId, packetId);
  }

  void _requireConnected() {
    if (_state != TransportConnectionState.connected) {
      throw const TransportException('transport_not_connected');
    }
  }

  void _setState(TransportConnectionState state) {
    _state = state;
    _states.add(state);
  }
}

class _Harness {
  _Harness({
    required this.sender,
    required this.receiver,
    required this.senderSession,
    required this.receiverSession,
    required this.sessionId,
    required this.relay,
    required this.senderTrust,
    required this.receiverTrust,
    required this.senderTransport,
    required this.receiverTransport,
    required this.senderMessaging,
    required this.receiverMessaging,
    required this.senderStore,
    required this.receiverStore,
  });

  final DeviceIdentity sender;
  final DeviceIdentity receiver;
  final SessionService senderSession;
  final SessionService receiverSession;
  final String sessionId;
  final _Relay relay;
  final ContactTrustService senderTrust;
  final ContactTrustService receiverTrust;
  final _Transport senderTransport;
  final _Transport receiverTransport;
  final MessagingService senderMessaging;
  final MessagingService receiverMessaging;
  final EncryptedMessageStore senderStore;
  final EncryptedMessageStore receiverStore;

  static Future<_Harness> create({bool verifyContacts = true}) async {
    final senderIdentity = IdentityService(store: MemorySecureIdentityStore());
    final receiverIdentity = IdentityService(
      store: MemorySecureIdentityStore(),
    );
    final sender = await senderIdentity.createIdentity();
    final receiver = await receiverIdentity.createIdentity();
    final senderTrust = ContactTrustService(store: MemoryContactTrustStore());
    final receiverTrust = ContactTrustService(store: MemoryContactTrustStore());
    if (verifyContacts) {
      await senderTrust.verifyContact(senderIdentity.createQrPayload(receiver));
      await receiverTrust.verifyContact(
        receiverIdentity.createQrPayload(sender),
      );
    } else {
      await senderTrust.observeIdentity(
        senderIdentity.createQrPayload(receiver),
      );
      await receiverTrust.observeIdentity(
        receiverIdentity.createQrPayload(sender),
      );
    }
    final senderSessionStore = MemorySecureSessionStore();
    final receiverSessionStore = MemorySecureSessionStore();
    final senderSession = SessionService(
      identityService: senderIdentity,
      sessionStore: senderSessionStore,
    );
    final receiverSession = SessionService(
      identityService: receiverIdentity,
      sessionStore: receiverSessionStore,
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

    final relay = _Relay();
    final senderTransport = _Transport(relay, sender.deviceId);
    final receiverTransport = _Transport(relay, receiver.deviceId);
    final senderStore = EncryptedMessageStore(
      backend: MemoryEncryptedRecordBackend(),
      keyProvider: () async => SecretKey(List<int>.filled(32, 11)),
    );
    final receiverStore = EncryptedMessageStore(
      backend: MemoryEncryptedRecordBackend(),
      keyProvider: () async => SecretKey(List<int>.filled(32, 22)),
    );
    final senderMessages = MessageService(
      sessionService: senderSession,
      localDeviceId: sender.deviceId,
    );
    final receiverMessages = MessageService(
      sessionService: receiverSession,
      localDeviceId: receiver.deviceId,
    );
    return _Harness(
      sender: sender,
      receiver: receiver,
      senderSession: senderSession,
      receiverSession: receiverSession,
      sessionId: initiation.sessionId,
      relay: relay,
      senderTrust: senderTrust,
      receiverTrust: receiverTrust,
      senderTransport: senderTransport,
      receiverTransport: receiverTransport,
      senderMessaging: MessagingService(
        protocol: senderMessages,
        transport: senderTransport,
        store: senderStore,
        contactTrust: senderTrust,
        localDeviceId: sender.deviceId,
      ),
      receiverMessaging: MessagingService(
        protocol: receiverMessages,
        transport: receiverTransport,
        store: receiverStore,
        contactTrust: receiverTrust,
        localDeviceId: receiver.deviceId,
      ),
      senderStore: senderStore,
      receiverStore: receiverStore,
    );
  }
}

void main() {
  test(
    'offline message retries after reconnect with stable ID and ciphertext',
    () async {
      final harness = await _Harness.create();
      const plaintext = 'offline-private-content';
      final queued = await harness.senderMessaging.sendTextMessage(
        sessionId: harness.sessionId,
        recipientDeviceId: harness.receiver.deviceId,
        plaintext: plaintext,
      );

      expect(queued.state, MessageState.queued);
      expect(await harness.senderStore.listOutbox(), hasLength(1));
      expect(harness.relay.pendingCount, 0);

      final senderSync = await harness.senderMessaging.synchronize();
      expect(senderSync.submitted, 1);
      expect(harness.relay.submissions, hasLength(1));
      expect(harness.relay.submissions.single.packetId, queued.messageId);
      expect(
        utf8.decode(harness.relay.submissions.single.encryptedPacket),
        isNot(contains(plaintext)),
      );
      expect(await harness.senderStore.listOutbox(), isEmpty);

      final receiverSync = await harness.receiverMessaging.synchronize();
      expect(receiverSync.received, 1);
      expect(harness.relay.pendingCount, 0);
      expect(harness.relay.acknowledgements, 1);
      final received = await harness.receiverStore.getMessage(queued.messageId);
      expect(received?.plaintext, plaintext);
      expect(received?.state, MessageState.received);
    },
  );

  test(
    'lost acknowledgement retries duplicate safely without decrypting twice',
    () async {
      final harness = await _Harness.create();
      final queued = await harness.senderMessaging.sendTextMessage(
        sessionId: harness.sessionId,
        recipientDeviceId: harness.receiver.deviceId,
        plaintext: 'ack retry',
      );
      await harness.senderMessaging.synchronize();
      harness.relay.failNextAcknowledgement = true;

      await expectLater(
        harness.receiverMessaging.synchronize(),
        throwsA(isA<TransportException>()),
      );
      expect(
        await harness.receiverStore.getMessage(queued.messageId),
        isNotNull,
      );
      expect(harness.relay.pendingCount, 1);

      final retry = await harness.receiverMessaging.synchronize();
      expect(retry.duplicates, 1);
      expect(harness.relay.pendingCount, 0);
      expect(harness.relay.acknowledgements, 1);
      expect(await harness.receiverStore.listMessages(), hasLength(1));
    },
  );

  test('tampered ciphertext is not stored or acknowledged', () async {
    final harness = await _Harness.create();
    await harness.senderMessaging.sendTextMessage(
      sessionId: harness.sessionId,
      recipientDeviceId: harness.receiver.deviceId,
      plaintext: 'tamper-detection',
    );
    await harness.senderMessaging.synchronize();
    harness.relay.tamperNextDelivery = true;

    await expectLater(
      harness.receiverMessaging.synchronize(),
      throwsA(isA<MessageProtocolException>()),
    );
    expect(await harness.receiverStore.listMessages(), isEmpty);
    expect(harness.relay.pendingCount, 1);
    expect(harness.relay.acknowledgements, 0);
  });

  test(
    'unverified peer cannot consume a send sequence or reach the relay',
    () async {
      final harness = await _Harness.create(verifyContacts: false);
      final before = await harness.senderSession.getSession(harness.sessionId);

      await expectLater(
        harness.senderMessaging.sendTextMessage(
          sessionId: harness.sessionId,
          recipientDeviceId: harness.receiver.deviceId,
          plaintext: 'must not send',
        ),
        throwsA(isA<ContactTrustException>()),
      );

      final after = await harness.senderSession.getSession(harness.sessionId);
      expect(after?.sendSequence, before?.sendSequence);
      expect(harness.relay.submissions, isEmpty);
    },
  );

  test('changed identity and stale session key cannot send', () async {
    final harness = await _Harness.create();
    final replacementIdentity = IdentityService(
      store: MemorySecureIdentityStore(),
    );
    final replacement = await replacementIdentity.createIdentity();
    final replacementQr = replacementIdentity.createQrPayload(replacement);
    final changedQr = PublicIdentityQrPayload(
      version: replacementQr.version,
      deviceId: harness.receiver.deviceId,
      publicKeyPem: replacementQr.publicKeyPem,
      fingerprint: replacementQr.fingerprint,
      createdAt: replacementQr.createdAt,
    );
    await harness.senderTrust.observeIdentity(changedQr);

    await expectLater(
      harness.senderMessaging.sendTextMessage(
        sessionId: harness.sessionId,
        recipientDeviceId: harness.receiver.deviceId,
        plaintext: 'blocked after key change',
      ),
      throwsA(isA<ContactTrustException>()),
    );
    await harness.senderTrust.reverifyChangedIdentity(changedQr);
    await expectLater(
      harness.senderMessaging.sendTextMessage(
        sessionId: harness.sessionId,
        recipientDeviceId: harness.receiver.deviceId,
        plaintext: 'old session is still pinned',
      ),
      throwsA(isA<ContactTrustException>()),
    );
    final session = await harness.senderSession.getSession(harness.sessionId);
    expect(session?.sendSequence, 0);
    expect(harness.relay.submissions, isEmpty);
  });

  test('revoked sender is not decrypted, stored, or acknowledged', () async {
    final harness = await _Harness.create();
    await harness.senderMessaging.sendTextMessage(
      sessionId: harness.sessionId,
      recipientDeviceId: harness.receiver.deviceId,
      plaintext: 'revoke before delivery',
    );
    await harness.senderMessaging.synchronize();
    await harness.receiverTrust.revokeContact(harness.sender.deviceId);

    await expectLater(
      harness.receiverMessaging.synchronize(),
      throwsA(isA<ContactTrustException>()),
    );
    expect(await harness.receiverStore.listMessages(), isEmpty);
    expect(harness.relay.pendingCount, 1);
    expect(harness.relay.acknowledgements, 0);
  });
}
