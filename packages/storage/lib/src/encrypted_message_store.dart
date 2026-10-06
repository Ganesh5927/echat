import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' show sha256;
import 'package:cryptography/cryptography.dart';

typedef LocalStorageKeyProvider = Future<SecretKey> Function();

enum MessageDirection { outgoing, incoming }

enum MessageState { queued, submitted, received, failed }

class MessageStoreException implements Exception {
  const MessageStoreException(this.code);

  final String code;

  @override
  String toString() => 'MessageStoreException: $code';
}

class StoredMessage {
  const StoredMessage({
    required this.messageId,
    required this.sessionId,
    required this.peerDeviceId,
    required this.direction,
    required this.state,
    required this.plaintext,
    required this.serializedPacket,
    required this.createdAt,
    required this.expiresAt,
  });

  final String messageId;
  final String sessionId;
  final String peerDeviceId;
  final MessageDirection direction;
  final MessageState state;
  final String plaintext;
  final String serializedPacket;
  final DateTime createdAt;
  final DateTime expiresAt;

  StoredMessage copyWith({MessageState? state}) => StoredMessage(
    messageId: messageId,
    sessionId: sessionId,
    peerDeviceId: peerDeviceId,
    direction: direction,
    state: state ?? this.state,
    plaintext: plaintext,
    serializedPacket: serializedPacket,
    createdAt: createdAt,
    expiresAt: expiresAt,
  );

  Map<String, Object?> toJson() => {
    'messageId': messageId,
    'sessionId': sessionId,
    'peerDeviceId': peerDeviceId,
    'direction': direction.name,
    'state': state.name,
    'plaintext': plaintext,
    'serializedPacket': serializedPacket,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'expiresAt': expiresAt.toUtc().toIso8601String(),
  };

  factory StoredMessage.fromJson(Map<String, dynamic> json) {
    const fields = {
      'messageId',
      'sessionId',
      'peerDeviceId',
      'direction',
      'state',
      'plaintext',
      'serializedPacket',
      'createdAt',
      'expiresAt',
    };
    if (json.length != fields.length ||
        !json.keys.toSet().containsAll(fields)) {
      throw const MessageStoreException('malformed_message_record');
    }
    try {
      final direction = MessageDirection.values.firstWhere(
        (value) => value.name == json['direction'],
      );
      final state = MessageState.values.firstWhere(
        (value) => value.name == json['state'],
      );
      final message = StoredMessage(
        messageId: json['messageId'] as String,
        sessionId: json['sessionId'] as String,
        peerDeviceId: json['peerDeviceId'] as String,
        direction: direction,
        state: state,
        plaintext: json['plaintext'] as String,
        serializedPacket: json['serializedPacket'] as String,
        createdAt: DateTime.parse(json['createdAt'] as String).toUtc(),
        expiresAt: DateTime.parse(json['expiresAt'] as String).toUtc(),
      );
      if (message.messageId.isEmpty ||
          message.sessionId.isEmpty ||
          message.peerDeviceId.isEmpty ||
          message.serializedPacket.isEmpty ||
          (message.direction == MessageDirection.outgoing &&
              message.state == MessageState.received) ||
          (message.direction == MessageDirection.incoming &&
              message.state != MessageState.received)) {
        throw const MessageStoreException('malformed_message_record');
      }
      return message;
    } on MessageStoreException {
      rethrow;
    } on Object {
      throw const MessageStoreException('malformed_message_record');
    }
  }
}

abstract interface class EncryptedRecordBackend {
  Future<Uint8List?> read(String recordId);
  Future<List<Uint8List>> readAll();
  Future<void> write(String recordId, List<int> encryptedRecord);
  Future<void> delete(String recordId);
}

class MemoryEncryptedRecordBackend implements EncryptedRecordBackend {
  final Map<String, Uint8List> _records = {};

  @override
  Future<Uint8List?> read(String recordId) async {
    final bytes = _records[_recordKey(recordId)];
    return bytes == null ? null : Uint8List.fromList(bytes);
  }

  @override
  Future<List<Uint8List>> readAll() async => [
    for (final bytes in _records.values) Uint8List.fromList(bytes),
  ];

  @override
  Future<void> write(String recordId, List<int> encryptedRecord) async {
    _records[_recordKey(recordId)] = Uint8List.fromList(encryptedRecord);
  }

  @override
  Future<void> delete(String recordId) async {
    _records.remove(_recordKey(recordId));
  }
}

class FileEncryptedRecordBackend implements EncryptedRecordBackend {
  FileEncryptedRecordBackend({required Directory directory})
    : _directory = directory;

  final Directory _directory;
  static final Random _random = Random.secure();

  @override
  Future<Uint8List?> read(String recordId) async {
    await _recoverFiles();
    final file = _fileFor(recordId);
    if (!await file.exists()) return null;
    return file.readAsBytes();
  }

  @override
  Future<List<Uint8List>> readAll() async {
    await _recoverFiles();
    if (!await _directory.exists()) return const [];
    final records = <Uint8List>[];
    await for (final entity in _directory.list(followLinks: false)) {
      if (entity is File && entity.path.endsWith('.record')) {
        records.add(await entity.readAsBytes());
      }
    }
    return records;
  }

  @override
  Future<void> write(String recordId, List<int> encryptedRecord) async {
    await _directory.create(recursive: true);
    final target = _fileFor(recordId);
    final temporary = File(
      '${target.path}.tmp-${DateTime.now().microsecondsSinceEpoch}-${_random.nextInt(1 << 32)}',
    );
    final backup = File('${target.path}.bak');
    await temporary.writeAsBytes(encryptedRecord, flush: true);
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
  }

  @override
  Future<void> delete(String recordId) async {
    final target = _fileFor(recordId);
    for (final file in [target, File('${target.path}.bak')]) {
      if (await file.exists()) await file.delete();
    }
  }

  File _fileFor(String recordId) {
    _validateRecordId(recordId);
    final digest = sha256.convert(utf8.encode(recordId));
    return File('${_directory.path}${Platform.pathSeparator}$digest.record');
  }

  Future<void> _recoverFiles() async {
    if (!await _directory.exists()) return;
    await for (final entity in _directory.list(followLinks: false)) {
      if (entity is! File) continue;
      if (entity.path.endsWith('.record.bak')) {
        final target = File(entity.path.substring(0, entity.path.length - 4));
        if (await target.exists()) {
          await entity.delete();
        } else {
          await entity.rename(target.path);
        }
      } else if (entity.path.contains('.record.tmp-')) {
        await entity.delete();
      }
    }
  }
}

class EncryptedMessageStore {
  EncryptedMessageStore({
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
    108,
    111,
    99,
    97,
    108,
    32,
    109,
    101,
    115,
    115,
    97,
    103,
    101,
    115,
    32,
    118,
    49,
  ];

  final EncryptedRecordBackend _backend;
  final LocalStorageKeyProvider _keyProvider;
  final AesGcm _aead = AesGcm.with256bits(nonceLength: 12);
  Future<void> _tail = Future<void>.value();

  Future<void> saveMessage(StoredMessage message) => _serialized(() async {
    _validateMessage(message);
    final existing = await _readMessage(message.messageId);
    if (existing != null) _validateTransition(existing, message);
    await _backend.write(message.messageId, await _encrypt(message));
  });

  Future<StoredMessage?> getMessage(String messageId) =>
      _serialized(() => _readMessage(messageId));

  Future<List<StoredMessage>> listMessages({String? sessionId}) =>
      _serialized(() async {
        final messages = await _readAllMessages();
        final filtered = sessionId == null
            ? messages
            : messages.where((message) => message.sessionId == sessionId);
        return List.unmodifiable(
          filtered.toList()
            ..sort((left, right) => left.createdAt.compareTo(right.createdAt)),
        );
      });

  Future<List<StoredMessage>> listOutbox() => _serialized(() async {
    final messages = await _readAllMessages();
    return List.unmodifiable(
      messages
          .where(
            (message) =>
                message.direction == MessageDirection.outgoing &&
                (message.state == MessageState.queued ||
                    message.state == MessageState.failed),
          )
          .toList()
        ..sort((left, right) => left.createdAt.compareTo(right.createdAt)),
    );
  });

  Future<void> markSubmitted(String messageId) => _serialized(() async {
    final message = await _readMessage(messageId);
    if (message == null) {
      throw const MessageStoreException('message_not_found');
    }
    if (message.direction != MessageDirection.outgoing) {
      throw const MessageStoreException('invalid_message_state');
    }
    if (message.state == MessageState.queued) {
      await _backend.write(
        messageId,
        await _encrypt(message.copyWith(state: MessageState.submitted)),
      );
    }
  });

  Future<void> markFailed(String messageId) => _serialized(() async {
    final message = await _readMessage(messageId);
    if (message == null) {
      throw const MessageStoreException('message_not_found');
    }
    if (message.direction != MessageDirection.outgoing) {
      throw const MessageStoreException('invalid_message_state');
    }
    if (message.state == MessageState.failed) {
      return;
    }
    await _backend.write(
      messageId,
      await _encrypt(message.copyWith(state: MessageState.failed)),
    );
  });

  Future<void> deleteMessage(String messageId) =>
      _serialized(() => _backend.delete(messageId));

  Future<StoredMessage?> _readMessage(String messageId) async {
    _validateRecordId(messageId);
    final bytes = await _backend.read(messageId);
    if (bytes == null) return null;
    final message = await _decrypt(bytes);
    if (message.messageId != messageId) {
      throw const MessageStoreException('message_record_id_mismatch');
    }
    return message;
  }

  Future<List<StoredMessage>> _readAllMessages() async {
    final messages = <StoredMessage>[];
    for (final bytes in await _backend.readAll()) {
      messages.add(await _decrypt(bytes));
    }
    return messages;
  }

  Future<Uint8List> _encrypt(StoredMessage message) async {
    final cleartext = Uint8List.fromList(
      utf8.encode(jsonEncode(message.toJson())),
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
      throw const MessageStoreException('message_encryption_failed');
    } finally {
      cleartext.fillRange(0, cleartext.length, 0);
    }
  }

  Future<StoredMessage> _decrypt(List<int> bytes) async {
    try {
      final outer = jsonDecode(utf8.decode(bytes));
      if (outer is! Map<String, dynamic> ||
          outer.length != 4 ||
          !outer.keys.toSet().containsAll(const {
            'version',
            'nonce',
            'ciphertext',
            'tag',
          }) ||
          outer['version'] != _version) {
        throw const MessageStoreException('malformed_encrypted_record');
      }
      final nonce = _decodeBase64(outer['nonce'], expectedLength: 12);
      final ciphertext = _decodeBase64(outer['ciphertext']);
      final tag = _decodeBase64(outer['tag'], expectedLength: 16);
      final cleartext = await _aead.decrypt(
        SecretBox(ciphertext, nonce: nonce, mac: Mac(tag)),
        secretKey: await _keyProvider(),
        aad: _associatedData,
      );
      try {
        final decoded = jsonDecode(utf8.decode(cleartext));
        if (decoded is! Map<String, dynamic>) {
          throw const MessageStoreException('malformed_message_record');
        }
        return StoredMessage.fromJson(decoded);
      } finally {
        cleartext.fillRange(0, cleartext.length, 0);
      }
    } on MessageStoreException {
      rethrow;
    } on Object {
      throw const MessageStoreException('message_decryption_failed');
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

  static void _validateMessage(StoredMessage message) {
    if (message.messageId.isEmpty ||
        message.messageId.length > 128 ||
        message.sessionId.isEmpty ||
        message.peerDeviceId.isEmpty ||
        message.serializedPacket.isEmpty ||
        (message.direction == MessageDirection.outgoing &&
            message.state == MessageState.received) ||
        (message.direction == MessageDirection.incoming &&
            message.state != MessageState.received)) {
      throw const MessageStoreException('invalid_message_record');
    }
  }

  static void _validateTransition(StoredMessage previous, StoredMessage next) {
    if (previous.sessionId != next.sessionId ||
        previous.peerDeviceId != next.peerDeviceId ||
        previous.direction != next.direction ||
        previous.plaintext != next.plaintext ||
        previous.serializedPacket != next.serializedPacket ||
        previous.createdAt != next.createdAt ||
        previous.expiresAt != next.expiresAt ||
        (previous.state == MessageState.submitted &&
            next.state != MessageState.submitted) ||
        (previous.state == MessageState.received &&
            next.state != MessageState.received) ||
        (previous.state == MessageState.failed && next.state != MessageState.failed)) {
      throw const MessageStoreException('message_id_conflict');
    }
  }
}

List<int> _decodeBase64(Object? value, {int? expectedLength}) {
  if (value is! String) {
    throw const MessageStoreException('malformed_encrypted_record');
  }
  try {
    final decoded = base64Decode(value);
    if (base64Encode(decoded) != value ||
        (expectedLength != null && decoded.length != expectedLength)) {
      throw const MessageStoreException('malformed_encrypted_record');
    }
    return decoded;
  } on MessageStoreException {
    rethrow;
  } on Object {
    throw const MessageStoreException('malformed_encrypted_record');
  }
}

void _validateRecordId(String recordId) {
  if (recordId.isEmpty || recordId.length > 128) {
    throw const MessageStoreException('invalid_record_id');
  }
}

String _recordKey(String recordId) {
  _validateRecordId(recordId);
  return sha256.convert(utf8.encode(recordId)).toString();
}
