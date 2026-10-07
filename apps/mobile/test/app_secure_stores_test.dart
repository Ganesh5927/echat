import 'dart:convert';
import 'dart:typed_data';

import 'package:echat_identity/echat_identity.dart';
import 'package:echat_mobile/platform/app_local_storage_key_provider.dart';
import 'package:echat_mobile/platform/app_secure_stores.dart';
import 'package:echat_mobile/platform/secure_value_store.dart';
import 'package:echat_storage/echat_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MemorySecureValueStore implements SecureValueStore {
  final Map<String, String> values = {};

  @override
  Future<void> delete(String key) async => values.remove(key);

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }
}

class _FailingWriteBackend implements EncryptedRecordBackend {
  @override
  Future<void> delete(String recordId) async {}

  @override
  Future<Uint8List?> read(String recordId) async => null;

  @override
  Future<List<Uint8List>> readAll() async => const [];

  @override
  Future<void> write(String recordId, List<int> encryptedRecord) async {
    throw StateError('write failed');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'session records migrate from preferences to encrypted records',
    () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final secureValues = _MemorySecureValueStore();
      final backend = MemoryEncryptedRecordBackend();
      final record = SessionRecord(
        sessionId: 'session-id-1',
        localDeviceId: 'local-device-id',
        remoteDeviceId: 'remote-device-id',
        localIdentityPublicKeyPem: 'public-local-key',
        remoteIdentityPublicKeyPem: 'public-remote-key',
        sessionStatus: SessionState.established,
        createdAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026, 1, 1, 0, 1),
        sendSequence: 2,
        receiveSequence: 3,
        derivedKeyFingerprint: 'derived-key-fingerprint',
        seenMessageIds: const {'seen-message-id'},
      );
      const legacyKey = 'echat.session.record.session-id-1';
      await prefs.setString(legacyKey, jsonEncode(record.toJson()));

      final store = AppSecureSessionStore(
        secureStore: secureValues,
        encryptedRecords: EncryptedSessionRecordStore(
          backend: backend,
          keyProvider: AppLocalStorageKeyProvider(store: secureValues).call,
        ),
      );
      final restored = await store.listSessionRecords();

      expect(restored, hasLength(1));
      expect(restored.single.sessionId, record.sessionId);
      expect(restored.single.localDeviceId, record.localDeviceId);
      expect(restored.single.remoteDeviceId, record.remoteDeviceId);
      expect(restored.single.sessionStatus, SessionState.established);
      expect(restored.single.sendSequence, 2);
      expect(restored.single.receiveSequence, 3);
      expect(restored.single.seenMessageIds, {'seen-message-id'});
      expect(prefs.containsKey(legacyKey), isFalse);

      final storedBytes = await backend.read('session-id-1');
      expect(storedBytes, isNotNull);
      final storedText = utf8.decode(storedBytes!);
      expect(storedText, contains('"ciphertext"'));
      expect(storedText, isNot(contains('local-device-id')));
      expect(storedText, isNot(contains('public-local-key')));
      expect(storedText, isNot(contains('derived-key-fingerprint')));
      expect(storedText, isNot(contains('seen-message-id')));

      final reopenedStore = AppSecureSessionStore(
        secureStore: secureValues,
        encryptedRecords: EncryptedSessionRecordStore(
          backend: backend,
          keyProvider: AppLocalStorageKeyProvider(store: secureValues).call,
        ),
      );
      final reopened = await reopenedStore.loadSessionRecord(record.sessionId);
      expect(reopened?.sessionId, record.sessionId);
      expect(reopened?.derivedKeyFingerprint, record.derivedKeyFingerprint);
    },
  );

  test('session secret bundles remain in secure-value storage only', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final secureValues = _MemorySecureValueStore();
    final backend = MemoryEncryptedRecordBackend();
    final store = AppSecureSessionStore(
      secureStore: secureValues,
      encryptedRecords: EncryptedSessionRecordStore(
        backend: backend,
        keyProvider: AppLocalStorageKeyProvider(store: secureValues).call,
      ),
    );
    final record = SessionRecord(
      sessionId: 'session-id-2',
      localDeviceId: 'local-device-id',
      remoteDeviceId: 'remote-device-id',
      localIdentityPublicKeyPem: 'public-local-key',
      remoteIdentityPublicKeyPem: 'public-remote-key',
      sessionStatus: SessionState.established,
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
      sendSequence: 0,
      receiveSequence: 0,
    );
    final secret = SessionSecretBundle(
      sessionId: 'session-id-2',
      sessionKeyHex: 'session-key-material',
      localEphemeralPrivateKeyBase64: 'ephemeral-private-material',
      remoteEphemeralPublicKeyBase64: 'ephemeral-public-material',
      localIdentityPublicKeyPem: 'public-local-key',
      remoteIdentityPublicKeyPem: 'public-remote-key',
      derivedKeyFingerprint: 'derived-key-fingerprint',
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
      seenMessageIds: {'session-message-id'},
    );

    await store.saveSessionRecord(record.sessionId, record);
    await store.saveSessionSecret(secret.sessionId, secret);

    expect(await store.loadSessionRecord(record.sessionId), isNotNull);
    expect(await store.loadSessionSecret(secret.sessionId), isNotNull);
    expect(prefs.getKeys(), isEmpty);
    expect(secureValues.values, contains('echat.session.secret.session-id-2'));
    expect(
      secureValues.values['echat.session.secret.session-id-2'],
      contains('session-key-material'),
    );

    await store.deleteSession(secret.sessionId);
    expect(await store.loadSessionRecord(record.sessionId), isNull);
    expect(await store.loadSessionSecret(secret.sessionId), isNull);
    expect(await backend.read('session-id-2'), isNull);
    expect(
      secureValues.values.containsKey('echat.session.secret.session-id-2'),
      isFalse,
    );
  });

  test(
    'failed migration leaves the plaintext legacy record for retry',
    () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final secureValues = _MemorySecureValueStore();
      final record = SessionRecord(
        sessionId: 'session-id-3',
        localDeviceId: 'local-device-id',
        remoteDeviceId: 'remote-device-id',
        localIdentityPublicKeyPem: 'public-local-key',
        remoteIdentityPublicKeyPem: 'public-remote-key',
        sessionStatus: SessionState.pending,
        createdAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026),
        sendSequence: 0,
        receiveSequence: -1,
      );
      const legacyKey = 'echat.session.record.session-id-3';
      await prefs.setString(legacyKey, jsonEncode(record.toJson()));
      final store = AppSecureSessionStore(
        secureStore: secureValues,
        encryptedRecords: EncryptedSessionRecordStore(
          backend: _FailingWriteBackend(),
          keyProvider: AppLocalStorageKeyProvider(store: secureValues).call,
        ),
      );

      await expectLater(store.listSessionRecords(), throwsStateError);
      expect(prefs.getString(legacyKey), isNotNull);
    },
  );
}
