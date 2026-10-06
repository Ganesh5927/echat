import 'dart:async';

import 'session_service.dart';
import 'public_identity_qr.dart';

enum ContactTrustState { unverified, verified, identityChanged, revoked }

class ContactTrustException implements Exception {
  const ContactTrustException(this.code);

  final String code;

  @override
  String toString() => 'ContactTrustException: $code';
}

class ContactTrustRecord {
  const ContactTrustRecord({
    required this.deviceId,
    required this.publicKeyPem,
    required this.fingerprint,
    required this.state,
    required this.createdAt,
    required this.updatedAt,
    this.candidatePublicKeyPem,
    this.candidateFingerprint,
  });

  final String deviceId;
  final String publicKeyPem;
  final String fingerprint;
  final ContactTrustState state;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? candidatePublicKeyPem;
  final String? candidateFingerprint;

  Map<String, Object?> toJson() => {
    'deviceId': deviceId,
    'publicKeyPem': publicKeyPem,
    'fingerprint': fingerprint,
    'state': state.name,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'updatedAt': updatedAt.toUtc().toIso8601String(),
    'candidatePublicKeyPem': candidatePublicKeyPem,
    'candidateFingerprint': candidateFingerprint,
  };

  factory ContactTrustRecord.fromJson(Map<String, dynamic> json) {
    const fields = {
      'deviceId',
      'publicKeyPem',
      'fingerprint',
      'state',
      'createdAt',
      'updatedAt',
      'candidatePublicKeyPem',
      'candidateFingerprint',
    };
    if (json.length != fields.length ||
        !json.keys.toSet().containsAll(fields)) {
      throw const ContactTrustException('malformed_trust_record');
    }
    try {
      final record = ContactTrustRecord(
        deviceId: json['deviceId'] as String,
        publicKeyPem: json['publicKeyPem'] as String,
        fingerprint: json['fingerprint'] as String,
        state: ContactTrustState.values.firstWhere(
          (state) => state.name == json['state'],
        ),
        createdAt: DateTime.parse(json['createdAt'] as String).toUtc(),
        updatedAt: DateTime.parse(json['updatedAt'] as String).toUtc(),
        candidatePublicKeyPem: json['candidatePublicKeyPem'] as String?,
        candidateFingerprint: json['candidateFingerprint'] as String?,
      );
      PublicIdentityQrPayload(
        version: PublicIdentityQrPayload.currentVersion,
        deviceId: record.deviceId,
        publicKeyPem: record.publicKeyPem,
        fingerprint: record.fingerprint,
        createdAt: record.createdAt,
      ).validate();
      final hasCandidatePem = record.candidatePublicKeyPem != null;
      final hasCandidateFingerprint = record.candidateFingerprint != null;
      if (record.deviceId.isEmpty ||
          (record.state == ContactTrustState.identityChanged) !=
              (hasCandidatePem && hasCandidateFingerprint) ||
          hasCandidatePem != hasCandidateFingerprint) {
        throw const ContactTrustException('malformed_trust_record');
      }
      if (hasCandidatePem) {
        PublicIdentityQrPayload(
          version: PublicIdentityQrPayload.currentVersion,
          deviceId: record.deviceId,
          publicKeyPem: record.candidatePublicKeyPem!,
          fingerprint: record.candidateFingerprint!,
          createdAt: record.updatedAt,
        ).validate();
        if (record.candidateFingerprint == record.fingerprint) {
          throw const ContactTrustException('malformed_trust_record');
        }
      }
      return record;
    } on ContactTrustException {
      rethrow;
    } on Object {
      throw const ContactTrustException('malformed_trust_record');
    }
  }
}

abstract interface class ContactTrustStore {
  Future<ContactTrustRecord?> loadContact(String deviceId);
  Future<List<ContactTrustRecord>> loadContacts();
  Future<void> saveContact(ContactTrustRecord contact);
}

class MemoryContactTrustStore implements ContactTrustStore {
  final Map<String, ContactTrustRecord> _contacts = {};

  @override
  Future<ContactTrustRecord?> loadContact(String deviceId) async =>
      _contacts[deviceId];

  @override
  Future<List<ContactTrustRecord>> loadContacts() async =>
      List.unmodifiable(_contacts.values);

  @override
  Future<void> saveContact(ContactTrustRecord contact) async {
    _contacts[contact.deviceId] = contact;
  }
}

class ContactTrustService {
  ContactTrustService({
    required ContactTrustStore store,
    DateTime Function()? clock,
  }) : _store = store,
       _clock = clock ?? DateTime.now;

  final ContactTrustStore _store;
  final DateTime Function() _clock;
  final Map<String, Future<void>> _deviceLocks = {};

  Future<ContactTrustRecord?> getContact(String deviceId) =>
      _store.loadContact(deviceId);

  Future<List<ContactTrustRecord>> listContacts() async {
    final contacts = await _store.loadContacts();
    return List.unmodifiable(
      contacts.toList()
        ..sort((left, right) => left.deviceId.compareTo(right.deviceId)),
    );
  }

  Future<ContactTrustRecord> observeQr(String qrString) =>
      observeIdentity(PublicIdentityQrPayload.fromQrString(qrString));

  Future<ContactTrustRecord> observeIdentity(PublicIdentityQrPayload identity) {
    identity.validate();
    return _withDeviceLock(identity.deviceId, () => _observeIdentity(identity));
  }

  Future<ContactTrustRecord> _observeIdentity(
    PublicIdentityQrPayload identity,
  ) async {
    final current = await _store.loadContact(identity.deviceId);
    final now = _clock().toUtc();
    if (current == null) {
      final observed = ContactTrustRecord(
        deviceId: identity.deviceId,
        publicKeyPem: identity.publicKeyPem,
        fingerprint: identity.fingerprint,
        state: ContactTrustState.unverified,
        createdAt: now,
        updatedAt: now,
      );
      await _store.saveContact(observed);
      return observed;
    }
    if (current.state == ContactTrustState.revoked) return current;
    if (_sameIdentity(current.publicKeyPem, current.fingerprint, identity)) {
      return current;
    }
    if (current.state == ContactTrustState.identityChanged &&
        current.candidatePublicKeyPem == identity.publicKeyPem &&
        current.candidateFingerprint == identity.fingerprint) {
      return current;
    }
    final changed = ContactTrustRecord(
      deviceId: current.deviceId,
      publicKeyPem: current.publicKeyPem,
      fingerprint: current.fingerprint,
      state: ContactTrustState.identityChanged,
      createdAt: current.createdAt,
      updatedAt: now,
      candidatePublicKeyPem: identity.publicKeyPem,
      candidateFingerprint: identity.fingerprint,
    );
    await _store.saveContact(changed);
    return changed;
  }

  Future<ContactTrustRecord> verifyContact(PublicIdentityQrPayload identity) {
    identity.validate();
    return _withDeviceLock(identity.deviceId, () async {
      final current = await _store.loadContact(identity.deviceId);
      final now = _clock().toUtc();
      if (current == null) {
        final verified = _recordFor(
          identity,
          state: ContactTrustState.verified,
          now: now,
        );
        await _store.saveContact(verified);
        return verified;
      }
      if (current.state == ContactTrustState.revoked) {
        throw const ContactTrustException('device_revoked');
      }
      if (current.state == ContactTrustState.identityChanged) {
        throw const ContactTrustException('explicit_reverification_required');
      }
      if (!_sameIdentity(current.publicKeyPem, current.fingerprint, identity)) {
        await _observeIdentity(identity);
        throw const ContactTrustException('identity_change_detected');
      }
      final verified = ContactTrustRecord(
        deviceId: current.deviceId,
        publicKeyPem: current.publicKeyPem,
        fingerprint: current.fingerprint,
        state: ContactTrustState.verified,
        createdAt: current.createdAt,
        updatedAt: now,
      );
      await _store.saveContact(verified);
      return verified;
    });
  }

  Future<ContactTrustRecord> reverifyChangedIdentity(
    PublicIdentityQrPayload identity,
  ) {
    identity.validate();
    return _withDeviceLock(identity.deviceId, () async {
      final current = await _store.loadContact(identity.deviceId);
      if (current == null ||
          current.state != ContactTrustState.identityChanged) {
        throw const ContactTrustException('no_identity_change_pending');
      }
      if (current.candidatePublicKeyPem != identity.publicKeyPem ||
          current.candidateFingerprint != identity.fingerprint) {
        throw const ContactTrustException('candidate_identity_mismatch');
      }
      final verified = _recordFor(
        identity,
        state: ContactTrustState.verified,
        now: _clock().toUtc(),
        createdAt: current.createdAt,
      );
      await _store.saveContact(verified);
      return verified;
    });
  }

  Future<ContactTrustRecord> revokeContact(String deviceId) =>
      _withDeviceLock(deviceId, () async {
        final current = await _store.loadContact(deviceId);
        if (current == null) {
          throw const ContactTrustException('contact_not_found');
        }
        if (current.state == ContactTrustState.revoked) return current;
        final revoked = ContactTrustRecord(
          deviceId: current.deviceId,
          publicKeyPem: current.publicKeyPem,
          fingerprint: current.fingerprint,
          state: ContactTrustState.revoked,
          createdAt: current.createdAt,
          updatedAt: _clock().toUtc(),
        );
        await _store.saveContact(revoked);
        return revoked;
      });

  Future<ContactTrustRecord> requireVerified(String deviceId) async {
    final contact = await _store.loadContact(deviceId);
    if (contact == null || contact.state != ContactTrustState.verified) {
      throw ContactTrustException(
        contact?.state == ContactTrustState.revoked
            ? 'device_revoked'
            : contact?.state == ContactTrustState.identityChanged
            ? 'identity_change_requires_reverification'
            : 'device_not_verified',
      );
    }
    return contact;
  }

  Future<ContactTrustRecord> requireTrustedSession(
    SessionRecord session,
    String expectedPeerDeviceId,
  ) async {
    if (!session.isEstablished ||
        session.remoteDeviceId != expectedPeerDeviceId) {
      throw const ContactTrustException('session_peer_mismatch');
    }
    final contact = await requireVerified(expectedPeerDeviceId);
    if (contact.publicKeyPem != session.remoteIdentityPublicKeyPem) {
      throw const ContactTrustException('session_identity_key_mismatch');
    }
    return contact;
  }

  Future<T> withTrustedSession<T>(
    SessionRecord session,
    String expectedPeerDeviceId,
    Future<T> Function() action,
  ) => _withDeviceLock(expectedPeerDeviceId, () async {
    await requireTrustedSession(session, expectedPeerDeviceId);
    return action();
  });

  ContactTrustRecord _recordFor(
    PublicIdentityQrPayload identity, {
    required ContactTrustState state,
    required DateTime now,
    DateTime? createdAt,
  }) => ContactTrustRecord(
    deviceId: identity.deviceId,
    publicKeyPem: identity.publicKeyPem,
    fingerprint: identity.fingerprint,
    state: state,
    createdAt: createdAt ?? now,
    updatedAt: now,
  );

  bool _sameIdentity(
    String publicKeyPem,
    String fingerprint,
    PublicIdentityQrPayload identity,
  ) =>
      publicKeyPem == identity.publicKeyPem &&
      fingerprint == identity.fingerprint;

  Future<T> _withDeviceLock<T>(String deviceId, Future<T> Function() action) {
    final previous = _deviceLocks[deviceId] ?? Future<void>.value();
    final release = Completer<void>();
    _deviceLocks[deviceId] = release.future;
    return () async {
      await previous;
      try {
        return await action();
      } finally {
        release.complete();
        if (identical(_deviceLocks[deviceId], release.future)) {
          _deviceLocks.remove(deviceId);
        }
      }
    }();
  }
}
