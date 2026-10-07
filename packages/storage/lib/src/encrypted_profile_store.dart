import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import 'encrypted_message_store.dart';

class ProfileStoreException implements Exception {
  const ProfileStoreException(this.code);

  final String code;

  @override
  String toString() => 'ProfileStoreException: $code';
}

class StoredProfile {
  StoredProfile({required this.displayName, List<int>? avatarBytes})
    : avatarBytes = avatarBytes == null
          ? null
          : Uint8List.fromList(avatarBytes);

  final String displayName;
  final Uint8List? avatarBytes;
}

class EncryptedProfileStore {
  EncryptedProfileStore({
    required EncryptedRecordBackend backend,
    required LocalStorageKeyProvider keyProvider,
  }) : _backend = backend,
       _keyProvider = keyProvider;

  static const String _recordId = 'local-profile-v1';
  static const int _version = 1;
  static const int maxDisplayNameLength = 64;
  static const int maxAvatarBytes = 512 * 1024;
  static const List<int> _associatedData = [
    101,
    67,
    104,
    97,
    116,
    32,
    108,
    111,
    99,
    97,
    108,
    32,
    112,
    114,
    111,
    102,
    105,
    108,
    101,
    32,
    118,
    49,
  ];

  final EncryptedRecordBackend _backend;
  final LocalStorageKeyProvider _keyProvider;
  final AesGcm _aead = AesGcm.with256bits(nonceLength: 12);
  Future<void> _tail = Future<void>.value();

  Future<StoredProfile?> load() => _serialized(() async {
    final bytes = await _backend.read(_recordId);
    if (bytes == null) return null;
    return _decrypt(bytes);
  });

  Future<void> save(StoredProfile profile) => _serialized(() async {
    _validate(profile);
    await _backend.write(_recordId, await _encrypt(profile));
  });

  Future<void> clear() => _serialized(() => _backend.delete(_recordId));

  void _validate(StoredProfile profile) {
    final name = profile.displayName.trim();
    if (name.isEmpty || name.length > maxDisplayNameLength) {
      throw const ProfileStoreException('invalid_profile_display_name');
    }
    if (profile.avatarBytes case final bytes?
        when bytes.length > maxAvatarBytes) {
      throw const ProfileStoreException('profile_avatar_too_large');
    }
  }

  Future<List<int>> _encrypt(StoredProfile profile) async {
    final cleartext = utf8.encode(
      jsonEncode({
        'displayName': profile.displayName.trim(),
        'avatar': profile.avatarBytes == null
            ? null
            : base64Encode(profile.avatarBytes!),
      }),
    );
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
      throw const ProfileStoreException('profile_encryption_failed');
    } finally {
      cleartext.fillRange(0, cleartext.length, 0);
    }
  }

  Future<StoredProfile> _decrypt(List<int> bytes) async {
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
        throw const ProfileStoreException('malformed_encrypted_profile');
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
        if (value is! Map<String, dynamic> ||
            value.length != 2 ||
            value['displayName'] is! String ||
            (value['avatar'] != null && value['avatar'] is! String)) {
          throw const ProfileStoreException('malformed_profile_record');
        }
        final avatar = value['avatar'] == null
            ? null
            : _decodeBase64(value['avatar']);
        final profile = StoredProfile(
          displayName: value['displayName'] as String,
          avatarBytes: avatar,
        );
        _validate(profile);
        return profile;
      } finally {
        cleartext.fillRange(0, cleartext.length, 0);
      }
    } on ProfileStoreException {
      rethrow;
    } on Object {
      throw const ProfileStoreException('profile_decryption_failed');
    }
  }

  List<int> _decodeBase64(Object? value, [int? expectedLength]) {
    if (value is! String) {
      throw const ProfileStoreException('malformed_encrypted_profile');
    }
    try {
      final bytes = base64Decode(value);
      if (base64Encode(bytes) != value ||
          (expectedLength != null && bytes.length != expectedLength)) {
        throw const ProfileStoreException('malformed_encrypted_profile');
      }
      return bytes;
    } on ProfileStoreException {
      rethrow;
    } on Object {
      throw const ProfileStoreException('malformed_encrypted_profile');
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
