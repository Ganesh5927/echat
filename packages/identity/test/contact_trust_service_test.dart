import 'package:echat_identity/echat_identity.dart';
import 'package:test/test.dart';

Future<PublicIdentityQrPayload> _newIdentity() async {
  final service = IdentityService(store: MemorySecureIdentityStore());
  final identity = await service.createIdentity();
  return service.createQrPayload(identity);
}

PublicIdentityQrPayload _withDeviceId(
  PublicIdentityQrPayload identity,
  String deviceId,
) => PublicIdentityQrPayload(
  version: identity.version,
  deviceId: deviceId,
  publicKeyPem: identity.publicKeyPem,
  fingerprint: identity.fingerprint,
  createdAt: identity.createdAt,
);

void main() {
  test('QR payload exposes only validated public identity fields', () async {
    final identity = await _newIdentity();
    final qr = identity.toQrString();
    final decoded = PublicIdentityQrPayload.fromQrString(qr);

    expect(decoded.fingerprint, identity.fingerprint);
    expect(decoded.deviceId, identity.deviceId);
    expect(identity.toJson().keys.toSet(), {
      'version',
      'deviceId',
      'publicKeyPem',
      'fingerprint',
      'createdAt',
    });
    expect(qr, isNot(contains('PRIVATE KEY')));
    expect(qr, isNot(contains('privateKey')));
  });

  test(
    'QR parser rejects extra fields and mismatched public-key fingerprints',
    () async {
      final identity = await _newIdentity();
      expect(
        () => PublicIdentityQrPayload.fromJson({
          ...identity.toJson(),
          'privateKeyPem': 'not allowed',
        }),
        throwsA(isA<PublicIdentityFormatException>()),
      );
      expect(
        () => PublicIdentityQrPayload.fromJson({
          ...identity.toJson(),
          'fingerprint': '0' * 64,
        }),
        throwsA(isA<PublicIdentityFormatException>()),
      );
    },
  );

  test(
    'observed contact remains unverified until explicitly confirmed',
    () async {
      final identity = await _newIdentity();
      final trust = ContactTrustService(store: MemoryContactTrustStore());

      final observed = await trust.observeQr(identity.toQrString());
      expect(observed.state, ContactTrustState.unverified);
      await expectLater(
        trust.requireVerified(identity.deviceId),
        throwsA(
          isA<ContactTrustException>().having(
            (error) => error.code,
            'code',
            'device_not_verified',
          ),
        ),
      );

      final verified = await trust.verifyContact(identity);
      expect(verified.state, ContactTrustState.verified);
      expect(
        (await trust.requireVerified(identity.deviceId)).fingerprint,
        identity.fingerprint,
      );
    },
  );

  test('trust records reject partial key-change candidates', () async {
    final identity = await _newIdentity();
    final trust = ContactTrustService(store: MemoryContactTrustStore());
    final record = await trust.verifyContact(identity);
    final json = record.toJson()
      ..['state'] = ContactTrustState.identityChanged.name
      ..['candidatePublicKeyPem'] = identity.publicKeyPem;

    expect(
      () => ContactTrustRecord.fromJson(json),
      throwsA(isA<ContactTrustException>()),
    );
  });

  test(
    'local display name survives identity changes without changing trust',
    () async {
      final original = await _newIdentity();
      final replacement = await _newIdentity();
      final changed = _withDeviceId(replacement, original.deviceId);
      final trust = ContactTrustService(store: MemoryContactTrustStore());
      await trust.verifyContact(original);

      final named = await trust.updateDisplayName(
        original.deviceId,
        '  Alex  ',
      );
      expect(named.displayName, 'Alex');
      expect(named.fingerprint, original.fingerprint);
      expect(named.state, ContactTrustState.verified);

      final changedRecord = await trust.observeIdentity(changed);
      expect(changedRecord.displayName, 'Alex');
      expect(changedRecord.state, ContactTrustState.identityChanged);

      final reverified = await trust.reverifyChangedIdentity(changed);
      expect(reverified.displayName, 'Alex');
      expect(reverified.state, ContactTrustState.verified);
      expect(reverified.fingerprint, changed.fingerprint);

      final revoked = await trust.revokeContact(original.deviceId);
      expect(revoked.displayName, 'Alex');
      expect(revoked.state, ContactTrustState.revoked);

      final restored = ContactTrustRecord.fromJson(
        revoked.toJson()..remove('displayName'),
      );
      expect(restored.displayName, isNull);
    },
  );

  test(
    'unexpected key change blocks trust until candidate is explicitly reverified',
    () async {
      final original = await _newIdentity();
      final replacement = await _newIdentity();
      final changed = _withDeviceId(replacement, original.deviceId);
      final trust = ContactTrustService(store: MemoryContactTrustStore());
      await trust.verifyContact(original);

      final observed = await trust.observeIdentity(changed);
      expect(observed.state, ContactTrustState.identityChanged);
      expect(observed.fingerprint, original.fingerprint);
      expect(observed.candidateFingerprint, changed.fingerprint);
      await expectLater(
        trust.requireVerified(original.deviceId),
        throwsA(isA<ContactTrustException>()),
      );
      await expectLater(
        trust.verifyContact(changed),
        throwsA(isA<ContactTrustException>()),
      );

      final reverified = await trust.reverifyChangedIdentity(changed);
      expect(reverified.state, ContactTrustState.verified);
      expect(reverified.fingerprint, changed.fingerprint);
      expect(reverified.candidateFingerprint, isNull);
    },
  );

  test(
    'revocation is a persistent tombstone and cannot be cleared by rescanning',
    () async {
      final identity = await _newIdentity();
      final replacement = await _newIdentity();
      final changed = _withDeviceId(replacement, identity.deviceId);
      final trust = ContactTrustService(store: MemoryContactTrustStore());
      await trust.verifyContact(identity);

      final revoked = await trust.revokeContact(identity.deviceId);
      expect(revoked.state, ContactTrustState.revoked);
      expect(
        (await trust.observeIdentity(identity)).state,
        ContactTrustState.revoked,
      );
      expect(
        (await trust.observeIdentity(changed)).state,
        ContactTrustState.revoked,
      );
      await expectLater(
        trust.requireVerified(identity.deviceId),
        throwsA(
          isA<ContactTrustException>().having(
            (error) => error.code,
            'code',
            'device_revoked',
          ),
        ),
      );
      await expectLater(
        trust.verifyContact(identity),
        throwsA(isA<ContactTrustException>()),
      );
    },
  );

  test(
    'session trust requires an established session pinned to the verified key',
    () async {
      final identity = await _newIdentity();
      final trust = ContactTrustService(store: MemoryContactTrustStore());
      await trust.verifyContact(identity);
      final session = SessionRecord(
        sessionId: '1278392e-1d6b-42dd-bd6f-cf66b88ddf8f',
        localDeviceId: 'ac15269c-177e-46d1-a01a-7527f5eab87a',
        remoteDeviceId: identity.deviceId,
        localIdentityPublicKeyPem: 'local-public-key',
        remoteIdentityPublicKeyPem: identity.publicKeyPem,
        sessionStatus: SessionState.established,
        createdAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026),
        sendSequence: 0,
        receiveSequence: 0,
      );

      expect(
        (await trust.requireTrustedSession(session, identity.deviceId)).state,
        ContactTrustState.verified,
      );
      await expectLater(
        trust.requireTrustedSession(
          session.copyWith(remoteIdentityPublicKeyPem: 'changed-key'),
          identity.deviceId,
        ),
        throwsA(isA<ContactTrustException>()),
      );
    },
  );
}
