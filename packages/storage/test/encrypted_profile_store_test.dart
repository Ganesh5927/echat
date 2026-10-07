import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:echat_storage/echat_storage.dart';
import 'package:test/test.dart';

void main() {
  late MemoryEncryptedRecordBackend backend;
  late SecretKey key;

  setUp(() {
    backend = MemoryEncryptedRecordBackend();
    key = SecretKey(List<int>.generate(32, (index) => index + 1));
  });

  EncryptedProfileStore store() =>
      EncryptedProfileStore(backend: backend, keyProvider: () async => key);

  test(
    'profile name and avatar survive encrypted store reconstruction',
    () async {
      const name = 'Local Display Name';
      final avatar = List<int>.generate(128, (index) => index);
      await store().save(StoredProfile(displayName: name, avatarBytes: avatar));

      final persisted = utf8.decode((await backend.readAll()).single);
      expect(persisted, isNot(contains(name)));
      expect(persisted, isNot(contains(base64Encode(avatar))));

      final loaded = await store().load();
      expect(loaded?.displayName, name);
      expect(loaded?.avatarBytes, avatar);
    },
  );

  test('profile data rejects invalid names and oversized avatars', () async {
    await expectLater(
      store().save(StoredProfile(displayName: '  ')),
      throwsA(
        isA<ProfileStoreException>().having(
          (error) => error.code,
          'code',
          'invalid_profile_display_name',
        ),
      ),
    );
    await expectLater(
      store().save(
        StoredProfile(
          displayName: 'Name',
          avatarBytes: List<int>.filled(
            EncryptedProfileStore.maxAvatarBytes + 1,
            0,
          ),
        ),
      ),
      throwsA(isA<ProfileStoreException>()),
    );
  });

  test('profile can be cleared without touching unrelated records', () async {
    await backend.write('unrelated', [1, 2, 3]);
    await store().save(StoredProfile(displayName: 'Name'));
    await store().clear();

    expect(await store().load(), isNull);
    expect(await backend.read('unrelated'), [1, 2, 3]);
  });
}
