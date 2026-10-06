import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:echat_storage/echat_storage.dart';
import 'package:test/test.dart';

void main() {
  late Directory directory;
  late SecretKey key;
  late FileEncryptedRecordBackend backend;
  late EncryptedMessageStore store;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('echat-message-store-');
    key = SecretKey(List<int>.generate(32, (index) => index + 1));
    backend = FileEncryptedRecordBackend(directory: directory);
    store = EncryptedMessageStore(
      backend: backend,
      keyProvider: () async => key,
    );
  });

  tearDown(() async {
    if (await directory.exists()) await directory.delete(recursive: true);
  });

  StoredMessage message({
    String id = '6f7009ac-ec1a-40dc-a978-2f2e2f6d0831',
    MessageDirection direction = MessageDirection.outgoing,
    MessageState state = MessageState.queued,
    String plaintext = 'local-only-sentinel',
    String packet = '{"ciphertext":"opaque"}',
  }) => StoredMessage(
    messageId: id,
    sessionId: 'f62f6b73-b7a4-4090-ad7d-17443e7256c2',
    peerDeviceId: '45ee8c81-f50c-44bc-a36b-d8bdbcc93829',
    direction: direction,
    state: state,
    plaintext: plaintext,
    serializedPacket: packet,
    createdAt: DateTime.utc(2026, 10, 6),
    expiresAt: DateTime.utc(2026, 10, 7),
  );

  test('records persist encrypted and reopen with the same key', () async {
    final record = message();
    await store.saveMessage(record);

    final rawRecords = await backend.readAll();
    expect(rawRecords, hasLength(1));
    expect(utf8.decode(rawRecords.single), isNot(contains(record.plaintext)));
    expect(utf8.decode(rawRecords.single), isNot(contains(record.sessionId)));

    final reopened = EncryptedMessageStore(
      backend: FileEncryptedRecordBackend(directory: directory),
      keyProvider: () async => key,
    );
    expect(
      (await reopened.getMessage(record.messageId))?.toJson(),
      record.toJson(),
    );
  });

  test(
    'outbox includes queued messages and removes acknowledged submissions',
    () async {
      final queued = message();
      final alreadySubmitted = message(
        id: '1edee425-0285-47cf-84a8-c24f7af84b2b',
        state: MessageState.submitted,
      );
      await store.saveMessage(queued);
      await store.saveMessage(alreadySubmitted);

      expect((await store.listOutbox()).map((entry) => entry.messageId), [
        queued.messageId,
      ]);
      await store.markSubmitted(queued.messageId);
      expect(await store.listOutbox(), isEmpty);
      expect(
        (await store.getMessage(queued.messageId))?.state,
        MessageState.submitted,
      );
    },
  );

  test(
    'incoming records are encrypted and cannot be overwritten by conflicting IDs',
    () async {
      final incoming = message(
        direction: MessageDirection.incoming,
        state: MessageState.received,
      );
      await store.saveMessage(incoming);

      await expectLater(
        store.saveMessage(
          message(id: incoming.messageId, plaintext: 'different'),
        ),
        throwsA(isA<MessageStoreException>()),
      );
      expect(
        (await store.getMessage(incoming.messageId))?.toJson(),
        incoming.toJson(),
      );
    },
  );

  test('wrong storage key fails closed', () async {
    final record = message();
    await store.saveMessage(record);
    final wrongKeyStore = EncryptedMessageStore(
      backend: backend,
      keyProvider: () async => SecretKey(List<int>.filled(32, 99)),
    );

    await expectLater(
      wrongKeyStore.getMessage(record.messageId),
      throwsA(isA<MessageStoreException>()),
    );
  });
}
