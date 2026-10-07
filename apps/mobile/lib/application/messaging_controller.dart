import 'dart:convert';

import 'package:echat_identity/echat_identity.dart';
import 'package:echat_messaging/echat_messaging.dart';
import 'package:echat_protocol/echat_protocol.dart';
import 'package:echat_storage/echat_storage.dart';
import 'package:echat_transport/echat_transport.dart';

import '../platform/app_secure_stores.dart';
import '../platform/unavailable_packet_transport.dart';
import 'messaging_models.dart';
import 'session_exchange_gateway.dart';

class AppMessagingException implements Exception {
  const AppMessagingException(this.code);

  final String code;

  @override
  String toString() => 'AppMessagingException: $code';
}

class MessagingController {
  MessagingController({
    required this._identityService,
    required this._sessionService,
    required this._sessionStore,
    required this._contactTrustService,
    required this._messageStore,
    required this._packetTransport,
    required this._sessionExchangeGateway,
  });

  final IdentityService _identityService;
  final SessionService _sessionService;
  final AppSecureSessionStore _sessionStore;
  final ContactTrustService _contactTrustService;
  final EncryptedMessageStore _messageStore;
  final PacketTransport _packetTransport;
  final SessionExchangeGateway _sessionExchangeGateway;
  final Map<String, AppSessionStatus> _sessionOverrides = {};
  final Map<String, String> _pendingSessionExchanges = {};
  MessagingService? _messagingService;
  String? _localDeviceId;

  bool get hasActiveIdentity => _localDeviceId != null;

  AppConnectionStatus get connectionStatus {
    if (_packetTransport is UnavailablePacketTransport) {
      return AppConnectionStatus.notConfigured;
    }
    return switch (_packetTransport.connectionState) {
      TransportConnectionState.disconnected => AppConnectionStatus.disconnected,
      TransportConnectionState.connecting => AppConnectionStatus.connecting,
      TransportConnectionState.connected => AppConnectionStatus.connected,
    };
  }

  bool get sessionExchangeAvailable => _sessionExchangeGateway.isConfigured;

  Future<LocalIdentityView?> loadLocalIdentity() async {
    await _sessionStore.migrateLegacySessionRecords();
    final identity = await _identityService.loadIdentity();
    if (identity == null) {
      _localDeviceId = null;
      _messagingService = null;
      return null;
    }
    await activateIdentity(identity);
    return _identityView(identity);
  }

  Future<LocalIdentityView> createLocalIdentity() async {
    final identity = await _identityService.createIdentity();
    await activateIdentity(identity);
    return _identityView(identity);
  }

  Future<void> deleteLocalIdentity() async {
    await _identityService.deleteIdentity();
    _localDeviceId = null;
    _messagingService = null;
  }

  Future<void> activateIdentity(DeviceIdentity identity) async {
    final storedIdentity = await _identityService.loadIdentity();
    if (storedIdentity == null ||
        storedIdentity.deviceId != identity.deviceId) {
      throw const AppMessagingException('local_identity_unavailable');
    }
    _localDeviceId = storedIdentity.deviceId;
    _messagingService = MessagingService(
      protocol: MessageService(
        sessionService: _sessionService,
        localDeviceId: storedIdentity.deviceId,
      ),
      transport: _packetTransport,
      store: _messageStore,
      contactTrust: _contactTrustService,
      localDeviceId: storedIdentity.deviceId,
    );
  }

  Future<List<AppContact>> contacts() async {
    final records = await _contactTrustService.listContacts();
    return List.unmodifiable(records.map(_contactView));
  }

  Future<AppContact?> contact(String deviceId) async {
    final record = await _contactTrustService.getContact(deviceId);
    return record == null ? null : _contactView(record);
  }

  Future<AppContact> observeContactQr(String qrJson) async =>
      _contactView(await _contactTrustService.observeQr(qrJson));

  Future<AppContact> verifyContactFingerprint({
    required String deviceId,
    required String independentlyComparedFingerprint,
  }) async {
    final record = await _contactTrustService.getContact(deviceId);
    if (record == null) {
      throw const AppMessagingException('contact_not_found');
    }
    if (record.state == ContactTrustState.revoked) {
      throw const AppMessagingException('device_revoked');
    }
    if (record.state == ContactTrustState.identityChanged) {
      throw const AppMessagingException('explicit_reverification_required');
    }
    if (_normalizeFingerprint(independentlyComparedFingerprint) !=
        record.fingerprint) {
      throw const AppMessagingException('fingerprint_mismatch');
    }
    return _contactView(
      await _contactTrustService.verifyContact(_payloadFor(record)),
    );
  }

  Future<AppContact> reverifyChangedFingerprint({
    required String deviceId,
    required String independentlyComparedFingerprint,
  }) async {
    final record = await _contactTrustService.getContact(deviceId);
    if (record == null || record.state != ContactTrustState.identityChanged) {
      throw const AppMessagingException('no_identity_change_pending');
    }
    final candidateFingerprint = record.candidateFingerprint;
    final candidatePublicKey = record.candidatePublicKeyPem;
    if (candidateFingerprint == null || candidatePublicKey == null) {
      throw const AppMessagingException('candidate_identity_unavailable');
    }
    if (_normalizeFingerprint(independentlyComparedFingerprint) !=
        candidateFingerprint) {
      throw const AppMessagingException('fingerprint_mismatch');
    }
    return _contactView(
      await _contactTrustService.reverifyChangedIdentity(
        PublicIdentityQrPayload(
          version: PublicIdentityQrPayload.currentVersion,
          deviceId: record.deviceId,
          publicKeyPem: candidatePublicKey,
          fingerprint: candidateFingerprint,
          createdAt: record.updatedAt,
        ),
      ),
    );
  }

  Future<AppContact> revokeContact(String deviceId) async =>
      _contactView(await _contactTrustService.revokeContact(deviceId));

  Future<SessionBootstrapView> requestSession(String peerDeviceId) async {
    final service = _sessionService;
    final contact = await _contactTrustService.requireVerified(peerDeviceId);
    final request = await service.createSession(
      remoteDeviceId: peerDeviceId,
      remoteIdentityPublicKeyPem: contact.publicKeyPem,
      localDeviceId: _requireLocalDeviceId(),
    );
    _pendingSessionExchanges[request.sessionId] = jsonEncode(request.toJson());
    _sessionOverrides[request.sessionId] = AppSessionStatus.requestPending;
    try {
      await _sessionExchangeGateway.sendExchange(
        recipientDeviceId: peerDeviceId,
        serializedExchange: _pendingSessionExchanges[request.sessionId]!,
      );
    } on Object {
      // The signed request remains staged locally; no session is marked ready.
    }
    return sessionStatus(request.sessionId);
  }

  Future<SessionBootstrapView> acceptSessionExchange(
    String serializedExchange,
  ) async {
    final service = _sessionService;
    final request = _decodeSessionExchange(serializedExchange);
    final contact = await _contactTrustService.requireVerified(
      request.senderDeviceId,
    );
    if (contact.publicKeyPem != request.senderIdentityPublicKeyPem) {
      throw const AppMessagingException('session_identity_key_mismatch');
    }
    final result = await service.acceptSession(
      message: request,
      localDeviceId: _requireLocalDeviceId(),
      expectedRemoteIdentityPublicKeyPem: contact.publicKeyPem,
    );
    _pendingSessionExchanges[result.record.sessionId] = jsonEncode(
      result.response.toJson(),
    );
    _sessionOverrides[result.record.sessionId] =
        AppSessionStatus.responsePendingDelivery;
    try {
      await _sessionExchangeGateway.sendExchange(
        recipientDeviceId: result.record.remoteDeviceId,
        serializedExchange: _pendingSessionExchanges[result.record.sessionId]!,
      );
    } on Object {
      // The accepted session is not exposed as ready until its response is sent.
    }
    return sessionStatus(result.record.sessionId);
  }

  Future<SessionBootstrapView> completeSessionExchange(
    String serializedExchange,
  ) async {
    final service = _sessionService;
    final response = _decodeSessionExchange(serializedExchange);
    final contact = await _contactTrustService.requireVerified(
      response.senderDeviceId,
    );
    if (contact.publicKeyPem != response.senderIdentityPublicKeyPem) {
      throw const AppMessagingException('session_identity_key_mismatch');
    }
    final established = await service.establishAcceptedSession(
      message: response,
      localDeviceId: _requireLocalDeviceId(),
    );
    _sessionOverrides[established.sessionId] = AppSessionStatus.established;
    _pendingSessionExchanges.remove(established.sessionId);
    return sessionStatus(established.sessionId);
  }

  String? exportPendingSessionExchange(String sessionId) =>
      _pendingSessionExchanges[sessionId];

  SessionBootstrapView sessionStatus(String sessionId) {
    final status = _sessionOverrides[sessionId];
    if (status != null) {
      return SessionBootstrapView(
        sessionId: sessionId,
        status: status,
        exchangeTransportAvailable: _sessionExchangeGateway.isConfigured,
      );
    }
    return SessionBootstrapView(
      sessionId: sessionId,
      status: AppSessionStatus.restoredNeedsReview,
      exchangeTransportAvailable: _sessionExchangeGateway.isConfigured,
    );
  }

  Future<List<AppConversation>> conversations() async {
    final sessions = await _sessionStore.listSessionRecords();
    final contactsById = {
      for (final contact in await contacts()) contact.deviceId: contact,
    };
    final allMessages = await _messageStore.listMessages();
    final outbox = await _messageStore.listOutbox();
    final conversations = <AppConversation>[];
    for (final session in sessions) {
      final peer = contactsById[session.remoteDeviceId];
      final sessionMessages =
          allMessages
              .where((message) => message.sessionId == session.sessionId)
              .toList()
            ..sort((left, right) => left.createdAt.compareTo(right.createdAt));
      final last = sessionMessages.isEmpty
          ? null
          : _messageView(sessionMessages.last);
      conversations.add(
        AppConversation(
          sessionId: session.sessionId,
          peerDeviceId: session.remoteDeviceId,
          displayAlias: peer?.displayAlias ?? session.remoteDeviceId,
          trustStatus: peer?.trustStatus ?? AppTrustStatus.unverified,
          sessionStatus: _sessionStatusForRecord(session),
          pendingMessageCount: outbox
              .where((message) => message.sessionId == session.sessionId)
              .length,
          lastMessage: last,
        ),
      );
    }
    conversations.sort((left, right) {
      final leftAt =
          left.lastMessage?.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      final rightAt =
          right.lastMessage?.createdAt ??
          DateTime.fromMillisecondsSinceEpoch(0);
      return rightAt.compareTo(leftAt);
    });
    return List.unmodifiable(conversations);
  }

  Future<List<AppMessage>> messages(String sessionId) async {
    final stored = await _messageStore.listMessages(sessionId: sessionId);
    return List.unmodifiable(stored.map(_messageView));
  }

  Future<AppMessage> sendText({
    required String sessionId,
    required String peerDeviceId,
    required String text,
  }) async {
    if (_sessionOverrides[sessionId] != AppSessionStatus.established) {
      throw const AppMessagingException('session_not_ready');
    }
    await _contactTrustService.requireVerified(peerDeviceId);
    final message = await _requireMessagingService().sendTextMessage(
      sessionId: sessionId,
      recipientDeviceId: peerDeviceId,
      plaintext: text,
    );
    return _messageView(message);
  }

  Future<AppMessage> retryMessage(String messageId) async {
    final stored = await _messageStore.getMessage(messageId);
    if (stored == null || stored.direction != MessageDirection.outgoing) {
      throw const AppMessagingException('message_not_found');
    }
    if (_sessionOverrides[stored.sessionId] != AppSessionStatus.established) {
      throw const AppMessagingException('session_not_ready');
    }
    final session = await _sessionService.getSession(stored.sessionId);
    if (session == null) {
      throw const AppMessagingException('session_not_found');
    }
    try {
      await _contactTrustService.withTrustedSession(
        session,
        stored.peerDeviceId,
        () async {
          if (_packetTransport.connectionState !=
              TransportConnectionState.connected) {
            throw const AppMessagingException('transport_not_connected');
          }
          final packet = PacketSubmission(
            packetId: stored.messageId,
            recipientRouteId: stored.peerDeviceId,
            expiresAt: stored.expiresAt,
            encryptedPacket: utf8.encode(stored.serializedPacket),
          );
          final receipt = await _packetTransport.sendPacket(packet);
          if (receipt.packetId != stored.messageId ||
              !const {
                'queued',
                'duplicate',
                'delivered',
                'acknowledged',
              }.contains(receipt.state)) {
            throw const AppMessagingException('invalid_submission_receipt');
          }
          await _messageStore.markSubmitted(stored.messageId);
        },
      );
    } on Object {
      await _messageStore.markFailed(messageId);
      final failed = await _messageStore.getMessage(messageId);
      if (failed == null) {
        throw const AppMessagingException('message_not_found');
      }
      return _messageView(failed);
    }
    final updated = await _messageStore.getMessage(messageId);
    if (updated == null) {
      throw const AppMessagingException('message_not_found');
    }
    return _messageView(updated);
  }

  Future<AppSyncResult> synchronize() async {
    final messaging = _messagingService;
    if (messaging == null) {
      throw const AppMessagingException('local_identity_unavailable');
    }
    final result = await messaging.synchronize();
    final storedMessages = await _messageStore.listMessages();
    for (final conversation in await conversations()) {
      if (_sessionOverrides[conversation.sessionId] ==
              AppSessionStatus.responsePendingDelivery &&
          storedMessages.any(
            (message) =>
                message.sessionId == conversation.sessionId &&
                message.direction == MessageDirection.incoming,
          )) {
        _sessionOverrides[conversation.sessionId] =
            AppSessionStatus.established;
      }
    }
    return AppSyncResult(
      submittedToRelay: result.submitted,
      receivedLocally: result.received,
      duplicatesAcknowledged: result.duplicates,
      moreAvailable: result.moreAvailable,
    );
  }

  AppSessionStatus _sessionStatusForRecord(SessionRecord record) {
    final override = _sessionOverrides[record.sessionId];
    if (override != null) return override;
    if (record.isClosed) return AppSessionStatus.closed;
    if (record.isPending) return AppSessionStatus.requestPending;
    return AppSessionStatus.restoredNeedsReview;
  }

  AppContact _contactView(ContactTrustRecord record) => AppContact(
    deviceId: record.deviceId,
    displayAlias: record.deviceId,
    fingerprint: record.state == ContactTrustState.identityChanged
        ? record.candidateFingerprint ?? record.fingerprint
        : record.fingerprint,
    trustStatus: switch (record.state) {
      ContactTrustState.unverified => AppTrustStatus.unverified,
      ContactTrustState.verified => AppTrustStatus.verified,
      ContactTrustState.identityChanged => AppTrustStatus.identityChanged,
      ContactTrustState.revoked => AppTrustStatus.revoked,
    },
    previousFingerprint: record.state == ContactTrustState.identityChanged
        ? record.fingerprint
        : null,
  );

  LocalIdentityView _identityView(DeviceIdentity identity) => LocalIdentityView(
    deviceId: identity.deviceId,
    fingerprint: identity.fingerprint,
    statusLabel: identity.statusLabel,
    publicQrJson: _identityService.createQrPayload(identity).toQrString(),
  );

  AppMessage _messageView(StoredMessage message) => AppMessage(
    id: message.messageId,
    body: message.plaintext,
    isOutgoing: message.direction == MessageDirection.outgoing,
    status: switch (message.state) {
      MessageState.queued => AppMessageStatus.pending,
      MessageState.submitted => AppMessageStatus.submittedToRelay,
      MessageState.received => AppMessageStatus.receivedLocally,
      MessageState.failed => AppMessageStatus.failed,
    },
    createdAt: message.createdAt,
  );

  PublicIdentityQrPayload _payloadFor(ContactTrustRecord record) =>
      PublicIdentityQrPayload(
        version: PublicIdentityQrPayload.currentVersion,
        deviceId: record.deviceId,
        publicKeyPem: record.publicKeyPem,
        fingerprint: record.fingerprint,
        createdAt: record.createdAt,
      );

  SessionProtocolMessage _decodeSessionExchange(String serialized) {
    try {
      final value = jsonDecode(serialized);
      if (value is! Map<String, dynamic>) {
        throw const AppMessagingException('invalid_session_exchange');
      }
      return SessionProtocolMessage.fromJson(value);
    } on AppMessagingException {
      rethrow;
    } on Object {
      throw const AppMessagingException('invalid_session_exchange');
    }
  }

  String _normalizeFingerprint(String value) =>
      value.replaceAll(RegExp(r'\s+'), '').toLowerCase();

  String _requireLocalDeviceId() =>
      _localDeviceId ??
      (throw const AppMessagingException('local_identity_unavailable'));

  MessagingService _requireMessagingService() =>
      _messagingService ??
      (throw const AppMessagingException('local_identity_unavailable'));
}
