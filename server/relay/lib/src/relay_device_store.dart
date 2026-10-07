import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:echat_identity/echat_identity.dart';

class RelayRegisteredDevice {
  const RelayRegisteredDevice({
    required this.deviceId,
    required this.publicKeyPem,
    required this.fingerprint,
    required this.registeredAt,
  });

  final String deviceId;
  final String publicKeyPem;
  final String fingerprint;
  final DateTime registeredAt;

  Map<String, Object?> toJson() => {
    'deviceId': deviceId,
    'publicKeyPem': publicKeyPem,
    'fingerprint': fingerprint,
    'registeredAt': registeredAt.toUtc().toIso8601String(),
  };

  factory RelayRegisteredDevice.fromJson(Map<String, dynamic> json) {
    const keys = {'deviceId', 'publicKeyPem', 'fingerprint', 'registeredAt'};
    if (json.length != keys.length || !json.keys.toSet().containsAll(keys)) {
      throw const FormatException('Malformed relay device registration.');
    }
    try {
      final deviceId = json['deviceId'];
      final publicKeyPem = json['publicKeyPem'];
      final fingerprint = json['fingerprint'];
      final registeredAt = json['registeredAt'];
      if (deviceId is! String ||
          publicKeyPem is! String ||
          fingerprint is! String ||
          registeredAt is! String) {
        throw const FormatException('Malformed relay device registration.');
      }
      final payload = PublicIdentityQrPayload(
        version: PublicIdentityQrPayload.currentVersion,
        deviceId: deviceId,
        publicKeyPem: publicKeyPem,
        fingerprint: fingerprint,
        createdAt: DateTime.utc(2000),
      );
      payload.validate();
      return RelayRegisteredDevice(
        deviceId: deviceId,
        publicKeyPem: publicKeyPem,
        fingerprint: fingerprint,
        registeredAt: DateTime.parse(registeredAt).toUtc(),
      );
    } on FormatException {
      rethrow;
    } on Object {
      throw const FormatException('Malformed relay device registration.');
    }
  }
}

abstract interface class RelayDeviceStore {
  Future<List<RelayRegisteredDevice>> loadAll();
  Future<void> save(RelayRegisteredDevice device);
}

class MemoryRelayDeviceStore implements RelayDeviceStore {
  final Map<String, RelayRegisteredDevice> _devices = {};

  @override
  Future<List<RelayRegisteredDevice>> loadAll() async =>
      List.unmodifiable(_devices.values);

  @override
  Future<void> save(RelayRegisteredDevice device) async {
    _devices[device.deviceId] = device;
  }
}

class FileRelayDeviceStore implements RelayDeviceStore {
  FileRelayDeviceStore({required Directory directory}) : _directory = directory;

  final Directory _directory;
  Future<void> _tail = Future<void>.value();

  @override
  Future<List<RelayRegisteredDevice>> loadAll() => _serialized(() async {
    await _recoverFiles();
    if (!await _directory.exists()) return const [];
    final devices = <RelayRegisteredDevice>[];
    await for (final entity in _directory.list(followLinks: false)) {
      if (entity is! File || !entity.path.endsWith('.device')) continue;
      final decoded = jsonDecode(await entity.readAsString());
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('Malformed relay device registration.');
      }
      final device = RelayRegisteredDevice.fromJson(decoded);
      if (entity.path != _fileFor(device.deviceId).path) {
        throw const FormatException('Relay device registration path mismatch.');
      }
      devices.add(device);
    }
    return List.unmodifiable(devices);
  });

  @override
  Future<void> save(RelayRegisteredDevice device) => _serialized(() async {
    await _directory.create(recursive: true);
    final target = _fileFor(device.deviceId);
    final temporary = File(
      '${target.path}.tmp-${DateTime.now().microsecondsSinceEpoch}',
    );
    final backup = File('${target.path}.bak');
    await temporary.writeAsString(jsonEncode(device.toJson()), flush: true);
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

  File _fileFor(String deviceId) => File(
    '${_directory.path}${Platform.pathSeparator}'
    '${sha256.convert(utf8.encode(deviceId))}.device',
  );

  Future<void> _recoverFiles() async {
    if (!await _directory.exists()) return;
    await for (final entity in _directory.list(followLinks: false)) {
      if (entity is! File) continue;
      if (entity.path.endsWith('.device.bak')) {
        final target = File(
          entity.path.substring(0, entity.path.length - '.bak'.length),
        );
        if (await target.exists()) {
          await entity.delete();
        } else {
          await entity.rename(target.path);
        }
      } else if (entity.path.contains('.device.tmp-')) {
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
