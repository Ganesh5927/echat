import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:echat_identity/echat_identity.dart';
import 'package:echat_mobile/app/mobile_app_services.dart';
import 'package:echat_mobile/application/messaging_models.dart';
import 'package:echat_mobile/application/session_exchange_gateway.dart';
import 'package:echat_mobile/application/theme_preferences.dart';
import 'package:echat_mobile/platform/app_local_storage_key_provider.dart';
import 'package:echat_mobile/platform/secure_value_store.dart';
import 'package:echat_mobile/platform/unavailable_packet_transport.dart';
import 'package:echat_mobile/ui/contacts_screen.dart';
import 'package:echat_mobile/ui/conversations_screen.dart';
import 'package:echat_mobile/ui/echat_app.dart';
import 'package:echat_mobile/ui/identity_screen.dart';
import 'package:echat_mobile/ui/onboarding_screen.dart';
import 'package:echat_mobile/ui/profile_screen.dart';
import 'package:echat_mobile/ui/settings_screen.dart';
import 'package:echat_mobile/ui/echat_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:echat_transport/echat_transport.dart';
import 'package:echat_storage/echat_storage.dart';

class _MemorySecureValueStore implements SecureValueStore {
  final Map<String, String> values = {};

  @override
  Future<void> delete(String key) async => values.remove(key);

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }
}

class _FailingSecureValueStore implements SecureValueStore {
  @override
  Future<void> delete(String key) async =>
      throw StateError('secure storage unavailable');

  @override
  Future<String?> read(String key) async =>
      throw StateError('secure storage unavailable');

  @override
  Future<void> write(String key, String value) async =>
      throw StateError('secure storage unavailable');
}

class _AuthenticatedTestTransport implements PacketTransport {
  final StreamController<TransportConnectionState> _states =
      StreamController.broadcast(sync: true);
  TransportConnectionState _connectionState =
      TransportConnectionState.disconnected;
  bool _isAuthenticated = false;

  @override
  TransportConnectionState get connectionState => _connectionState;

  @override
  bool get isAuthenticated => _isAuthenticated;

  @override
  Stream<TransportConnectionState> get connectionStates => _states.stream;

  void setAuthenticated(bool value) {
    _isAuthenticated = value;
    setConnectionState(
      value
          ? TransportConnectionState.connected
          : TransportConnectionState.disconnected,
      authenticated: value,
    );
  }

  void setConnectionState(
    TransportConnectionState value, {
    bool authenticated = false,
  }) {
    _isAuthenticated = authenticated;
    _connectionState = value;
    _states.add(_connectionState);
  }

  Future<void> dispose() => _states.close();

  @override
  Future<void> connect() async => setAuthenticated(true);

  @override
  Future<void> disconnect() async => setAuthenticated(false);

  @override
  Future<PacketReceipt> sendPacket(PacketSubmission packet) async =>
      PacketReceipt(packetId: packet.packetId, state: 'queued');

  @override
  Future<List<DeliveredPacket>> receivePackets() async =>
      const <DeliveredPacket>[];

  @override
  Future<void> acknowledge(String packetId) async {}
}

class _AppHarness {
  _AppHarness({
    required this.services,
    required this.directory,
    required this.secureStore,
    required this.localIdentity,
    required this.remoteIdentityService,
    required this.remoteIdentity,
  });

  final MobileAppServices services;
  final Directory directory;
  final _MemorySecureValueStore secureStore;
  final LocalIdentityView localIdentity;
  final IdentityService remoteIdentityService;
  final DeviceIdentity remoteIdentity;

  Future<void> establishSessionThroughExistingHandshake() async {
    final controller = services.controller;
    final requestView = await controller.requestSession(
      remoteIdentity.deviceId,
    );
    expect(requestView.status, AppSessionStatus.requestPending);
    final serializedRequest = controller.exportPendingSessionExchange(
      requestView.sessionId,
    );
    expect(serializedRequest, isNotNull);

    final localPublic = PublicIdentityQrPayload.fromQrString(
      localIdentity.publicQrJson,
    );
    final remoteSessionService = SessionService(
      identityService: remoteIdentityService,
      sessionStore: MemorySecureSessionStore(),
    );
    final accepted = await remoteSessionService.acceptSession(
      message: SessionProtocolMessage.fromJson(
        jsonDecode(serializedRequest!) as Map<String, dynamic>,
      ),
      localDeviceId: remoteIdentity.deviceId,
      expectedRemoteIdentityPublicKeyPem: localPublic.publicKeyPem,
    );
    final completed = await controller.completeSessionExchange(
      jsonEncode(accepted.response.toJson()),
    );
    expect(completed.status, AppSessionStatus.established);
  }
}

Future<_AppHarness> _createHarness({
  bool addContact = true,
  PacketTransport? packetTransport,
}) async {
  SharedPreferences.setMockInitialValues({});
  final directory = Directory(
    '${Directory.systemTemp.path}${Platform.pathSeparator}echat-mobile-test',
  );
  final secureStore = _MemorySecureValueStore();
  final services = await MobileAppServices.bootstrap(
    supportDirectory: directory,
    secureValueStore: secureStore,
    messageBackend: MemoryEncryptedRecordBackend(),
    contactTrustBackend: MemoryEncryptedRecordBackend(),
    sessionBackend: MemoryEncryptedRecordBackend(),
    profileBackend: MemoryEncryptedRecordBackend(),
    packetTransport:
        packetTransport ??
        UnavailablePacketTransport('relay_endpoint_not_configured'),
    sessionExchangeGateway: const UnavailableSessionExchangeGateway(),
  );
  final localIdentity = await services.controller.createLocalIdentity();
  final remoteIdentityService = IdentityService(
    store: MemorySecureIdentityStore(),
  );
  final remoteIdentity = await remoteIdentityService.createIdentity();
  if (addContact) {
    final contact = await services.controller.observeContactQr(
      remoteIdentityService.createQrPayload(remoteIdentity).toQrString(),
    );
    expect(contact.trustStatus, AppTrustStatus.unverified);
    await services.controller.verifyContactFingerprint(
      deviceId: remoteIdentity.deviceId,
      independentlyComparedFingerprint: remoteIdentity.fingerprint,
    );
  }
  return _AppHarness(
    services: services,
    directory: directory,
    secureStore: secureStore,
    localIdentity: localIdentity,
    remoteIdentityService: remoteIdentityService,
    remoteIdentity: remoteIdentity,
  );
}

Future<void> _pumpUntilFound(WidgetTester tester, Finder finder) async {
  for (var frame = 0; frame < 40; frame++) {
    await tester.pump(const Duration(milliseconds: 50));
    if (finder.evaluate().isNotEmpty) return;
  }
}

Future<void> _pumpTransition(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 350));
}

Future<void> _scrollSettingsTo(WidgetTester tester, Finder target) async {
  await tester.ensureVisible(target.first);
  await tester.pump();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'bootstrap wires services without placing the local key in preferences',
    () async {
      final harness = await _createHarness();
      expect(harness.services.controller.hasActiveIdentity, isTrue);
      expect(
        harness.services.controller.connectionStatus,
        AppConnectionStatus.notConfigured,
      );
      expect(
        harness.secureStore.values,
        contains(AppLocalStorageKeyProvider.storageKeyName),
      );
      expect(harness.services.isTemporaryLocalMode, isFalse);
      expect(
        SharedPreferences.getInstance().then((prefs) => prefs.getKeys()),
        completion(isNot(contains(AppLocalStorageKeyProvider.storageKeyName))),
      );
      expect(
        Directory(
          '${harness.directory.path}${Platform.pathSeparator}echat${Platform.pathSeparator}messages',
        ).path,
        isNot(
          Directory(
            '${harness.directory.path}${Platform.pathSeparator}echat${Platform.pathSeparator}contact-trust',
          ).path,
        ),
      );
    },
  );

  test(
    'bootstrap falls back to in-memory local services when secure storage fails',
    () async {
      final services = await MobileAppServices.bootstrap(
        secureValueStore: _FailingSecureValueStore(),
        messageBackend: MemoryEncryptedRecordBackend(),
        contactTrustBackend: MemoryEncryptedRecordBackend(),
        packetTransport: UnavailablePacketTransport(
          'secure_storage_unavailable',
        ),
        sessionExchangeGateway: const UnavailableSessionExchangeGateway(),
      );
      expect(
        services.controller.connectionStatus,
        AppConnectionStatus.disconnected,
      );
      expect(services.controller.hasActiveIdentity, isFalse);
      expect(services.isTemporaryLocalMode, isTrue);
      expect(
        services.relayConfigurationMessage,
        contains('Local secure storage unavailable'),
      );
    },
  );

  testWidgets(
    'app bootstrap opens contacts, conversations, and identity screens',
    (tester) async {
      final harness = await _createHarness();
      await tester.pumpWidget(EchatApp(services: harness.services));
      await _pumpUntilFound(tester, find.text('Conversations').first);
      expect(find.text('Conversations').first, findsOneWidget);

      await tester.tap(find.text('Contacts').last);
      await _pumpTransition(tester);
      expect(find.byType(ContactsScreen), findsOneWidget);

      await tester.tap(find.text('Identity').last);
      await _pumpTransition(tester);
      expect(find.byType(IdentityScreen), findsOneWidget);
      expect(find.text('eChat'), findsOneWidget);
      expect(find.text('My Identity'), findsOneWidget);
      expect(find.text('IDENTITY CREATED'), findsOneWidget);
      expect(find.text('IDENTITY VERIFIED'), findsNothing);
      expect(find.text('Mark Verified'), findsNothing);
      expect(find.text('Private key material'), findsOneWidget);
      expect(
        find.textContaining('Compare fingerprints through an independent'),
        findsOneWidget,
      );
    },
  );

  testWidgets('Settings opens and shows all real account sections', (
    tester,
  ) async {
    final harness = await _createHarness();
    expect(await harness.services.profileService.load(), isNull);
    await tester.pumpWidget(EchatApp(services: harness.services));
    await _pumpUntilFound(tester, find.text('Conversations').first);
    await tester.tap(find.text('Settings').last);
    await _pumpTransition(tester);
    await _pumpUntilFound(tester, find.text('My Identity').first);

    expect(find.byType(SettingsScreen), findsOneWidget);
    for (final section in [
      'My Identity',
      'Privacy & Security',
      'Contacts & Trust',
      'Messaging',
      'Connection / Relay',
      'Storage',
      'About eChat',
    ]) {
      await _scrollSettingsTo(tester, find.text(section));
      expect(find.text(section), findsOneWidget);
    }
    await _scrollSettingsTo(tester, find.text('Not configured'));
    expect(find.text('Not configured'), findsOneWidget);
    await _scrollSettingsTo(tester, find.textContaining('Verified 1'));
    expect(find.textContaining('Verified 1'), findsWidgets);
    await _scrollSettingsTo(tester, find.text('No local sessions'));
    expect(find.text('No local sessions'), findsWidgets);
    await _scrollSettingsTo(tester, find.text('Notifications unavailable'));
    expect(find.text('Notifications unavailable'), findsOneWidget);
    expect(find.text('Foreground sync only'), findsOneWidget);
  });

  testWidgets('Appearance changes theme immediately and persists selection', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final harness = await _createHarness();
    await tester.pumpWidget(EchatApp(services: harness.services));
    await _pumpUntilFound(tester, find.text('Conversations').first);
    await tester.tap(find.text('Settings').last);
    await _pumpTransition(tester);
    await _scrollSettingsTo(tester, find.text('Appearance'));

    expect(find.text('Dark'), findsOneWidget);
    expect(find.text('Cyan'), findsOneWidget);
    await tester.tap(find.byKey(const Key('appearance-theme-mode')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('AMOLED').last);
    await tester.pumpAndSettle();
    expect(EchatColors.background, const Color(0xFF000000));

    await tester.ensureVisible(find.byKey(const Key('appearance-accent')));
    await tester.tap(find.byKey(const Key('appearance-accent')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Green').last);
    await tester.pumpAndSettle();
    expect(EchatColors.accent, const Color(0xFF83D7A0));

    final stored = await ThemePreferenceStore().load();
    expect(stored.mode, EchatThemeMode.amoled);
    expect(stored.accent, EchatAccent.green);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Settings reflects authenticated relay state changes', (
    tester,
  ) async {
    final transport = _AuthenticatedTestTransport();
    addTearDown(transport.dispose);
    final harness = await _createHarness(packetTransport: transport);
    await tester.pumpWidget(EchatApp(services: harness.services));
    await _pumpUntilFound(tester, find.text('Conversations').first);
    await tester.tap(find.text('Settings').last);
    await _pumpTransition(tester);
    await _pumpUntilFound(tester, find.text('Offline / unavailable'));
    expect(find.text('Offline / unavailable'), findsOneWidget);

    transport.setConnectionState(TransportConnectionState.authenticating);
    await tester.pump();
    expect(find.text('Authenticating'), findsOneWidget);

    transport.setConnectionState(TransportConnectionState.authenticationFailed);
    await tester.pump();
    expect(find.text('Authentication failed'), findsOneWidget);

    transport.setAuthenticated(true);
    await tester.pump();
    expect(find.text('Connected · authenticated'), findsOneWidget);

    transport.setAuthenticated(false);
    await tester.pump();
    expect(find.text('Offline / unavailable'), findsOneWidget);
  });

  testWidgets(
    'Settings navigates to Identity and returns with back navigation',
    (tester) async {
      final harness = await _createHarness();
      await tester.pumpWidget(EchatApp(services: harness.services));
      await _pumpUntilFound(tester, find.text('Conversations').first);
      await tester.tap(find.text('Settings').last);
      await _pumpTransition(tester);
      await _pumpUntilFound(tester, find.text('Device identity').first);
      await tester.ensureVisible(find.text('Device identity').first);
      await tester.pump();
      await tester.tap(find.text('Device identity').first);
      await _pumpTransition(tester);

      expect(find.byType(IdentityScreen), findsOneWidget);
      expect(find.text('My Identity'), findsWidgets);
      await tester.pageBack();
      await _pumpTransition(tester);
      expect(find.byType(SettingsScreen), findsOneWidget);
      await _scrollSettingsTo(tester, find.text('About eChat'));
      expect(find.text('About eChat'), findsOneWidget);
    },
  );

  testWidgets(
    'Settings navigates to Contacts and returns with back navigation',
    (tester) async {
      final harness = await _createHarness();
      await tester.pumpWidget(EchatApp(services: harness.services));
      await _pumpUntilFound(tester, find.text('Conversations').first);
      await tester.tap(find.text('Settings').last);
      await _pumpTransition(tester);
      await _pumpUntilFound(tester, find.text('Contacts & Trust').first);
      await _scrollSettingsTo(tester, find.text('Your contacts'));
      await tester.tap(find.text('Your contacts'));
      await _pumpTransition(tester);

      expect(find.byType(ContactsScreen), findsOneWidget);
      expect(find.text('Contacts'), findsWidgets);
      await tester.pageBack();
      await _pumpTransition(tester);
      expect(find.byType(SettingsScreen), findsOneWidget);
    },
  );

  testWidgets('Settings opens the local Profile screen', (tester) async {
    final harness = await _createHarness();
    await tester.pumpWidget(EchatApp(services: harness.services));
    await _pumpUntilFound(tester, find.text('Conversations').first);
    await tester.tap(find.text('Settings').last);
    await _pumpTransition(tester);
    await _scrollSettingsTo(tester, find.text('My Profile'));
    await tester.tap(find.text('Display name and avatar'));
    await _pumpTransition(tester);

    expect(find.byType(ProfileScreen), findsOneWidget);
    expect(find.text('My Profile'), findsWidgets);
    await tester.pageBack();
    await _pumpTransition(tester);
    expect(find.byType(SettingsScreen), findsOneWidget);
  });

  testWidgets(
    'Settings warns about temporary storage and omits secrets on narrow screens',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final services = await MobileAppServices.bootstrap(
        supportDirectory: Directory(
          '${Directory.systemTemp.path}${Platform.pathSeparator}echat-settings-fallback-test',
        ),
        secureValueStore: _FailingSecureValueStore(),
        packetTransport: UnavailablePacketTransport(
          'secure_storage_unavailable',
        ),
        sessionExchangeGateway: const UnavailableSessionExchangeGateway(),
      );
      await services.controller.createLocalIdentity();
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      tester.view.physicalSize = const Size(320, 700);
      tester.view.devicePixelRatio = 1;

      await tester.pumpWidget(EchatApp(services: services));
      await _pumpUntilFound(tester, find.text('Conversations').first);
      await tester.tap(find.text('Settings').last);
      await _pumpTransition(tester);
      await _pumpUntilFound(tester, find.text('My Identity').first);

      await _scrollSettingsTo(tester, find.text('Secure storage'));
      expect(
        find.textContaining('Temporary in-memory mode is active.'),
        findsOneWidget,
      );
      await _scrollSettingsTo(
        tester,
        find.textContaining('Records use in-memory storage'),
      );
      expect(
        find.textContaining('may be lost when the app restarts'),
        findsOneWidget,
      );
      expect(find.textContaining('PRIVATE KEY'), findsNothing);
      expect(find.textContaining('sessionKey'), findsNothing);
      expect(find.textContaining('storageKey'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Profile shows temporary storage disclosure', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final services = await MobileAppServices.bootstrap(
      supportDirectory: Directory(
        '${Directory.systemTemp.path}${Platform.pathSeparator}echat-profile-fallback-test',
      ),
      secureValueStore: _FailingSecureValueStore(),
      packetTransport: UnavailablePacketTransport('secure_storage_unavailable'),
      sessionExchangeGateway: const UnavailableSessionExchangeGateway(),
    );
    expect(services.isTemporaryLocalMode, isTrue);

    await tester.pumpWidget(
      MaterialApp(
        home: ProfileScreen(
          profileService: services.profileService,
          isTemporaryLocalMode: services.isTemporaryLocalMode,
        ),
      ),
    );
    await _pumpUntilFound(
      tester,
      find.byKey(const Key('profile-display-name')),
    );

    expect(
      find.text(
        'Temporary local mode is active. Identity data may not persist after restart. Do not use this mode for a final security-sensitive deployment.',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('PRIVATE KEY'), findsNothing);
    expect(find.textContaining('sessionKey'), findsNothing);
  });

  testWidgets('system back from Settings returns to Conversations', (
    tester,
  ) async {
    final harness = await _createHarness();
    await tester.pumpWidget(EchatApp(services: harness.services));
    await _pumpUntilFound(tester, find.text('Conversations').first);
    await tester.tap(find.text('Settings').last);
    await _pumpTransition(tester);

    await tester.binding.handlePopRoute();
    await _pumpTransition(tester);
    expect(find.text('Conversations').first, findsOneWidget);
    expect(find.byType(SettingsScreen), findsNothing);
  });

  testWidgets('first launch onboarding creates identity and continues to app', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final secureStore = _MemorySecureValueStore();
    final services = await MobileAppServices.bootstrap(
      supportDirectory: Directory(
        '${Directory.systemTemp.path}${Platform.pathSeparator}echat-identity-setup-test',
      ),
      secureValueStore: secureStore,
      messageBackend: MemoryEncryptedRecordBackend(),
      contactTrustBackend: MemoryEncryptedRecordBackend(),
      packetTransport: UnavailablePacketTransport(
        'relay_endpoint_not_configured',
      ),
      sessionExchangeGateway: const UnavailableSessionExchangeGateway(),
    );

    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.view.physicalSize = const Size(320, 720);
    tester.view.devicePixelRatio = 1;

    await tester.pumpWidget(EchatApp(services: services));
    await _pumpUntilFound(tester, find.text('Welcome to eChat'));
    expect(find.byType(OnboardingScreen), findsOneWidget);
    expect(find.text('Welcome to eChat'), findsOneWidget);
    expect(find.text('Encrypted messages'), findsOneWidget);
    expect(find.text('Relay transports encrypted data'), findsOneWidget);
    expect(find.text('Metadata may still be visible'), findsOneWidget);
    expect(
      find.text(
        'Infrastructure may observe connection timing, routing information, and packet size.',
      ),
      findsOneWidget,
    );
    expect(
      find.text('The relay does not receive the message decryption keys.'),
      findsOneWidget,
    );
    expect(find.text('Create Device Identity'), findsOneWidget);
    expect(
      find.text(
        'Private identity material is stored using the platform\'s secure storage.',
      ),
      findsOneWidget,
    );
    expect(find.byType(IdentityScreen), findsNothing);

    await tester.ensureVisible(find.text('Create Device Identity'));
    await tester.pump();
    await tester.tap(find.text('Create Device Identity'));
    await _pumpUntilFound(tester, find.text('Your device identity is ready'));
    expect(find.byType(OnboardingScreen), findsOneWidget);
    expect(
      find.text(
        'Your device identity is used to authenticate this device and identify it to contacts.',
      ),
      findsOneWidget,
    );
    expect(find.text('Continue to eChat'), findsOneWidget);
    expect(find.textContaining('PRIVATE KEY'), findsNothing);
    expect(find.textContaining('sessionKey'), findsNothing);
    final privateKey = secureStore.values.entries
        .firstWhere((entry) => entry.key.endsWith('identity.private_key'))
        .value;
    expect(find.textContaining(privateKey), findsNothing);

    await tester.ensureVisible(find.text('Continue to eChat'));
    await tester.pump();
    await tester.tap(find.text('Continue to eChat'));
    await _pumpUntilFound(tester, find.text('Conversations').first);
    expect(find.byType(OnboardingScreen), findsNothing);
    expect(services.controller.hasActiveIdentity, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('existing identity skips first-time onboarding', (tester) async {
    final harness = await _createHarness();
    final storedPrivateKey = harness.secureStore.values.entries
        .firstWhere((entry) => entry.key.endsWith('identity.private_key'))
        .value;

    await tester.pumpWidget(EchatApp(services: harness.services));
    await _pumpUntilFound(tester, find.text('Conversations').first);

    expect(find.byType(OnboardingScreen), findsNothing);
    expect(find.text('Welcome to eChat'), findsNothing);
    expect(harness.services.controller.hasActiveIdentity, isTrue);
    expect(
      harness.secureStore.values.entries
          .firstWhere((entry) => entry.key.endsWith('identity.private_key'))
          .value,
      storedPrivateKey,
    );
  });

  testWidgets('profile edits save locally without changing device identity', (
    tester,
  ) async {
    final harness = await _createHarness();
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.view.physicalSize = const Size(320, 720);
    tester.view.devicePixelRatio = 1;
    final originalDeviceId = harness.localIdentity.deviceId;
    final originalFingerprint = harness.localIdentity.fingerprint;
    final avatar = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGNg+M/wHwAEAQH/cetH5QAAAABJRU5ErkJggg==',
    );
    var avatarPickerCalled = false;

    await tester.pumpWidget(
      MaterialApp(
        home: ProfileScreen(
          profileService: harness.services.profileService,
          isTemporaryLocalMode: false,
          pickAvatar: () async {
            avatarPickerCalled = true;
            return avatar;
          },
        ),
      ),
    );
    await _pumpUntilFound(
      tester,
      find.byKey(const Key('profile-display-name')),
    );
    expect(find.text('Local profile could not be loaded.'), findsNothing);

    await tester.ensureVisible(find.byKey(const Key('profile-display-name')));
    await tester.tap(find.byKey(const Key('profile-display-name')));
    await tester.enterText(
      find.byKey(const Key('profile-display-name')),
      '  Alice Local  ',
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Choose avatar'));
    await tester.tap(find.text('Choose avatar'));
    await tester.pumpAndSettle();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 250)),
    );
    await tester.pumpAndSettle();
    expect(avatarPickerCalled, isTrue);
    expect(
      find.text('Change avatar'),
      findsOneWidget,
      reason: tester
          .widgetList<Text>(find.byType(Text))
          .map((text) => text.data ?? text.textSpan?.toPlainText() ?? '')
          .join(' | '),
    );
    await tester.ensureVisible(find.text('Save profile'));
    await tester.tap(find.text('Save profile'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    final saved = await harness.services.profileService.load();
    expect(saved?.displayName, 'Alice Local');
    expect(saved?.avatarBytes, isNotNull);
    expect(saved!.avatarBytes!.length, lessThanOrEqualTo(512 * 1024));
    expect(saved.avatarBytes, isNot(avatar));
    expect(harness.localIdentity.deviceId, originalDeviceId);
    expect(harness.localIdentity.fingerprint, originalFingerprint);
    expect(find.text('Profile saved on this device.'), findsOneWidget);
    final privateKey = harness.secureStore.values.entries
        .firstWhere((entry) => entry.key.endsWith('identity.private_key'))
        .value;
    expect(find.textContaining(privateKey), findsNothing);
    expect(find.textContaining('sessionKey'), findsNothing);
    expect(find.bySemanticsLabel('Profile image preview'), findsOneWidget);

    await tester.tap(find.text('Remove avatar'));
    await tester.pump();
    await tester.tap(find.text('Save profile'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect((await harness.services.profileService.load())?.avatarBytes, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('profile image picker cancellation and invalid image fail safely', (
    tester,
  ) async {
    final harness = await _createHarness();
    final invalidAvatar = <int>[1, 2, 3, 4];
    List<int>? selectedAvatar;
    await tester.pumpWidget(
      MaterialApp(
        home: ProfileScreen(
          profileService: harness.services.profileService,
          isTemporaryLocalMode: false,
          pickAvatar: () async => selectedAvatar,
        ),
      ),
    );
    await _pumpUntilFound(
      tester,
      find.byKey(const Key('profile-display-name')),
    );

    await tester.tap(find.text('Choose avatar'));
    await tester.pumpAndSettle();
    expect(find.text('Choose avatar'), findsOneWidget);
    expect(find.text('The avatar image could not be selected.'), findsNothing);

    selectedAvatar = invalidAvatar;
    await tester.tap(find.text('Choose avatar'));
    await tester.pumpAndSettle();
    expect(
      find.text('The avatar image could not be selected.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('in-memory fallback clearly discloses temporary identity storage mode', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final services = await MobileAppServices.bootstrap(
      supportDirectory: Directory(
        '${Directory.systemTemp.path}${Platform.pathSeparator}echat-fallback-disclosure-test',
      ),
      secureValueStore: _FailingSecureValueStore(),
      messageBackend: MemoryEncryptedRecordBackend(),
      contactTrustBackend: MemoryEncryptedRecordBackend(),
      packetTransport: UnavailablePacketTransport('secure_storage_unavailable'),
      sessionExchangeGateway: const UnavailableSessionExchangeGateway(),
    );
    expect(services.isTemporaryLocalMode, isTrue);

    await tester.pumpWidget(EchatApp(services: services));
    await _pumpUntilFound(tester, find.text('Welcome to eChat'));
    expect(
      find.text(
        'Temporary local mode is active. Identity data may not persist after restart. Do not use this mode for a final security-sensitive deployment.',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('platform\'s secure storage'), findsNothing);

    await tester.ensureVisible(find.text('Create Device Identity'));
    await tester.pump();
    await tester.tap(find.text('Create Device Identity'));
    await _pumpUntilFound(tester, find.text('Your device identity is ready'));
    expect(
      find.text(
        'Temporary local mode is active. Identity data may not persist after restart. Do not use this mode for a final security-sensitive deployment.',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('PRIVATE KEY'), findsNothing);
    expect(find.textContaining('sessionKey'), findsNothing);

    await tester.ensureVisible(find.text('Continue to eChat'));
    await tester.pump();
    await tester.tap(find.text('Continue to eChat'));
    await _pumpUntilFound(tester, find.text('Conversations').first);
    await tester.tap(find.text('Identity').last);
    await _pumpTransition(tester);

    expect(find.byType(IdentityScreen), findsOneWidget);
    expect(
      find.text(
        'Temporary local mode is active. Identity data may not persist after restart. Do not use this mode for a final security-sensitive deployment.',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('PRIVATE KEY'), findsNothing);
    expect(find.textContaining('sessionKey'), findsNothing);
  });

  testWidgets(
    'identity screen renders only real public data and supported accessible actions',
    (tester) async {
      final harness = await _createHarness();
      var refreshCount = 0;
      var deleteCount = 0;
      final privateKey = harness.secureStore.values.entries
          .firstWhere((entry) => entry.key.endsWith('identity.private_key'))
          .value;
      String? copiedPayload;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copiedPayload =
                (call.arguments as Map<Object?, Object?>)['text'] as String;
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;

      await tester.pumpWidget(
        MaterialApp(
          home: IdentityScreen(
            identity: harness.localIdentity,
            relayConfigurationMessage:
                harness.services.relayConfigurationMessage,
            isTemporaryLocalMode: harness.services.isTemporaryLocalMode,
            onDelete: () async {
              deleteCount++;
            },
            onRefresh: () async {
              refreshCount++;
            },
          ),
        ),
      );
      await _pumpUntilFound(tester, find.text('My Identity'));

      expect(tester.takeException(), isNull);
      expect(find.text('eChat'), findsOneWidget);
      expect(find.text('IDENTITY CREATED'), findsOneWidget);
      expect(
        find.text(
          'Private identity material is stored using the platform\'s secure storage.',
        ),
        findsOneWidget,
      );
      expect(find.text(harness.localIdentity.fingerprint), findsOneWidget);
      expect(find.text(harness.localIdentity.deviceId), findsOneWidget);
      expect(find.text(harness.localIdentity.publicQrJson), findsOneWidget);
      expect(find.byKey(const Key('public-identity-qr')), findsOneWidget);
      expect(
        find.bySemanticsLabel('Copy public identity payload'),
        findsOneWidget,
      );
      expect(find.textContaining(privateKey), findsNothing);
      expect(find.textContaining('-----BEGIN PRIVATE KEY-----'), findsNothing);
      expect(find.bySemanticsLabel('Refresh identity'), findsOneWidget);
      expect(find.bySemanticsLabel('Delete local identity'), findsOneWidget);

      final copyButton = find.byKey(const Key('copy-public-identity'));
      await tester.ensureVisible(copyButton);
      await tester.pumpAndSettle();
      await tester.tap(copyButton);
      await tester.pumpAndSettle();
      expect(copiedPayload, harness.localIdentity.publicQrJson);
      expect(find.text('Public identity payload copied.'), findsOneWidget);
      ScaffoldMessenger.of(
        tester.element(find.byType(IdentityScreen)),
      ).hideCurrentSnackBar();
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Refresh identity'));
      await tester.pump();
      expect(refreshCount, 1);

      final deleteButton = find.byKey(const Key('delete-local-identity'));
      await tester.ensureVisible(deleteButton);
      await tester.pumpAndSettle();
      await tester.tap(deleteButton);
      await tester.pumpAndSettle();
      expect(find.text('Delete local identity?'), findsOneWidget);
      expect(
        find.textContaining('It does not delete saved contacts'),
        findsOneWidget,
      );
      expect(deleteCount, 0);
      await tester.tap(find.text('Delete identity'));
      await tester.pumpAndSettle();
      expect(deleteCount, 1);
    },
  );

  testWidgets(
    'identity deletion states retained data and returns to identity setup',
    (tester) async {
      final harness = await _createHarness();
      await harness.establishSessionThroughExistingHandshake();
      final conversation =
          (await harness.services.controller.conversations()).single;
      final sent = await harness.services.controller.sendText(
        sessionId: conversation.sessionId,
        peerDeviceId: conversation.peerDeviceId,
        text: 'retained encrypted message',
      );
      expect(sent.status, AppMessageStatus.pending);
      expect(
        harness.secureStore.values.keys.any(
          (key) => key.startsWith('echat.session.secret.'),
        ),
        isTrue,
      );

      await tester.pumpWidget(EchatApp(services: harness.services));
      await _pumpUntilFound(tester, find.text('Conversations').first);
      await tester.tap(find.text('Identity').last);
      await _pumpTransition(tester);
      final deleteButton = find.byKey(const Key('delete-local-identity'));
      await tester.ensureVisible(deleteButton);
      await tester.pumpAndSettle();
      await tester.tap(deleteButton);
      await tester.pumpAndSettle();

      expect(find.text('Delete local identity?'), findsOneWidget);
      expect(
        find.text(
          'This removes the device identity key and public identity record. It does not delete saved contacts, session records or secrets, encrypted messages, or the local storage key. Those records remain on this device. Contacts will need a new public identity if you create another.',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('all local data'), findsNothing);

      await tester.tap(find.text('Delete identity'));
      await _pumpUntilFound(tester, find.text('Welcome to eChat'));

      expect(harness.services.controller.hasActiveIdentity, isFalse);
      expect(find.text('Welcome to eChat'), findsOneWidget);
      expect(find.text('Create Device Identity'), findsOneWidget);
      expect(await harness.services.controller.contacts(), hasLength(1));
      expect(
        await harness.services.controller.messages(conversation.sessionId),
        hasLength(1),
      );
      expect(
        harness.secureStore.values.keys.any(
          (key) => key.startsWith('echat.session.secret.'),
        ),
        isTrue,
      );
      expect(
        harness.secureStore.values,
        contains(AppLocalStorageKeyProvider.storageKeyName),
      );
      expect(
        await SharedPreferences.getInstance().then(
          (prefs) => prefs.getKeys().any(
            (key) => key.startsWith('echat.session.record.'),
          ),
        ),
        isFalse,
      );
    },
  );

  testWidgets(
    'identity deletion failure is surfaced without claiming success',
    (tester) async {
      final harness = await _createHarness();
      await tester.pumpWidget(
        MaterialApp(
          home: IdentityScreen(
            identity: harness.localIdentity,
            relayConfigurationMessage:
                harness.services.relayConfigurationMessage,
            isTemporaryLocalMode: harness.services.isTemporaryLocalMode,
            onDelete: () async => throw Exception('storage unavailable'),
            onRefresh: () async {},
          ),
        ),
      );
      final deleteButton = find.byKey(const Key('delete-local-identity'));
      await tester.ensureVisible(deleteButton);
      await tester.pumpAndSettle();
      await tester.tap(deleteButton);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete identity'));
      await tester.pumpAndSettle();

      expect(
        find.text(
          'Identity could not be deleted. Check device storage and try again.',
        ),
        findsOneWidget,
      );
      expect(find.byType(IdentityScreen), findsOneWidget);
    },
  );

  testWidgets('messages screen shows a real empty state and relay status', (
    tester,
  ) async {
    final harness = await _createHarness();
    await tester.pumpWidget(
      MaterialApp(
        home: ConversationsScreen(controller: harness.services.controller),
      ),
    );
    await _pumpUntilFound(tester, find.text('No conversations yet'));

    expect(find.text('eChat'), findsOneWidget);
    expect(find.text('Messages'), findsOneWidget);
    expect(find.text('No conversations yet'), findsOneWidget);
    expect(find.text('Relay not configured'), findsOneWidget);
    expect(find.byTooltip('Synchronize conversations'), findsOneWidget);
    expect(find.textContaining('pending'), findsNothing);
  });

  testWidgets(
    'messages screen shows the real contact, local preview, trust, and delivery state',
    (tester) async {
      final harness = await _createHarness();
      await harness.establishSessionThroughExistingHandshake();
      final conversation =
          (await harness.services.controller.conversations()).single;
      final sent = await harness.services.controller.sendText(
        sessionId: conversation.sessionId,
        peerDeviceId: harness.remoteIdentity.deviceId,
        text: 'local preview canary',
      );
      expect(sent.status, AppMessageStatus.pending);

      await tester.pumpWidget(
        MaterialApp(
          home: ConversationsScreen(controller: harness.services.controller),
        ),
      );
      await _pumpUntilFound(tester, find.text('You: local preview canary'));

      expect(find.text(harness.remoteIdentity.deviceId), findsOneWidget);
      expect(find.text('You: local preview canary'), findsOneWidget);
      expect(
        find.text(DateFormat('h:mm a').format(sent.createdAt.toLocal())),
        findsOneWidget,
      );
      expect(find.text('Verified'), findsOneWidget);
      expect(find.text('Pending in encrypted outbox'), findsOneWidget);
      expect(find.text('Relay not configured'), findsOneWidget);
      expect(
        find.byKey(Key('conversation-${conversation.sessionId}')),
        findsOneWidget,
      );
      expect(find.text('No conversations yet'), findsNothing);

      final failed = await harness.services.controller.retryMessage(sent.id);
      expect(failed.status, AppMessageStatus.failed);
      await tester.pumpWidget(
        MaterialApp(
          home: ConversationsScreen(
            key: const ValueKey('failed-message-refresh'),
            controller: harness.services.controller,
          ),
        ),
      );
      await _pumpUntilFound(tester, find.text('Failed'));
      expect(find.text('Failed'), findsOneWidget);
      expect(find.text('You: local preview canary'), findsOneWidget);
    },
  );

  testWidgets('chat screen shows an honest empty conversation state', (
    tester,
  ) async {
    final harness = await _createHarness();
    await harness.establishSessionThroughExistingHandshake();
    final conversation =
        (await harness.services.controller.conversations()).single;

    await tester.pumpWidget(
      MaterialApp(
        home: ConversationScreen(
          controller: harness.services.controller,
          conversation: conversation,
        ),
      ),
    );
    await _pumpUntilFound(tester, find.text('No messages yet'));

    expect(find.text(harness.remoteIdentity.deviceId), findsAtLeastNWidgets(1));
    expect(find.text('Verified · session established'), findsOneWidget);
    expect(
      find.text(
        'Messages are stored locally in encrypted storage and encrypted before relay submission.',
      ),
      findsOneWidget,
    );
    expect(find.text('Relay not configured'), findsOneWidget);
    expect(find.byKey(const Key('message-list')), findsNothing);
  });

  testWidgets(
    'chat screen renders locally stored incoming messages with real timestamps',
    (tester) async {
      final harness = await _createHarness();
      await harness.establishSessionThroughExistingHandshake();
      final conversation =
          (await harness.services.controller.conversations()).single;
      final createdAt = DateTime.utc(2026, 10, 7, 9, 5);
      const incomingId = 'incoming-widget-message';
      await harness.services.messageStore.saveMessage(
        StoredMessage(
          messageId: incomingId,
          sessionId: conversation.sessionId,
          peerDeviceId: conversation.peerDeviceId,
          direction: MessageDirection.incoming,
          state: MessageState.received,
          plaintext: 'A locally stored incoming message',
          serializedPacket: 'serialized-packet-fixture',
          createdAt: createdAt,
          expiresAt: createdAt.add(const Duration(hours: 24)),
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: ConversationScreen(
            controller: harness.services.controller,
            conversation: conversation,
          ),
        ),
      );
      await _pumpUntilFound(
        tester,
        find.text('A locally stored incoming message'),
      );

      expect(find.text('Received on this device'), findsOneWidget);
      expect(
        find.byKey(const ValueKey<String>('message-time-$incomingId')),
        findsOneWidget,
      );
      expect(
        find.text(DateFormat('h:mm a').format(createdAt.toLocal())),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('retry-message-incoming-widget-message')),
        findsNothing,
      );
    },
  );

  testWidgets(
    'chat composer rejects whitespace and sends multiline text accessibly on narrow screens',
    (tester) async {
      final harness = await _createHarness();
      await harness.establishSessionThroughExistingHandshake();
      final conversation =
          (await harness.services.controller.conversations()).single;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;

      await tester.pumpWidget(
        MaterialApp(
          home: ConversationScreen(
            controller: harness.services.controller,
            conversation: conversation,
          ),
        ),
      );
      await _pumpUntilFound(tester, find.byKey(const Key('message-input')));

      final inputFinder = find.byKey(const Key('message-input'));
      final input = tester.widget<TextField>(inputFinder);
      expect(input.minLines, 1);
      expect(input.maxLines, 5);
      expect(input.keyboardType, TextInputType.multiline);
      expect(find.bySemanticsLabel('Send message'), findsOneWidget);

      await tester.enterText(inputFinder, '   \n ');
      await tester.pump();
      expect(
        tester
            .widget<IconButton>(find.byKey(const Key('send-message')))
            .onPressed,
        isNull,
      );
      expect(
        await harness.services.controller.messages(conversation.sessionId),
        isEmpty,
      );

      await tester.enterText(inputFinder, 'First line\nSecond line');
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(
        tester
            .widget<IconButton>(find.byKey(const Key('send-message')))
            .onPressed,
        isNotNull,
      );
      await tester.tap(find.byKey(const Key('send-message')));
      await _pumpUntilFound(tester, find.text('First line\nSecond line'));

      final storedMessages = await harness.services.controller.messages(
        conversation.sessionId,
      );
      expect(storedMessages, hasLength(1));
      expect(storedMessages.single.body, 'First line\nSecond line');
      expect(find.text('Pending in encrypted outbox'), findsOneWidget);
      expect(find.text('Submitted to relay'), findsNothing);
      expect(find.byKey(const Key('message-input')), findsOneWidget);

      await harness.services.messageStore.markSubmitted(
        storedMessages.single.id,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: ConversationScreen(
            key: const ValueKey('submitted-message-state'),
            controller: harness.services.controller,
            conversation: conversation,
          ),
        ),
      );
      await _pumpUntilFound(tester, find.text('Submitted to relay'));
      expect(find.text('Submitted to relay'), findsOneWidget);
      expect(find.text('Delivered'), findsNothing);

      await harness.services.messageStore.markFailed(storedMessages.single.id);
      await tester.pumpWidget(
        MaterialApp(
          home: ConversationScreen(
            key: const ValueKey('failed-message-state'),
            controller: harness.services.controller,
            conversation: conversation,
          ),
        ),
      );
      await _pumpUntilFound(tester, find.text('Failed'));
      final messageFinder = find.byKey(
        ValueKey<String>('message-${storedMessages.single.id}'),
      );
      expect(messageFinder, findsOneWidget);
      expect(find.text('Delivered'), findsNothing);
      await tester.tap(
        find.byKey(
          ValueKey<String>('retry-message-${storedMessages.single.id}'),
        ),
      );
      await tester.pumpAndSettle();
      final afterRetry = await harness.services.controller.messages(
        conversation.sessionId,
      );
      expect(afterRetry, hasLength(1));
      expect(afterRetry.single.id, storedMessages.single.id);
      expect(afterRetry.single.status, AppMessageStatus.failed);
    },
  );

  testWidgets(
    'contacts screen imports public identity and exposes real trust state',
    (tester) async {
      final harness = await _createHarness();
      final anotherIdentityService = IdentityService(
        store: MemorySecureIdentityStore(),
      );
      final anotherIdentity = await anotherIdentityService.createIdentity();
      final observed = await harness.services.controller.observeContactQr(
        anotherIdentityService.createQrPayload(anotherIdentity).toQrString(),
      );
      expect(observed.trustStatus, AppTrustStatus.unverified);
      await tester.pumpWidget(
        MaterialApp(
          home: ContactsScreen(controller: harness.services.controller),
        ),
      );
      await _pumpUntilFound(tester, find.text('Contacts'));
      expect(find.text('eChat'), findsOneWidget);
      expect(
        find.text(
          'Your contacts are stored locally. Compare fingerprints through a trusted channel before verifying.',
        ),
        findsOneWidget,
      );
      expect(find.bySemanticsLabel('Import public identity'), findsOneWidget);
      final contactCard = find.byKey(
        Key('contact-${anotherIdentity.deviceId}'),
      );
      expect(
        find.descendant(
          of: contactCard,
          matching: find.text(anotherIdentity.deviceId),
        ),
        findsOneWidget,
      );
      await tester.ensureVisible(contactCard);
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: contactCard,
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is Semantics &&
                widget.properties.label ==
                    'Open contact details for ${anotherIdentity.deviceId}. Identity not verified.' &&
                widget.properties.button == true,
          ),
        ),
        findsOneWidget,
      );
      await tester.tap(contactCard);
      await _pumpUntilFound(tester, find.text('Contact details'));
      await tester.drag(find.byType(ListView).last, const Offset(0, -600));
      await tester.pumpAndSettle();
      await _pumpUntilFound(tester, find.text('Verify contact'));
      final imported = await harness.services.controller.contact(
        anotherIdentity.deviceId,
      );
      expect(imported?.trustStatus, AppTrustStatus.unverified);
      expect(find.text('Identity not verified'), findsAtLeastNWidgets(1));
      await tester.ensureVisible(find.text('Verify contact'));
      await tester.pump();
      final renderedText = tester
          .widgetList<Text>(find.byType(Text))
          .map((widget) => widget.data ?? widget.textSpan?.toPlainText() ?? '')
          .join(' | ');
      expect(find.text('Unverified'), findsAtLeastNWidgets(1));
      expect(
        find.text('Verify contact'),
        findsOneWidget,
        reason: 'Rendered text: $renderedText',
      );
      expect(find.text('Start 1-to-1 session'), findsNothing);
      expect(find.text('Device ID'), findsOneWidget);
      expect(find.text('Session status'), findsOneWidget);

      await tester.enterText(
        find.byKey(const Key('contact-display-name')),
        'Alex',
      );
      await tester.ensureVisible(
        find.byKey(const Key('save-contact-display-name')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('save-contact-display-name')));
      await tester.pumpAndSettle();
      final renamed = await harness.services.controller.contact(
        anotherIdentity.deviceId,
      );
      expect(renamed?.displayAlias, 'Alex');
      expect(renamed?.fingerprint, anotherIdentity.fingerprint);
      expect(renamed?.trustStatus, AppTrustStatus.unverified);
    },
  );

  testWidgets('contact and conversation search use local data only', (
    tester,
  ) async {
    final harness = await _createHarness();
    await harness.establishSessionThroughExistingHandshake();
    final conversation =
        (await harness.services.controller.conversations()).single;
    await harness.services.controller.updateContactDisplayName(
      deviceId: conversation.peerDeviceId,
      displayName: 'Alex Example',
    );
    await harness.services.controller.sendText(
      sessionId: conversation.sessionId,
      peerDeviceId: conversation.peerDeviceId,
      text: 'local search phrase',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: ContactsScreen(controller: harness.services.controller),
      ),
    );
    await _pumpUntilFound(tester, find.text('Alex Example'));
    await tester.enterText(find.byKey(const Key('contact-search')), 'Alex');
    expect(find.text('Alex Example'), findsOneWidget);
    expect(find.text(harness.remoteIdentity.deviceId), findsNothing);

    await tester.pumpWidget(
      MaterialApp(
        home: ConversationsScreen(controller: harness.services.controller),
      ),
    );
    await _pumpUntilFound(tester, find.text('Alex Example'));
    await tester.enterText(
      find.byKey(const Key('conversation-search')),
      'local search phrase',
    );
    expect(find.text('You: local search phrase'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('contact revocation requires explicit confirmation', (
    tester,
  ) async {
    final harness = await _createHarness();
    final contact = (await harness.services.controller.contacts()).single;
    await tester.pumpWidget(
      MaterialApp(
        home: ContactDetailsScreen(
          controller: harness.services.controller,
          initialContact: contact,
        ),
      ),
    );
    await tester.drag(find.byType(ListView).last, const Offset(0, -600));
    await tester.pumpAndSettle();
    final revoke = find.byKey(const Key('revoke-contact'));
    await tester.ensureVisible(revoke);
    await tester.pumpAndSettle();
    await tester.tap(revoke);
    await tester.pumpAndSettle();
    expect(find.text('Revoke this contact?'), findsOneWidget);
    expect(
      (await harness.services.controller.contact(
        contact.deviceId,
      ))?.trustStatus,
      AppTrustStatus.verified,
    );

    await tester.tap(find.text('Revoke contact'));
    await tester.pumpAndSettle();
    expect(
      (await harness.services.controller.contact(
        contact.deviceId,
      ))?.trustStatus,
      AppTrustStatus.revoked,
    );
  });

  testWidgets('contacts screen adapts contact cards to a narrow viewport', (
    tester,
  ) async {
    final harness = await _createHarness();
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;

    await tester.pumpWidget(
      MaterialApp(
        home: ContactsScreen(controller: harness.services.controller),
      ),
    );
    await _pumpUntilFound(
      tester,
      find.byKey(Key('contact-${harness.remoteIdentity.deviceId}')),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('Identity verified'), findsOneWidget);
  });

  testWidgets('contacts screen explains its empty state and import action', (
    tester,
  ) async {
    final harness = await _createHarness(addContact: false);
    await tester.pumpWidget(
      MaterialApp(
        home: ContactsScreen(controller: harness.services.controller),
      ),
    );
    await _pumpUntilFound(tester, find.text('No contacts yet'));

    expect(find.text('Contacts'), findsOneWidget);
    expect(find.text('No contacts yet'), findsOneWidget);
    expect(
      find.textContaining('import a real public identity'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('contact-public-payload')), findsOneWidget);
    expect(find.bySemanticsLabel('Import public identity'), findsOneWidget);
  });

  testWidgets('contacts screen shows every real trust state', (tester) async {
    final harness = await _createHarness();
    final controller = harness.services.controller;

    final verifiedService = IdentityService(store: MemorySecureIdentityStore());
    final verifiedIdentity = await verifiedService.createIdentity();
    await controller.observeContactQr(
      verifiedService.createQrPayload(verifiedIdentity).toQrString(),
    );
    await controller.verifyContactFingerprint(
      deviceId: verifiedIdentity.deviceId,
      independentlyComparedFingerprint: verifiedIdentity.fingerprint,
    );

    final unverifiedService = IdentityService(
      store: MemorySecureIdentityStore(),
    );
    final unverifiedIdentity = await unverifiedService.createIdentity();
    await controller.observeContactQr(
      unverifiedService.createQrPayload(unverifiedIdentity).toQrString(),
    );

    final replacementService = IdentityService(
      store: MemorySecureIdentityStore(),
    );
    final replacementIdentity = await replacementService.createIdentity();
    final changedIdentity = PublicIdentityQrPayload(
      version: PublicIdentityQrPayload.currentVersion,
      deviceId: harness.remoteIdentity.deviceId,
      publicKeyPem: replacementIdentity.publicKeyPem,
      fingerprint: replacementIdentity.fingerprint,
      createdAt: replacementIdentity.createdAt,
    );
    await controller.observeContactQr(changedIdentity.toQrString());

    final revokedService = IdentityService(store: MemorySecureIdentityStore());
    final revokedIdentity = await revokedService.createIdentity();
    await controller.observeContactQr(
      revokedService.createQrPayload(revokedIdentity).toQrString(),
    );
    await controller.revokeContact(revokedIdentity.deviceId);

    await tester.pumpWidget(
      MaterialApp(home: ContactsScreen(controller: controller)),
    );
    await _pumpUntilFound(tester, find.byKey(const Key('contact-list')));
    final verifiedCard = find.byKey(
      Key('contact-${verifiedIdentity.deviceId}'),
    );
    final unverifiedCard = find.byKey(
      Key('contact-${unverifiedIdentity.deviceId}'),
    );
    final changedCard = find.byKey(
      Key('contact-${harness.remoteIdentity.deviceId}'),
    );
    final revokedCard = find.byKey(Key('contact-${revokedIdentity.deviceId}'));

    await tester.ensureVisible(verifiedCard);
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: verifiedCard,
        matching: find.text('Identity verified'),
      ),
      findsOneWidget,
    );
    await tester.ensureVisible(unverifiedCard);
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: unverifiedCard,
        matching: find.text('Identity not verified'),
      ),
      findsOneWidget,
    );
    await tester.ensureVisible(changedCard);
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: changedCard,
        matching: find.text('Identity changed — re-verification required'),
      ),
      findsOneWidget,
    );
    await tester.ensureVisible(revokedCard);
    await tester.pumpAndSettle();
    expect(
      find.descendant(of: revokedCard, matching: find.text('Contact revoked')),
      findsOneWidget,
    );
    await tester.ensureVisible(verifiedCard);
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: verifiedCard,
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is Semantics &&
              widget.properties.label ==
                  'Open contact details for ${verifiedIdentity.deviceId}. Identity verified.' &&
              widget.properties.button == true,
        ),
      ),
      findsOneWidget,
    );
  });

  testWidgets(
    'unverified session bootstrap stays pending and chat is blocked',
    (tester) async {
      final harness = await _createHarness();
      final session = await harness.services.controller.requestSession(
        harness.remoteIdentity.deviceId,
      );
      expect(session.status, AppSessionStatus.requestPending);
      final conversation =
          (await harness.services.controller.conversations()).single;

      await tester.pumpWidget(
        MaterialApp(
          home: ConversationScreen(
            controller: harness.services.controller,
            conversation: conversation,
          ),
        ),
      );
      await _pumpUntilFound(
        tester,
        find.text('Session request pending exchange'),
      );
      expect(find.text('Session request pending exchange'), findsOneWidget);
      expect(find.byKey(const Key('message-input')), findsOneWidget);
      final input = tester.widget<TextField>(
        find.byKey(const Key('message-input')),
      );
      expect(input.enabled, isFalse);
      expect(find.textContaining('Messaging is blocked'), findsOneWidget);
    },
  );

  testWidgets(
    'offline send renders the persisted pending message and keeps its ID on retry',
    (tester) async {
      final harness = await _createHarness();
      await harness.establishSessionThroughExistingHandshake();
      final conversation =
          (await harness.services.controller.conversations()).single;
      final sent = await harness.services.controller.sendText(
        sessionId: conversation.sessionId,
        peerDeviceId: harness.remoteIdentity.deviceId,
        text: 'offline body canary',
      );
      expect(sent.status, AppMessageStatus.pending);
      expect(sent.body, 'offline body canary');

      await expectLater(
        harness.services.controller.synchronize(),
        throwsA(isA<TransportException>()),
      );
      final afterRetry = (await harness.services.controller.messages(
        conversation.sessionId,
      )).single;
      expect(afterRetry.id, sent.id);
      expect(afterRetry.status, AppMessageStatus.pending);
      expect(
        harness.secureStore.values.values,
        isNot(contains('offline body canary')),
      );

      final failed = await harness.services.controller.retryMessage(sent.id);
      expect(failed.status, AppMessageStatus.failed);

      final refreshedConversation =
          (await harness.services.controller.conversations()).single;
      await tester.pumpWidget(
        MaterialApp(
          home: ConversationScreen(
            controller: harness.services.controller,
            conversation: refreshedConversation,
          ),
        ),
      );
      await _pumpUntilFound(tester, find.text('offline body canary'));
      expect(find.text('Failed'), findsOneWidget);
      final retryButton = find.byKey(Key('retry-message-${sent.id}'));
      expect(retryButton, findsOneWidget);
      await tester.ensureVisible(retryButton);
      await tester.pumpAndSettle();
      expect(find.byTooltip('Retry failed message'), findsOneWidget);
      await tester.tap(retryButton);
      await tester.pumpAndSettle();
      final afterUiRetry = await harness.services.controller.messages(
        conversation.sessionId,
      );
      expect(afterUiRetry, hasLength(1));
      expect(afterUiRetry.single.id, sent.id);
      expect(afterUiRetry.single.status, AppMessageStatus.failed);
    },
  );
}
