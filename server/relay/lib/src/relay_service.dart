import 'dart:collection';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' show sha256;
import 'package:echat_transport/echat_transport.dart';

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
  }) : config = config,
       _clock = clock ?? DateTime.now {
    config.validate();
  }

  final RelayConfig config;
  final DateTime Function() _clock;
  final Map<String, _StoredPacket> _packets = {};
  int get pendingPacketCount =>
      _packets.values
        .where((packet) => !packet.acknowledged && !packet.expired)
        .length;

  Future<RelaySubmission> submit({
    required String authenticatedSenderRouteId,
    required PacketSubmission packet,
  }) async {
    _cleanupExpired();
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
    _packets[packet.packetId] = stored;
    return RelaySubmission(
      packetId: stored.packetId,
      state: 'queued',
      queuedAt: stored.queuedAt,
      expiresAt: stored.expiresAt,
    );
  }

  Future<List<DeliveredPacket>> receive({
    required String authenticatedRecipientRouteId,
  }) async {
    _cleanupExpired();
    PacketSubmission.validateRoute(authenticatedRecipientRouteId);
    final now = _clock().toUtc();
    final pending = _packets.values
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
    packet.deliveryCount++;
    packet.deliveredAt ??= now;
    return [
      DeliveredPacket(
        packetId: packet.packetId,
        senderRouteId: packet.senderRouteId,
        recipientRouteId: packet.recipientRouteId,
        createdAt: packet.queuedAt,
        expiresAt: packet.expiresAt,
        state: RelayPacketState.delivered,
        encryptedPacket: packet.encryptedPacket,
      ),
    ];
  }

  Future<RelayAcknowledgementResult> acknowledge({
    required String authenticatedRecipientRouteId,
    required String packetId,
  }) async {
    _cleanupExpired();
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
      packet.expired = true;
      packet.encryptedPacket.fillRange(0, packet.encryptedPacket.length, 0);
      packet.encryptedPacket = Uint8List(0);
      throw const RelayServiceException('packet_expired', 410);
    }
    packet.acknowledged = true;
    packet.encryptedPacket.fillRange(0, packet.encryptedPacket.length, 0);
    packet.encryptedPacket = Uint8List(0);
    return RelayAcknowledgementResult(
      packetId: packet.packetId,
      state: 'acknowledged',
    );
  }

  int cleanup() => _cleanupExpired();

  int _cleanupExpired() {
    final now = _clock().toUtc();
    var removed = 0;
    for (final entry in _packets.entries.toList(growable: false)) {
      final packet = entry.value;
        final newlyExpired =
          !packet.acknowledged &&
          !packet.expired &&
          !packet.expiresAt.isAfter(now);
        if (newlyExpired) {
        packet.expired = true;
        packet.encryptedPacket.fillRange(0, packet.encryptedPacket.length, 0);
        packet.encryptedPacket = Uint8List(0);
        }
      final tombstoneExpired =
            (packet.acknowledged || packet.expired) &&
            !packet.expiresAt
              .add(config.acknowledgementRetention)
              .isAfter(now);
        if (tombstoneExpired) {
        _packets.remove(entry.key);
        removed++;
      }
    }
    return removed;
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
  });

  final String packetId;
  final String senderRouteId;
  final String recipientRouteId;
  Uint8List encryptedPacket;
  final String encryptedPacketDigest;
  final DateTime queuedAt;
  final DateTime expiresAt;
  int deliveryCount = 0;
  DateTime? deliveredAt;
  bool acknowledged = false;
  bool expired = false;

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