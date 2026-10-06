import 'dart:async';
import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:echat_identity/echat_identity.dart';

import 'encrypted_message_store.dart';

class EncryptedContactTrustStore implements ContactTrustStore {
  EncryptedContactTrustStore({
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
    99,
    111,
    110,
    116,
    97,
    99,
    116,
    32,
    116,
    114,
    117,
    115,
    116,
    32,
    118,
    49,
  ];

  final EncryptedRecordBackend _backend;
  final LocalStorageKeyProvider _keyProvider;
  final AesGcm _aead = AesGcm.with256bits(nonceLength: 12);
  Future<void> _tail = Future<void>.value();

  @override
  Future<ContactTrustRecord?> loadContact(String deviceId) =>
      _serialized(() async {
        final bytes = await _backend.read(_recordId(deviceId));
        if (bytes == null) return null;
        final contact = await _decrypt(bytes);
        if (contact.deviceId != deviceId) {
          throw const MessageStoreException('trust_record_id_mismatch');
        }
        return contact;
      });

  @override
  Future<List<ContactTrustRecord>> loadContacts() => _serialized(() async {
    final contacts = <ContactTrustRecord>[];
    for (final bytes in await _backend.readAll()) {
      contacts.add(await _decrypt(bytes));
    }
    return List.unmodifiable(contacts);
  });

  @override
  Future<void> saveContact(ContactTrustRecord contact) => _serialized(() async {
    await _backend.write(_recordId(contact.deviceId), await _encrypt(contact));
  });

  String _recordId(String deviceId) {
    if (deviceId.isEmpty || deviceId.length > 128) {
      throw const MessageStoreException('invalid_trust_record_id');
    }
    return 'contact-trust-$deviceId';
  }

  Future<List<int>> _encrypt(ContactTrustRecord contact) async {
    final cleartext = utf8.encode(jsonEncode(contact.toJson()));
    try {
      final box = await _aead.encrypt(
        cleartext,
        secretKey: await _keyProvider(),
        nonce: _aead.newNonce(),
        aad: _associatedData,
      );
      return utf8.encode(
        jsonEncode({
          'version': _version,
          'nonce': base64Encode(box.nonce),
          'ciphertext': base64Encode(box.cipherText),
          'tag': base64Encode(box.mac.bytes),
        }),
      );
    } on Object {
      throw const MessageStoreException('trust_record_encryption_failed');
    } finally {
      cleartext.fillRange(0, cleartext.length, 0);
    }
  }

  Future<ContactTrustRecord> _decrypt(List<int> bytes) async {
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
        throw const MessageStoreException('malformed_encrypted_trust_record');
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
          throw const MessageStoreException('malformed_trust_record');
        }
        return ContactTrustRecord.fromJson(value);
      } finally {
        cleartext.fillRange(0, cleartext.length, 0);
      }
    } on MessageStoreException {
      rethrow;
    } on Object {
      throw const MessageStoreException('trust_record_decryption_failed');
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
    throw const MessageStoreException('malformed_encrypted_trust_record');
  }
  try {
    final bytes = base64Decode(value);
    if (base64Encode(bytes) != value ||
        (expectedLength != null && bytes.length != expectedLength)) {
      throw const MessageStoreException('malformed_encrypted_trust_record');
    }
    return bytes;
  } on MessageStoreException {
    rethrow;
  } on Object {
    throw const MessageStoreException('malformed_encrypted_trust_record');
  }
}
