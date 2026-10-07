import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:echat_identity/echat_identity.dart';

import 'encrypted_message_store.dart';

class SessionRecordStoreException implements Exception {
  const SessionRecordStoreException(this.code);

  final String code;

  @override
  String toString() => 'SessionRecordStoreException: $code';
}

class EncryptedSessionRecordStore {
  EncryptedSessionRecordStore({
    required EncryptedRecordBackend backend,
    required LocalStorageKeyProvider keyProvider,
  }) : _backend = backend,
       _keyProvider = keyProvider;

  static const int _version = 1;
  static const List<int> _associatedData = [
    101,
    67,
    104,
    97,
    116,
    32,
    115,
    101,
    115,
    115,
    105,
    111,
    110,
    32,
    114,
    101,
    99,
    111,
    114,
    100,
    32,
    118,
    49,
  ];

  final EncryptedRecordBackend _backend;
  final LocalStorageKeyProvider _keyProvider;
  final AesGcm _aead = AesGcm.with256bits(nonceLength: 12);
  Future<void> _tail = Future<void>.value();

  Future<SessionRecord?> load(String sessionId) => _serialized(() async {
    final bytes = await _backend.read(_recordId(sessionId));
    if (bytes == null) return null;
    final record = await _decrypt(bytes);
    if (record.sessionId != sessionId) {
      throw const SessionRecordStoreException('session_record_id_mismatch');
    }
    return record;
  });

  Future<List<SessionRecord>> loadAll() => _serialized(() async {
    final records = <SessionRecord>[];
    for (final bytes in await _backend.readAll()) {
      records.add(await _decrypt(bytes));
    }
    return List.unmodifiable(records);
  });

  Future<void> save(String sessionId, SessionRecord record) =>
      _serialized(() async {
        if (record.sessionId != sessionId) {
          throw const SessionRecordStoreException('session_record_id_mismatch');
        }
        await _backend.write(_recordId(sessionId), await _encrypt(record));
      });

  Future<void> delete(String sessionId) =>
      _serialized(() => _backend.delete(_recordId(sessionId)));

  String _recordId(String sessionId) {
    if (sessionId.isEmpty || sessionId.length > 128) {
      throw const SessionRecordStoreException('invalid_session_record_id');
    }
    return sessionId;
  }

  Future<Uint8List> _encrypt(SessionRecord record) async {
    final cleartext = Uint8List.fromList(
      utf8.encode(jsonEncode(record.toJson())),
    );
    try {
      final box = await _aead.encrypt(
        cleartext,
        secretKey: await _keyProvider(),
        nonce: _aead.newNonce(),
        aad: _associatedData,
      );
      return Uint8List.fromList(
        utf8.encode(
          jsonEncode({
            'version': _version,
            'nonce': base64Encode(box.nonce),
            'ciphertext': base64Encode(box.cipherText),
            'tag': base64Encode(box.mac.bytes),
          }),
        ),
      );
    } on Object {
      throw const SessionRecordStoreException(
        'session_record_encryption_failed',
      );
    } finally {
      cleartext.fillRange(0, cleartext.length, 0);
    }
  }

  Future<SessionRecord> _decrypt(List<int> bytes) async {
    try {
      final decoded = jsonDecode(utf8.decode(bytes));
      if (decoded is! Map<String, dynamic> ||
          decoded.length != 4 ||
          !decoded.keys.toSet().containsAll(const {
            'version',
            'nonce',
            'ciphertext',
            'tag',
          }) ||
          decoded['version'] != _version) {
        throw const SessionRecordStoreException(
          'malformed_encrypted_session_record',
        );
      }
      final nonce = _decodeBase64(decoded['nonce'], 12);
      final ciphertext = _decodeBase64(decoded['ciphertext']);
      final tag = _decodeBase64(decoded['tag'], 16);
      final cleartext = await _aead.decrypt(
        SecretBox(ciphertext, nonce: nonce, mac: Mac(tag)),
        secretKey: await _keyProvider(),
        aad: _associatedData,
      );
      try {
        final value = jsonDecode(utf8.decode(cleartext));
        if (value is! Map<String, dynamic>) {
          throw const SessionRecordStoreException('malformed_session_record');
        }
        return SessionRecord.fromJson(value);
      } finally {
        cleartext.fillRange(0, cleartext.length, 0);
      }
    } on SessionRecordStoreException {
      rethrow;
    } on Object {
      throw const SessionRecordStoreException(
        'session_record_decryption_failed',
      );
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

List<int> _decodeBase64(Object? value, [int? expectedLength]) {
  if (value is! String) {
    throw const SessionRecordStoreException(
      'malformed_encrypted_session_record',
    );
  }
  try {
    final bytes = base64Decode(value);
    if (base64Encode(bytes) != value ||
        (expectedLength != null && bytes.length != expectedLength)) {
      throw const SessionRecordStoreException(
        'malformed_encrypted_session_record',
      );
    }
    return bytes;
  } on SessionRecordStoreException {
    rethrow;
  } on Object {
    throw const SessionRecordStoreException(
      'malformed_encrypted_session_record',
    );
  }
}
