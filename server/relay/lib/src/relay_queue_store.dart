import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' show sha256;

class RelayQueueRecord {
  RelayQueueRecord({
    required this.packetId,
    required this.senderRouteId,
    required this.recipientRouteId,
    required List<int> encryptedPacket,
    required this.encryptedPacketDigest,
    required this.queuedAt,
    required this.expiresAt,
    required this.deliveryCount,
    required this.deliveredAt,
    required this.acknowledged,
    required this.expired,
  }) : encryptedPacket = Uint8List.fromList(encryptedPacket);

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

  Map<String, Object?> toJson() => {
    'packetId': packetId,
    'senderRouteId': senderRouteId,
    'recipientRouteId': recipientRouteId,
    'encryptedPacket': base64Encode(encryptedPacket),
    'encryptedPacketDigest': encryptedPacketDigest,
    'queuedAt': queuedAt.toUtc().toIso8601String(),
    'expiresAt': expiresAt.toUtc().toIso8601String(),
    'deliveryCount': deliveryCount,
    'deliveredAt': deliveredAt?.toUtc().toIso8601String(),
    'acknowledged': acknowledged,
    'expired': expired,
  };

  factory RelayQueueRecord.fromJson(Map<String, dynamic> json) {
    const fields = {
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
    };
    if (json.length != fields.length ||
        !json.keys.toSet().containsAll(fields)) {
      throw const FormatException('Malformed relay queue record.');
    }
    final encodedPacket = json['encryptedPacket'];
    if (encodedPacket is! String) {
      throw const FormatException('Malformed relay queue record.');
    }
    final bytes = base64Decode(encodedPacket);
    if (base64Encode(bytes) != encodedPacket) {
      throw const FormatException('Malformed relay queue record.');
    }
    final deliveryCount = json['deliveryCount'];
    final acknowledged = json['acknowledged'];
    final expired = json['expired'];
    final deliveredAt = json['deliveredAt'];
    if (deliveryCount is! int ||
        deliveryCount < 0 ||
        acknowledged is! bool ||
        expired is! bool ||
        (deliveredAt != null && deliveredAt is! String)) {
      throw const FormatException('Malformed relay queue record.');
    }
    return RelayQueueRecord(
      packetId: _requiredString(json, 'packetId'),
      senderRouteId: _requiredString(json, 'senderRouteId'),
      recipientRouteId: _requiredString(json, 'recipientRouteId'),
      encryptedPacket: bytes,
      encryptedPacketDigest: _requiredString(json, 'encryptedPacketDigest'),
      queuedAt: DateTime.parse(_requiredString(json, 'queuedAt')).toUtc(),
      expiresAt: DateTime.parse(_requiredString(json, 'expiresAt')).toUtc(),
      deliveryCount: deliveryCount,
      deliveredAt: deliveredAt == null
          ? null
          : DateTime.parse(deliveredAt).toUtc(),
      acknowledged: acknowledged,
      expired: expired,
    );
  }
}

abstract interface class RelayQueueStore {
  Future<List<RelayQueueRecord>> loadAll();
  Future<void> save(RelayQueueRecord record);
  Future<void> delete(String packetId);
}

class MemoryRelayQueueStore implements RelayQueueStore {
  final Map<String, RelayQueueRecord> _records = {};

  @override
  Future<void> delete(String packetId) async {
    _records.remove(_recordKey(packetId));
  }

  @override
  Future<List<RelayQueueRecord>> loadAll() async =>
      List.unmodifiable(_records.values);

  @override
  Future<void> save(RelayQueueRecord record) async {
    _records[_recordKey(record.packetId)] = record;
  }
}

class FileRelayQueueStore implements RelayQueueStore {
  FileRelayQueueStore({required Directory directory}) : _directory = directory;

  final Directory _directory;
  static final Random _random = Random.secure();
  Future<void> _tail = Future<void>.value();

  @override
  Future<List<RelayQueueRecord>> loadAll() => _serialized(() async {
    await _recoverFiles();
    if (!await _directory.exists()) return const [];
    final records = <RelayQueueRecord>[];
    await for (final entity in _directory.list(followLinks: false)) {
      if (entity is! File || !entity.path.endsWith('.queue')) continue;
      final decoded = jsonDecode(await entity.readAsString());
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('Malformed relay queue record.');
      }
      final record = RelayQueueRecord.fromJson(decoded);
      if (entity.path != _fileFor(record.packetId).path) {
        throw const FormatException('Relay queue record path mismatch.');
      }
      records.add(record);
    }
    return List.unmodifiable(records);
  });

  @override
  Future<void> save(RelayQueueRecord record) => _serialized(() async {
    await _directory.create(recursive: true);
    final target = _fileFor(record.packetId);
    final temporary = File(
      '${target.path}.tmp-${DateTime.now().microsecondsSinceEpoch}-${_random.nextInt(1 << 32)}',
    );
    final backup = File('${target.path}.bak');
    await temporary.writeAsString(jsonEncode(record.toJson()), flush: true);
    try {
      if (await backup.exists()) await backup.delete();
      if (await target.exists()) await target.rename(backup.path);
      await temporary.rename(target.path);
      if (await backup.exists()) await backup.delete();
    } on Object {
      if (!await target.exists() && await backup.exists()) {
        await backup.rename(target.path);
      }
      if (await temporary.exists()) await temporary.delete();
      rethrow;
    }
  });

  @override
  Future<void> delete(String packetId) => _serialized(() async {
    final target = _fileFor(packetId);
    for (final file in [target, File('${target.path}.bak')]) {
      if (await file.exists()) await file.delete();
    }
  });

  File _fileFor(String packetId) => File(
    '${_directory.path}${Platform.pathSeparator}${_recordKey(packetId)}.queue',
  );

  Future<void> _recoverFiles() async {
    if (!await _directory.exists()) return;
    await for (final entity in _directory.list(followLinks: false)) {
      if (entity is! File) continue;
      if (entity.path.endsWith('.queue.bak')) {
        final target = File(entity.path.substring(0, entity.path.length - 4));
        if (await target.exists()) {
          await entity.delete();
        } else {
          await entity.rename(target.path);
        }
      } else if (entity.path.contains('.queue.tmp-')) {
        await entity.delete();
      }
    }
  }

  Future<T> _serialized<T>(Future<T> Function() action) {
    final previous = _tail;
    final release = Completer<void>();
    _tail = release.future;
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

String _recordKey(String packetId) =>
    sha256.convert(utf8.encode(packetId)).toString();

String _requiredString(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! String || value.isEmpty) {
    throw const FormatException('Malformed relay queue record.');
  }
  return value;
}
