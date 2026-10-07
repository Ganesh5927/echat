import 'dart:collection';
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' show sha256;
import 'package:echat_transport/echat_transport.dart';

import 'relay_queue_store.dart';

class RelayServiceException implements Exception {
  const RelayServiceException(this.code, this.statusCode);

  final String code;
  final int statusCode;

  @override
  String toString() => 'RelayServiceException: $code';
}

class RelayConfig {
  const RelayConfig({
    this.maxPacketBytes = 16 * 1024 * 1024,
    this.maxRequestBytes = 24 * 1024 * 1024,
    this.maxPacketLifetime = const Duration(hours: 24),
    this.acknowledgementRetention = const Duration(hours: 1),
    this.maxPackets = 10000,
    this.maxPacketsPerRecipient = 200,
    this.maxPacketsPerPoll = 1,
    this.maxConcurrentRequests = 64,
    this.rateLimitRequests = 120,
    this.rateLimitWindow = const Duration(minutes: 1),
  });

  final int maxPacketBytes;
  final int maxRequestBytes;
  final Duration maxPacketLifetime;
  final Duration acknowledgementRetention;
  final int maxPackets;
  final int maxPacketsPerRecipient;
  final int maxPacketsPerPoll;
  final int maxConcurrentRequests;
  final int rateLimitRequests;
  final Duration rateLimitWindow;

  void validate() {
    if (maxPacketBytes < 1 ||
        maxPacketBytes > PacketSubmission.maxEncryptedPacketBytes ||
        maxRequestBytes < maxPacketBytes ||
        maxPacketLifetime <= Duration.zero ||
        acknowledgementRetention < Duration.zero ||
        maxPackets < 1 ||
        maxPacketsPerRecipient < 1 ||
        maxPacketsPerPoll != 1 ||
        maxConcurrentRequests < 1 ||
        rateLimitRequests < 1 ||
        rateLimitWindow <= Duration.zero) {
      throw ArgumentError('Relay configuration is invalid.');
    }
  }
}

class RelaySubmission {
  const RelaySubmission({
    required this.packetId,
    required this.state,
    required this.queuedAt,
    required this.expiresAt,
  });

  final String packetId;
  final String state;
  final DateTime queuedAt;
  final DateTime expiresAt;

  Map<String, dynamic> toJson() => {
    'packetId': packetId,
    'state': state,
    'queuedAt': queuedAt.toUtc().toIso8601String(),
    'expiresAt': expiresAt.toUtc().toIso8601String(),
  };
}

class RelayAcknowledgementResult {
  const RelayAcknowledgementResult({
    required this.packetId,
    required this.state,
  });

  final String packetId;
  final String state;

  Map<String, dynamic> toJson() => {'packetId': packetId, 'state': state};
}

class RelayAuthenticator {
  const RelayAuthenticator();

  Future<String?> authenticate(String? authorizationHeader) async => null;

  Future<bool> isRegisteredDeviceRoute(String routeId) async => true;
}

class CallbackRelayAuthenticator extends RelayAuthenticator {
  const CallbackRelayAuthenticator(this._authenticate);

  final Future<String?> Function(String?) _authenticate;

  @override
  Future<String?> authenticate(String? authorizationHeader) =>
      _authenticate(authorizationHeader);
}

class RelayService {
  RelayService({
    RelayConfig config = const RelayConfig(),
    DateTime Function()? clock,
    RelayQueueStore? queueStore,
  }) : config = config,
       _clock = clock ?? DateTime.now,
       _queueStore =
           queueStore ??
           FileRelayQueueStore(directory: Directory('.echat-relay-queue')) {
    config.validate();
  }

  final RelayConfig config;
  final DateTime Function() _clock;
  final RelayQueueStore _queueStore;
  final Map<String, _StoredPacket> _packets = {};
  Future<void>? _initialization;
  Future<void> _tail = Future<void>.value();

  Future<void> initialize() => _initialization ??= _restore();

  int get pendingPacketCount => _packets.values
      .where((packet) => !packet.acknowledged && !packet.expired)
      .length;

  Future<RelaySubmission> submit({
    required String authenticatedSenderRouteId,
    required PacketSubmission packet,
  }) => _exclusive(() async {
    await _cleanupExpired();
    PacketSubmission.validateRoute(authenticatedSenderRouteId);
    try {
      packet.validate();
    } on TransportException catch (error) {
      throw RelayServiceException(error.code, 400);
    }
    if (packet.encryptedPacket.length > config.maxPacketBytes) {
      throw const RelayServiceException('packet_too_large', 413);
    }

    final now = _clock().toUtc();
    final existing = _packets[packet.packetId];
    if (existing != null) {
      if (!existing.matches(authenticatedSenderRouteId, packet)) {
        throw const RelayServiceException('packet_id_conflict', 409);
      }
      return RelaySubmission(
        packetId: existing.packetId,
        state: existing.acknowledged
            ? 'acknowledged'
            : existing.expired
            ? 'expired'
            : 'duplicate',
        queuedAt: existing.queuedAt,
        expiresAt: existing.expiresAt,
      );
    }

    if (!packet.expiresAt.isAfter(now)) {
      throw const RelayServiceException('packet_expired', 410);
    }
    final maximumExpiry = now.add(config.maxPacketLifetime);
    final expiresAt = packet.expiresAt.isAfter(maximumExpiry)
        ? maximumExpiry
        : packet.expiresAt.toUtc();

    final recipientPending = _packets.values
        .where(
          (candidate) =>
              !candidate.acknowledged &&
              !candidate.expired &&
              candidate.recipientRouteId == packet.recipientRouteId,
        )
        .length;
    if (_packets.length >= config.maxPackets ||
        recipientPending >= config.maxPacketsPerRecipient) {
      throw const RelayServiceException('recipient_queue_full', 429);
    }

    final stored = _StoredPacket(
      packetId: packet.packetId,
      senderRouteId: authenticatedSenderRouteId,
      recipientRouteId: packet.recipientRouteId,
      encryptedPacket: Uint8List.fromList(packet.encryptedPacket),
      encryptedPacketDigest: sha256.convert(packet.encryptedPacket).toString(),
      queuedAt: now,
      expiresAt: expiresAt,
    );
    await _queueStore.save(stored.toRecord());
    _packets[packet.packetId] = stored;
    return RelaySubmission(
      packetId: stored.packetId,
      state: 'queued',
      queuedAt: stored.queuedAt,
      expiresAt: stored.expiresAt,
    );
  });

  Future<List<DeliveredPacket>> receive({
    required String authenticatedRecipientRouteId,
  }) => _exclusive(() async {
    await _cleanupExpired();
    PacketSubmission.validateRoute(authenticatedRecipientRouteId);
    final now = _clock().toUtc();
    final pending =
        _packets.values
            .where(
              (packet) =>
                  !packet.acknowledged &&
                  !packet.expired &&
                  packet.recipientRouteId == authenticatedRecipientRouteId &&
                  packet.expiresAt.isAfter(now),
            )
            .toList(growable: false)
          ..sort((left, right) => left.queuedAt.compareTo(right.queuedAt));

    if (pending.isEmpty) return const [];
    final packet = pending.first;
    final delivered = packet.copyWith(
      deliveryCount: packet.deliveryCount + 1,
      deliveredAt: packet.deliveredAt ?? now,
    );
    await _queueStore.save(delivered.toRecord());
    _packets[packet.packetId] = delivered;
    return [
      DeliveredPacket(
        packetId: delivered.packetId,
        senderRouteId: delivered.senderRouteId,
        recipientRouteId: delivered.recipientRouteId,
        createdAt: delivered.queuedAt,
        expiresAt: delivered.expiresAt,
        state: RelayPacketState.delivered,
        encryptedPacket: delivered.encryptedPacket,
      ),
    ];
  });

  Future<RelayAcknowledgementResult> acknowledge({
    required String authenticatedRecipientRouteId,
    required String packetId,
  }) => _exclusive(() async {
    await _cleanupExpired();
    final packet = _packets[packetId];
    if (packet == null) {
      throw const RelayServiceException('packet_not_found', 404);
    }
    if (packet.recipientRouteId != authenticatedRecipientRouteId) {
      throw const RelayServiceException('packet_not_found', 404);
    }
    if (packet.expired) {
      throw const RelayServiceException('packet_expired', 410);
    }
    if (packet.acknowledged) {
      return RelayAcknowledgementResult(
        packetId: packet.packetId,
        state: 'already_acknowledged',
      );
    }
    final now = _clock().toUtc();
    if (!packet.expiresAt.isAfter(now)) {
      final expired = packet.copyWith(
        expired: true,
        encryptedPacket: const <int>[],
      );
      await _queueStore.save(expired.toRecord());
      packet.encryptedPacket.fillRange(0, packet.encryptedPacket.length, 0);
      _packets[packetId] = expired;
      throw const RelayServiceException('packet_expired', 410);
    }
    final acknowledged = packet.copyWith(
      acknowledged: true,
      encryptedPacket: const <int>[],
    );
    await _queueStore.save(acknowledged.toRecord());
    packet.encryptedPacket.fillRange(0, packet.encryptedPacket.length, 0);
    _packets[packetId] = acknowledged;
    return RelayAcknowledgementResult(
      packetId: packet.packetId,
      state: 'acknowledged',
    );
  });

  Future<int> cleanup() => _exclusive(_cleanupExpired);

  Future<int> _cleanupExpired() async {
    final now = _clock().toUtc();
    var removed = 0;
    for (final entry in _packets.entries.toList(growable: false)) {
      final packet = entry.value;
      if (!packet.acknowledged &&
          !packet.expired &&
          !packet.expiresAt.isAfter(now)) {
        final expired = packet.copyWith(
          expired: true,
          encryptedPacket: const <int>[],
        );
        await _queueStore.save(expired.toRecord());
        packet.encryptedPacket.fillRange(0, packet.encryptedPacket.length, 0);
        _packets[entry.key] = expired;
      }
      final updated = _packets[entry.key]!;
      final tombstoneExpired =
          (updated.acknowledged || updated.expired) &&
          !updated.expiresAt.add(config.acknowledgementRetention).isAfter(now);
      if (tombstoneExpired) {
        await _queueStore.delete(entry.key);
        _packets.remove(entry.key);
        removed++;
      }
    }
    return removed;
  }

  Future<void> _restore() async {
    final now = _clock().toUtc();
    final records = await _queueStore.loadAll();
    final restored = <String, _StoredPacket>{};
    final pendingPerRecipient = <String, int>{};
    for (final record in records) {
      PacketSubmission.validateRoute(record.packetId);
      PacketSubmission.validateRoute(record.senderRouteId);
      PacketSubmission.validateRoute(record.recipientRouteId);
      if (record.deliveryCount < 0 ||
          record.queuedAt.isAfter(record.expiresAt) ||
          record.acknowledged && record.expired ||
          (record.acknowledged || record.expired) !=
              record.encryptedPacket.isEmpty ||
          !RegExp(r'^[0-9a-f]{64}$').hasMatch(record.encryptedPacketDigest) ||
          (!record.acknowledged &&
              !record.expired &&
              (record.encryptedPacket.isEmpty ||
                  record.encryptedPacket.length > config.maxPacketBytes)) ||
          (record.encryptedPacket.isNotEmpty &&
              sha256.convert(record.encryptedPacket).toString() !=
                  record.encryptedPacketDigest)) {
        throw const FormatException('Invalid persisted relay queue record.');
      }
      if (restored.containsKey(record.packetId)) {
        throw const FormatException('Duplicate persisted relay packet ID.');
      }
      final loadedPacket = _StoredPacket.fromRecord(record);
      var packet = loadedPacket;
      if (!packet.acknowledged &&
          !packet.expired &&
          !packet.expiresAt.isAfter(now)) {
        packet = packet.copyWith(expired: true, encryptedPacket: const <int>[]);
        await _queueStore.save(packet.toRecord());
        loadedPacket.encryptedPacket.fillRange(
          0,
          loadedPacket.encryptedPacket.length,
          0,
        );
      }
      final tombstoneExpired =
          (packet.acknowledged || packet.expired) &&
          !packet.expiresAt.add(config.acknowledgementRetention).isAfter(now);
      if (tombstoneExpired) {
        await _queueStore.delete(packet.packetId);
        continue;
      }
      restored[packet.packetId] = packet;
      if (!packet.acknowledged && !packet.expired) {
        pendingPerRecipient.update(
          packet.recipientRouteId,
          (count) => count + 1,
          ifAbsent: () => 1,
        );
      }
    }
    if (restored.length > config.maxPackets ||
        pendingPerRecipient.values.any(
          (count) => count > config.maxPacketsPerRecipient,
        )) {
      throw const FormatException('Persisted relay queue exceeds limits.');
    }
    _packets.addAll(restored);
  }

  Future<T> _exclusive<T>(Future<T> Function() action) {
    final previous = _tail;
    final release = Completer<void>();
    _tail = release.future;
    return () async {
      await previous;
      try {
        await initialize();
        return await action();
      } finally {
        release.complete();
      }
    }();
  }
}

class _StoredPacket {
  _StoredPacket({
    required this.packetId,
    required this.senderRouteId,
    required this.recipientRouteId,
    required this.encryptedPacket,
    required this.encryptedPacketDigest,
    required this.queuedAt,
    required this.expiresAt,
    this.deliveryCount = 0,
    this.deliveredAt,
    this.acknowledged = false,
    this.expired = false,
  });

  final String packetId;
  final String senderRouteId;
  final String recipientRouteId;
  final Uint8List encryptedPacket;
  final String encryptedPacketDigest;
  final DateTime queuedAt;
  final DateTime expiresAt;
  final int deliveryCount;
  final DateTime? deliveredAt;
  final bool acknowledged;
  final bool expired;

  factory _StoredPacket.fromRecord(RelayQueueRecord record) => _StoredPacket(
    packetId: record.packetId,
    senderRouteId: record.senderRouteId,
    recipientRouteId: record.recipientRouteId,
    encryptedPacket: record.encryptedPacket,
    encryptedPacketDigest: record.encryptedPacketDigest,
    queuedAt: record.queuedAt,
    expiresAt: record.expiresAt,
    deliveryCount: record.deliveryCount,
    deliveredAt: record.deliveredAt,
    acknowledged: record.acknowledged,
    expired: record.expired,
  );

  RelayQueueRecord toRecord() => RelayQueueRecord(
    packetId: packetId,
    senderRouteId: senderRouteId,
    recipientRouteId: recipientRouteId,
    encryptedPacket: encryptedPacket,
    encryptedPacketDigest: encryptedPacketDigest,
    queuedAt: queuedAt,
    expiresAt: expiresAt,
    deliveryCount: deliveryCount,
    deliveredAt: deliveredAt,
    acknowledged: acknowledged,
    expired: expired,
  );

  _StoredPacket copyWith({
    List<int>? encryptedPacket,
    int? deliveryCount,
    DateTime? deliveredAt,
    bool? acknowledged,
    bool? expired,
  }) => _StoredPacket(
    packetId: packetId,
    senderRouteId: senderRouteId,
    recipientRouteId: recipientRouteId,
    encryptedPacket: Uint8List.fromList(
      encryptedPacket ?? this.encryptedPacket,
    ),
    encryptedPacketDigest: encryptedPacketDigest,
    queuedAt: queuedAt,
    expiresAt: expiresAt,
    deliveryCount: deliveryCount ?? this.deliveryCount,
    deliveredAt: deliveredAt ?? this.deliveredAt,
    acknowledged: acknowledged ?? this.acknowledged,
    expired: expired ?? this.expired,
  );

  bool matches(String senderRouteId, PacketSubmission packet) {
    if (this.senderRouteId != senderRouteId ||
        recipientRouteId != packet.recipientRouteId ||
        encryptedPacketDigest !=
            sha256.convert(packet.encryptedPacket).toString()) {
      return false;
    }
    return true;
  }
}

class SlidingWindowRateLimiter {
  SlidingWindowRateLimiter({
    required this.maxRequests,
    required this.window,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now {
    if (maxRequests < 1 || window <= Duration.zero) {
      throw ArgumentError('Rate limit configuration is invalid.');
    }
  }

  final int maxRequests;
  final Duration window;
  final DateTime Function() _clock;
  final Map<String, Queue<DateTime>> _events = {};

  bool allow(String principal) {
    final now = _clock().toUtc();
    final events = _events.putIfAbsent(principal, Queue<DateTime>.new);
    final cutoff = now.subtract(window);
    while (events.isNotEmpty && !events.first.isAfter(cutoff)) {
      events.removeFirst();
    }
    if (events.length >= maxRequests) return false;
    events.addLast(now);
    return true;
  }
}
