import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:echat_identity/echat_identity.dart';
import 'package:echat_storage/echat_storage.dart';
import 'package:test/test.dart';

void main() {
  late Directory directory;
  late SecretKey key;
  late FileEncryptedRecordBackend backend;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('echat-contact-trust-');
    key = SecretKey(List<int>.generate(32, (index) => 255 - index));
    backend = FileEncryptedRecordBackend(directory: directory);
  });

  tearDown(() async {
    if (await directory.exists()) await directory.delete(recursive: true);
  });

  EncryptedContactTrustStore store() => EncryptedContactTrustStore(
    backend: backend,
    keyProvider: () async => key,
  );

  test(
    'verified and revoked trust survive encrypted store reconstruction',
    () async {
      final identityService = IdentityService(
        store: MemorySecureIdentityStore(),
      );
      final identity = await identityService.createIdentity();
      final trust = ContactTrustService(store: store());
      await trust.verifyContact(identityService.createQrPayload(identity));

      final raw = utf8.decode((await backend.readAll()).single);
      expect(raw, isNot(contains(identity.deviceId)));
      expect(raw, isNot(contains(identity.publicKeyPem)));
      expect(raw, isNot(contains(identity.fingerprint)));

      final reopened = ContactTrustService(
        store: EncryptedContactTrustStore(
          backend: FileEncryptedRecordBackend(directory: directory),
          keyProvider: () async => key,
        ),
      );
      expect(
        (await reopened.requireVerified(identity.deviceId)).fingerprint,
        identity.fingerprint,
      );
      await reopened.revokeContact(identity.deviceId);

      final afterRevocation = ContactTrustService(
        store: EncryptedContactTrustStore(
          backend: FileEncryptedRecordBackend(directory: directory),
          keyProvider: () async => key,
        ),
      );
      expect(
        (await afterRevocation.getContact(identity.deviceId))?.state,
        ContactTrustState.revoked,
      );
    },
  );

  test(
    'trust records fail closed when opened with a different local key',
    () async {
      final identityService = IdentityService(
        store: MemorySecureIdentityStore(),
      );
      final identity = await identityService.createIdentity();
      await ContactTrustService(
        store: store(),
      ).verifyContact(identityService.createQrPayload(identity));
      final wrongKeyStore = EncryptedContactTrustStore(
        backend: backend,
        keyProvider: () async => SecretKey(List<int>.filled(32, 3)),
      );

      await expectLater(
        ContactTrustService(store: wrongKeyStore).getContact(identity.deviceId),
        throwsA(isA<MessageStoreException>()),
      );
    },
  );
}
