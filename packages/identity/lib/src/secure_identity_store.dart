import 'dart:async';

abstract class SecureIdentityStore {
  Future<void> savePrivateKey(String privateKeyPem);
  Future<String?> loadPrivateKey();
  Future<void> savePublicIdentity(Map<String, dynamic> publicIdentity);
  Future<Map<String, dynamic>?> loadPublicIdentity();
  Future<void> deleteAll();
  Future<bool> hasIdentity();
}

class MemorySecureIdentityStore implements SecureIdentityStore {
  String? _privateKeyPem;
  Map<String, dynamic>? _publicIdentity;
  bool _throwOnWrite = false;
  bool _throwOnRead = false;

  MemorySecureIdentityStore({
    bool throwOnWrite = false,
    bool throwOnRead = false,
  }) : _throwOnWrite = throwOnWrite,
       _throwOnRead = throwOnRead;

  @override
  Future<void> savePrivateKey(String privateKeyPem) async {
    if (_throwOnWrite) {
      throw SecureStorageException('Secure storage write failed.');
    }
    _privateKeyPem = privateKeyPem;
  }

  @override
  Future<String?> loadPrivateKey() async {
    if (_throwOnRead) {
      throw SecureStorageException('Secure storage read failed.');
    }
    return _privateKeyPem;
  }

  @override
  Future<void> savePublicIdentity(Map<String, dynamic> publicIdentity) async {
    if (_throwOnWrite) {
      throw SecureStorageException('Secure storage write failed.');
    }
    _publicIdentity = Map<String, dynamic>.from(publicIdentity);
  }

  @override
  Future<Map<String, dynamic>?> loadPublicIdentity() async {
    if (_throwOnRead) {
      throw SecureStorageException('Secure storage read failed.');
    }
    return _publicIdentity == null
        ? null
        : Map<String, dynamic>.from(_publicIdentity!);
  }

  @override
  Future<void> deleteAll() async {
    _privateKeyPem = null;
    _publicIdentity = null;
  }

  @override
  Future<bool> hasIdentity() async {
    return _privateKeyPem != null && _publicIdentity != null;
  }
}

class ThrowingSecureIdentityStore implements SecureIdentityStore {
  @override
  Future<void> savePrivateKey(String privateKeyPem) async {
    throw SecureStorageException('Secure storage unavailable.');
  }

  @override
  Future<String?> loadPrivateKey() async {
    throw SecureStorageException('Secure storage unavailable.');
  }

  @override
  Future<void> savePublicIdentity(Map<String, dynamic> publicIdentity) async {
    throw SecureStorageException('Secure storage unavailable.');
  }

  @override
  Future<Map<String, dynamic>?> loadPublicIdentity() async {
    throw SecureStorageException('Secure storage unavailable.');
  }

  @override
  Future<void> deleteAll() async {
    throw SecureStorageException('Secure storage unavailable.');
  }

  @override
  Future<bool> hasIdentity() async {
    throw SecureStorageException('Secure storage unavailable.');
  }
}

class SecureStorageException implements Exception {
  const SecureStorageException(this.message);

  final String message;

  @override
  String toString() => 'SecureStorageException: $message';
}
