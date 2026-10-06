enum AppTrustStatus { unverified, verified, identityChanged, revoked }

enum AppSessionStatus {
  notStarted,
  requestPending,
  responsePendingDelivery,
  established,
  closed,
  restoredNeedsReview,
}

enum AppConnectionStatus { notConfigured, disconnected, connecting, connected }

enum AppMessageStatus {
  pending,
  submittedToRelay,
  receivedLocally,
  failed,
}

class LocalIdentityView {
  const LocalIdentityView({
    required this.deviceId,
    required this.fingerprint,
    required this.statusLabel,
    required this.publicQrJson,
  });

  final String deviceId;
  final String fingerprint;
  final String statusLabel;
  final String publicQrJson;
}

class AppContact {
  const AppContact({
    required this.deviceId,
    required this.displayAlias,
    required this.fingerprint,
    required this.trustStatus,
    this.previousFingerprint,
  });

  final String deviceId;
  final String displayAlias;
  final String fingerprint;
  final AppTrustStatus trustStatus;
  final String? previousFingerprint;
}

class AppMessage {
  const AppMessage({
    required this.id,
    required this.body,
    required this.isOutgoing,
    required this.status,
    required this.createdAt,
  });

  final String id;
  final String body;
  final bool isOutgoing;
  final AppMessageStatus status;
  final DateTime createdAt;
}
class AppMessageSummary {
  const AppMessageSummary({
    required this.status,
    required this.message,
  });

  final AppMessageStatus status;
  final String message;
}
class AppConversation {
  const AppConversation({
    required this.sessionId,
    required this.peerDeviceId,
    required this.displayAlias,
    required this.trustStatus,
    required this.sessionStatus,
    required this.pendingMessageCount,
    required this.lastMessage,
  });

  final String sessionId;
  final String peerDeviceId;
  final String displayAlias;
  final AppTrustStatus trustStatus;
  final AppSessionStatus sessionStatus;
  final int pendingMessageCount;
  final AppMessage? lastMessage;
}

class AppSyncResult {
  const AppSyncResult({
    required this.submittedToRelay,
    required this.receivedLocally,
    required this.duplicatesAcknowledged,
    required this.moreAvailable,
  });

  final int submittedToRelay;
  final int receivedLocally;
  final int duplicatesAcknowledged;
  final bool moreAvailable;
}

class SessionBootstrapView {
  const SessionBootstrapView({
    required this.sessionId,
    required this.status,
    required this.exchangeTransportAvailable,
  });

  final String sessionId;
  final AppSessionStatus status;
  final bool exchangeTransportAvailable;
}