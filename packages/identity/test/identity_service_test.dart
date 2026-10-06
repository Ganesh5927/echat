import 'package:echat_identity/echat_identity.dart';
import 'package:test/test.dart';

void main() {
  group('IdentityService', () {
    test(
      'generates a device identity with public key material and fingerprint',
      () async {
        final service = IdentityService(store: MemorySecureIdentityStore());

        final identity = await service.createIdentity();

        expect(identity.deviceId, isNotEmpty);
        expect(
          identity.publicKeyPem,
          contains('BEGIN ECHAT DEVICE PUBLIC KEY'),
        );
        expect(identity.fingerprint, isNotEmpty);
        expect(identity.fingerprint.length, greaterThan(20));
        expect(identity.publicKeyPem, isNot(contains('PRIVATE KEY')));
      },
    );

    test(
      'creates a public identity representation from the stored device identity',
      () async {
        final service = IdentityService(store: MemorySecureIdentityStore());
        final identity = await service.createIdentity();

        final publicIdentity = await service.getPublicIdentity();

        expect(publicIdentity.deviceId, equals(identity.deviceId));
        expect(publicIdentity.publicKeyPem, equals(identity.publicKeyPem));
        expect(publicIdentity.fingerprint, equals(identity.fingerprint));
      },
    );

    test('persists and reloads the same identity', () async {
      final store = MemorySecureIdentityStore();
      final service = IdentityService(store: store);
      final created = await service.createIdentity();

      final reloaded = await IdentityService(store: store).loadIdentity();

      expect(reloaded, isNotNull);
      expect(reloaded!.deviceId, equals(created.deviceId));
      expect(reloaded.fingerprint, equals(created.fingerprint));
    });

    test('keeps the fingerprint consistent after reload', () async {
      final store = MemorySecureIdentityStore();
      final service = IdentityService(store: store);
      final created = await service.createIdentity();

      final loaded = await service.loadIdentity();

      expect(loaded!.fingerprint, equals(created.fingerprint));
      expect(loaded.publicKeyPem, equals(created.publicKeyPem));
    });

    test('deletes the stored identity cleanly', () async {
      final service = IdentityService(store: MemorySecureIdentityStore());
      await service.createIdentity();

      await service.deleteIdentity();
      final exists = await service.hasIdentity();

      expect(exists, isFalse);
      expect(await service.loadIdentity(), isNull);
    });

    test(
      'rotates to a new identity without silently reusing the old one',
      () async {
        final service = IdentityService(store: MemorySecureIdentityStore());
        final original = await service.createIdentity();

        final rotated = await service.rotateIdentity();

        expect(rotated.deviceId, isNot(equals(original.deviceId)));
        expect(rotated.fingerprint, isNot(equals(original.fingerprint)));
        expect(await service.loadIdentity(), isNotNull);
      },
    );

    test(
      'keeps the private key out of the public identity representation',
      () async {
        final service = IdentityService(store: MemorySecureIdentityStore());
        final identity = await service.createIdentity();

        expect(
          identity.publicKeyPem,
          isNot(contains('BEGIN ECHAT DEVICE PRIVATE KEY')),
        );
        expect(identity.publicKeyPem, isNot(contains('privateKey')));
      },
    );

    test('keeps the private key out of the QR payload', () async {
      final service = IdentityService(store: MemorySecureIdentityStore());
      final identity = await service.createIdentity();

      final payload = service.createQrPayload(identity).toQrString();

      expect(payload, contains('publicKeyPem'));
      expect(payload, isNot(contains('privateKey')));
      expect(payload, isNot(contains('BEGIN ECHAT DEVICE PRIVATE KEY')));
    });

    test('fails closed on corrupted identity storage', () async {
      final store = MemorySecureIdentityStore();
      await store.savePrivateKey('not-a-real-key');
      await store.savePublicIdentity({
        'deviceId': 'bad-device',
        'publicKeyPem': 'bad-value',
        'fingerprint': 'bad-fingerprint',
        'createdAt': DateTime.now().toUtc().toIso8601String(),
        'status': 'created',
      });

      final service = IdentityService(store: store);

      expect(
        () => service.loadIdentity(),
        throwsA(isA<SecureStorageException>()),
      );
    });

    test(
      'reports secure storage failure at the storage boundary',
      () async {
        final store = ThrowingSecureIdentityStore();

        try {
          await store.loadPublicIdentity();
          fail('Expected SecureStorageException to be thrown.');
        } on SecureStorageException {
          expect(true, isTrue);
        }
      },
    );

    test(
      'repeated initialization returns the same identity and does not duplicate keys',
      () async {
        final service = IdentityService(store: MemorySecureIdentityStore());
        final first = await service.createIdentity();

        final second = await service.createIdentity();

        expect(second.deviceId, equals(first.deviceId));
        expect(second.fingerprint, equals(first.fingerprint));
      },
    );

    test(
      'concurrent initialization yields a single identity instance',
      () async {
        final service = IdentityService(store: MemorySecureIdentityStore());

        final results = await Future.wait([
          service.createIdentity(),
          service.createIdentity(),
          service.createIdentity(),
        ]);

        expect(
          results.map((identity) => identity.deviceId).toSet().length,
          equals(1),
        );
      },
    );

    test(
      'application restart simulation loads the same identity from storage',
      () async {
        final store = MemorySecureIdentityStore();
        final firstService = IdentityService(store: store);
        final original = await firstService.createIdentity();

        final restartedService = IdentityService(store: store);
        final reloaded = await restartedService.loadIdentity();

        expect(reloaded, isNotNull);
        expect(reloaded!.deviceId, equals(original.deviceId));
        expect(reloaded.fingerprint, equals(original.fingerprint));
      },
    );
  });
}
