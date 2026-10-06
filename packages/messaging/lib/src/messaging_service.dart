import 'dart:async';
import 'dart:convert';

import 'package:echat_protocol/echat_protocol.dart';
import 'package:echat_storage/echat_storage.dart';
import 'package:echat_transport/echat_transport.dart';

class MessagingException implements Exception {
  const MessagingException(this.code);

  final String code;

  @override
  String toString() => 'MessagingException: $code';
}

class SyncResult {
  const SyncResult({
    required this.submitted,
    required this.received,
    required this.duplicates,
    required this.moreAvailable,
  });

  final int submitted;
  final int received;
  final int duplicates;
  final bool moreAvailable;
}

class MessagingService {
  MessagingService({
    required MessageService protocol,
    required PacketTransport transport,
    required EncryptedMessageStore store,
    required String localDeviceId,
    this.messageLifetime = const Duration(hours: 24),
    this.maxPacketsPerSync = 100,
    DateTime Function()? clock,
  }) : _protocol = protocol,
       _transport = transport,
       _store = store,
       _localDeviceId = localDeviceId,
       _clock = clock ?? DateTime.now {
    if (messageLifetime <= Duration.zero || maxPacketsPerSync < 1) {
      throw ArgumentError('Messaging configuration is invalid.');
    }
  }

  final MessageService _protocol;
  final PacketTransport _transport;
  final EncryptedMessageStore _store;
  final String _localDeviceId;
  final DateTime Function() _clock;
  final Duration messageLifetime;
  final int maxPacketsPerSync;
  Future<void> _syncTail = Future<void>.value();

  Future<StoredMessage> sendTextMessage({
    required String sessionId,
    required String plaintext,
  }) async {
    final packet = await _protocol.sendEncryptedMessage(
      sessionId: sessionId,
      plaintext: plaintext,
    );
    final now = _clock().toUtc();
    final message = StoredMessage(
      messageId: packet.envelope.messageId,
      sessionId: packet.envelope.sessionId,
      peerDeviceId: packet.envelope.recipientDeviceId,
      direction: MessageDirection.outgoing,
      state: MessageState.queued,
      plaintext: plaintext,
      serializedPacket: packet.toCanonicalJson(),
      createdAt: now,
      expiresAt: now.add(messageLifetime),
    );
    await _store.saveMessage(message);
    await _submitIfConnected(message);
    return (await _store.getMessage(message.messageId))!;
  }

  Future<SyncResult> synchronize() => _serializedSync(() async {
    if (_transport.connectionState != TransportConnectionState.connected) {
      await _transport.connect();
    }

    var submitted = 0;
    var received = 0;
    var duplicates = 0;
    for (final message in await _store.listOutbox()) {
      if (await _submitIfConnected(message)) submitted++;
    }

    var processedPackets = 0;
    while (processedPackets < maxPacketsPerSync) {
      final packets = await _transport.receivePackets();
      if (packets.isEmpty) {
        return SyncResult(
          submitted: submitted,
          received: received,
          duplicates: duplicates,
          moreAvailable: false,
        );
      }
      for (final delivered in packets) {
        if (processedPackets >= maxPacketsPerSync) {
          return SyncResult(
            submitted: submitted,
            received: received,
            duplicates: duplicates,
            moreAvailable: true,
          );
        }
        final wasDuplicate = await _acceptDelivery(delivered);
        if (wasDuplicate) {
          duplicates++;
        } else {
          received++;
        }
        processedPackets++;
      }
    }
    return SyncResult(
      submitted: submitted,
      received: received,
      duplicates: duplicates,
      moreAvailable: true,
    );
  });

  Future<bool> _submitIfConnected(StoredMessage message) async {
    if (_transport.connectionState != TransportConnectionState.connected) {
      return false;
    }
    final packet = PacketSubmission(
      packetId: message.messageId,
      recipientRouteId: message.peerDeviceId,
      expiresAt: message.expiresAt,
      encryptedPacket: utf8.encode(message.serializedPacket),
    );
    try {
      final receipt = await _transport.sendPacket(packet);
      if (receipt.packetId != message.messageId ||
          !const {
            'queued',
            'duplicate',
            'delivered',
            'acknowledged',
          }.contains(receipt.state)) {
        throw const MessagingException('invalid_submission_receipt');
      }
      await _store.markSubmitted(message.messageId);
      return true;
    } on TransportException {
      return false;
    }
  }

  Future<bool> _acceptDelivery(DeliveredPacket delivered) async {
    if (delivered.recipientRouteId != _localDeviceId) {
      throw const MessagingException('delivery_route_mismatch');
    }
    final serialized = utf8.decode(delivered.encryptedPacket);
    final packet = TransportPacket.fromJson(serialized);
    final envelope = packet.envelope;
    if (delivered.packetId != envelope.messageId ||
        envelope.recipientDeviceId != _localDeviceId) {
      throw const MessagingException('delivery_message_mismatch');
    }

    final existing = await _store.getMessage(delivered.packetId);
    if (existing != null) {
      if (existing.direction != MessageDirection.incoming ||
          existing.serializedPacket != serialized) {
        throw const MessagingException('message_id_conflict');
      }
      await _transport.acknowledge(delivered.packetId);
      return true;
    }

    await _protocol.decryptIncomingMessage(
      serialized,
      onAuthenticated: (plaintext, authenticatedPacket) async {
        final authenticatedEnvelope = authenticatedPacket.envelope;
        await _store.saveMessage(
          StoredMessage(
            messageId: authenticatedEnvelope.messageId,
            sessionId: authenticatedEnvelope.sessionId,
            peerDeviceId: authenticatedEnvelope.senderDeviceId,
            direction: MessageDirection.incoming,
            state: MessageState.received,
            plaintext: plaintext,
            serializedPacket: serialized,
            createdAt: delivered.createdAt,
            expiresAt: delivered.expiresAt,
          ),
        );
      },
    );
    await _transport.acknowledge(delivered.packetId);
    return false;
  }

  Future<T> _serializedSync<T>(Future<T> Function() action) {
    final previous = _syncTail;
    final release = Completer<void>();
    _syncTail = release.future;
    return () async {
      await previous;
      try {
        return await action();
      } finally {
        release.complete();
      }
    }();
  }
}
