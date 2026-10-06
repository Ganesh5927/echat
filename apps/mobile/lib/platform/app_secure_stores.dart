import 'dart:convert';

import 'package:echat_identity/echat_identity.dart';
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
  AppSecureSessionStore({required this._secureStore});

  final SecureValueStore _secureStore;
  static const String _recordPrefix = 'echat.session.record.';
  static const String _secretPrefix = 'echat.session.secret.';

  Future<SharedPreferences> get _prefs async => SharedPreferences.getInstance();

  Future<List<SessionRecord>> listSessionRecords() async {
    final prefs = await _prefs;
    final sessions = <SessionRecord>[];
    for (final key in prefs.getKeys().where(
      (key) => key.startsWith(_recordPrefix),
    )) {
      final value = prefs.getString(key);
      if (value != null && value.isNotEmpty) {
        sessions.add(
          SessionRecord.fromJson(jsonDecode(value) as Map<String, dynamic>),
        );
      }
    }
    return List.unmodifiable(sessions);
  }

  @override
  Future<void> saveSessionRecord(String sessionId, SessionRecord record) async {
    await (await _prefs).setString(
      '$_recordPrefix$sessionId',
      jsonEncode(record.toJson()),
    );
  }

  @override
  Future<SessionRecord?> loadSessionRecord(String sessionId) async {
    final value = (await _prefs).getString('$_recordPrefix$sessionId');
    if (value == null || value.isEmpty) return null;
    return SessionRecord.fromJson(jsonDecode(value) as Map<String, dynamic>);
  }

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
  Future<void> deleteSession(String sessionId) async {
    await (await _prefs).remove('$_recordPrefix$sessionId');
    await deleteSessionSecret(sessionId);
  }

  @override
  Future<void> deleteSessionSecret(String sessionId) =>
      _secureStore.delete('$_secretPrefix$sessionId');

  @override
  Future<bool> hasSession(String sessionId) async =>
      (await _prefs).containsKey('$_recordPrefix$sessionId') ||
      await _secureStore.read('$_secretPrefix$sessionId') != null;
}
