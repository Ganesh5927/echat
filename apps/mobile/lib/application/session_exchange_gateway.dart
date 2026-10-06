abstract interface class SessionExchangeGateway {
  bool get isConfigured;

  Future<void> sendExchange({
    required String recipientDeviceId,
    required String serializedExchange,
  });
}

class UnavailableSessionExchangeGateway implements SessionExchangeGateway {
  const UnavailableSessionExchangeGateway();

  @override
  bool get isConfigured => false;

  @override
  Future<void> sendExchange({
    required String recipientDeviceId,
    required String serializedExchange,
  }) async {
    throw StateError('Session exchange transport is not configured.');
  }
}
