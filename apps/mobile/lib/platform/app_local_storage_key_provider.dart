import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';

import 'secure_value_store.dart';

class AppLocalStorageKeyProvider {
  AppLocalStorageKeyProvider({required this._store});

  static const String storageKeyName = 'echat.local_storage_key.v1';
  final SecureValueStore _store;
  Future<SecretKey>? _keyFuture;

  Future<SecretKey> call() => _keyFuture ??= _loadOrCreate();

  Future<SecretKey> _loadOrCreate() async {
    final encoded = await _store.read(storageKeyName);
    if (encoded != null) {
      try {
        final bytes = base64Decode(encoded);
        if (base64Encode(bytes) != encoded || bytes.length != 32) {
          throw const FormatException('Invalid local key encoding.');
        }
        return SecretKey(bytes);
      } on Object {
        throw StateError('Local storage key is damaged.');
      }
    }

    final bytes = List<int>.generate(32, (_) => Random.secure().nextInt(256));
    final newKey = base64Encode(bytes);
    await _store.write(storageKeyName, newKey);
    return SecretKey(bytes);
  }
}
