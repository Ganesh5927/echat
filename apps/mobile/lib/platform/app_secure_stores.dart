import 'dart:async';
import 'dart:convert';

import 'package:echat_identity/echat_identity.dart';
import 'package:echat_storage/echat_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'secure_value_store.dart';

class AppSecureIdentityStore implements SecureIdentityStore {
  AppSecureIdentityStore({required this._secureStore});

  final SecureValueStore _secureStore;
  static const String _privateKeyKey = 'echat.identity.private_key';
  static const String _publicIdentityKey = 'echat.identity.public_identity';

  Future<SharedPreferences> get _prefs async => SharedPreferences.getInstance();

  @override
  Future<void> savePrivateKey(String privateKeyPem) async {
    await _secureStore.write(_privateKeyKey, privateKeyPem);
  }

  @override
  Future<String?> loadPrivateKey() => _secureStore.read(_privateKeyKey);

  @override
  Future<void> savePublicIdentity(Map<String, dynamic> publicIdentity) async {
    await (await _prefs).setString(
      _publicIdentityKey,
      jsonEncode(publicIdentity),
    );
  }

  @override
  Future<Map<String, dynamic>?> loadPublicIdentity() async {
    final value = (await _prefs).getString(_publicIdentityKey);
    if (value == null || value.isEmpty) return null;
    return jsonDecode(value) as Map<String, dynamic>;
  }

  @override
  Future<void> deleteAll() async {
    await _secureStore.delete(_privateKeyKey);
    await (await _prefs).remove(_publicIdentityKey);
  }

  @override
  Future<bool> hasIdentity() async {
    final privateKey = await loadPrivateKey();
    return privateKey != null &&
        privateKey.isNotEmpty &&
        (await _prefs).containsKey(_publicIdentityKey);
  }
}

class AppSecureSessionStore implements SecureSessionStore {
  AppSecureSessionStore({
    required this._secureStore,
    required this._encryptedRecords,
  });

  final SecureValueStore _secureStore;
  final EncryptedSessionRecordStore _encryptedRecords;
  static const String _recordPrefix = 'echat.session.record.';
  static const String _secretPrefix = 'echat.session.secret.';
  Future<void> _recordTail = Future<void>.value();

  Future<SharedPreferences> get _prefs async => SharedPreferences.getInstance();

  Future<List<SessionRecord>> listSessionRecords() async {
    return _serializeRecords(() async {
      await _migrateLegacyRecords();
      return _encryptedRecords.loadAll();
    });
  }

  Future<void> migrateLegacySessionRecords() =>
      _serializeRecords(_migrateLegacyRecords);

  @override
  Future<void> saveSessionRecord(String sessionId, SessionRecord record) =>
      _serializeRecords(() async {
        await _encryptedRecords.save(sessionId, record);
        await (await _prefs).remove('$_recordPrefix$sessionId');
      });

  @override
  Future<SessionRecord?> loadSessionRecord(String sessionId) =>
      _serializeRecords(() async {
        await _migrateLegacyRecord(sessionId);
        return _encryptedRecords.load(sessionId);
      });

  @override
  Future<void> saveSessionSecret(
    String sessionId,
    SessionSecretBundle bundle,
  ) => _secureStore.write(
    '$_secretPrefix$sessionId',
    jsonEncode(bundle.toJson()),
  );

  @override
  Future<SessionSecretBundle?> loadSessionSecret(String sessionId) async {
    final value = await _secureStore.read('$_secretPrefix$sessionId');
    if (value == null || value.isEmpty) return null;
    return SessionSecretBundle.fromJson(
      jsonDecode(value) as Map<String, dynamic>,
    );
  }

  @override
  Future<void> deleteSession(String sessionId) => _serializeRecords(() async {
    await _encryptedRecords.delete(sessionId);
    await (await _prefs).remove('$_recordPrefix$sessionId');
    await deleteSessionSecret(sessionId);
  });

  @override
  Future<void> deleteSessionSecret(String sessionId) =>
      _secureStore.delete('$_secretPrefix$sessionId');

  @override
  Future<bool> hasSession(String sessionId) async =>
      await loadSessionRecord(sessionId) != null ||
      await _secureStore.read('$_secretPrefix$sessionId') != null;

  Future<void> _migrateLegacyRecords() async {
    final prefs = await _prefs;
    final sessionIds = prefs
        .getKeys()
        .where((key) => key.startsWith(_recordPrefix))
        .map((key) => key.substring(_recordPrefix.length))
        .toList();
    for (final sessionId in sessionIds) {
      await _migrateLegacyRecord(sessionId);
    }
  }

  Future<void> _migrateLegacyRecord(String sessionId) async {
    final prefs = await _prefs;
    final key = '$_recordPrefix$sessionId';
    final value = prefs.getString(key);
    if (value == null || value.isEmpty) return;
    final record = SessionRecord.fromJson(
      jsonDecode(value) as Map<String, dynamic>,
    );
    if (record.sessionId != sessionId) {
      throw const FormatException('Session record key does not match record.');
    }
    await _encryptedRecords.save(sessionId, record);
    await prefs.remove(key);
  }

  Future<T> _serializeRecords<T>(Future<T> Function() action) {
    final previous = _recordTail;
    final release = Completer<void>();
    _recordTail = release.future;
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
