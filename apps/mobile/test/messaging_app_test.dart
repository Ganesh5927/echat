import 'dart:convert';
import 'dart:io';

import 'package:echat_identity/echat_identity.dart';
import 'package:echat_mobile/app/mobile_app_services.dart';
import 'package:echat_mobile/application/messaging_models.dart';
import 'package:echat_mobile/application/session_exchange_gateway.dart';
import 'package:echat_mobile/platform/app_local_storage_key_provider.dart';
import 'package:echat_mobile/platform/secure_value_store.dart';
import 'package:echat_mobile/platform/unavailable_packet_transport.dart';
import 'package:echat_mobile/ui/contacts_screen.dart';
import 'package:echat_mobile/ui/conversations_screen.dart';
import 'package:echat_mobile/ui/echat_app.dart';
import 'package:echat_mobile/ui/identity_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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

Future<_AppHarness> _createHarness() async {
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
    packetTransport: UnavailablePacketTransport(
      'relay_endpoint_not_configured',
    ),
    sessionExchangeGateway: const UnavailableSessionExchangeGateway(),
  );
  final localIdentity = await services.controller.createLocalIdentity();
  final remoteIdentityService = IdentityService(
    store: MemorySecureIdentityStore(),
  );
  final remoteIdentity = await remoteIdentityService.createIdentity();
  final contact = await services.controller.observeContactQr(
    remoteIdentityService.createQrPayload(remoteIdentity).toQrString(),
  );
  expect(contact.trustStatus, AppTrustStatus.unverified);
  await services.controller.verifyContactFingerprint(
    deviceId: remoteIdentity.deviceId,
    independentlyComparedFingerprint: remoteIdentity.fingerprint,
  );
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

  testWidgets(
    'app bootstrap opens contacts, conversations, and identity screens',
    (tester) async {
      final harness = await _createHarness();
      await tester.pumpWidget(EchatApp(services: harness.services));
      await _pumpUntilFound(tester, find.text('Conversations'));
      expect(find.text('Conversations'), findsOneWidget);

      await tester.tap(find.text('Contacts').last);
      await _pumpTransition(tester);
      expect(find.byType(ContactsScreen), findsOneWidget);

      await tester.tap(find.text('Identity').last);
      await _pumpTransition(tester);
      expect(find.byType(IdentityScreen), findsOneWidget);
      expect(find.text('IDENTITY CREATED'), findsOneWidget);
      expect(find.text('IDENTITY VERIFIED'), findsNothing);
      expect(find.text('Mark Verified'), findsNothing);
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
      await tester.tap(find.byKey(Key('contact-${anotherIdentity.deviceId}')));
      await _pumpUntilFound(tester, find.text('Contact details'));
      await _pumpUntilFound(tester, find.text('Verify contact'));
      final imported = await harness.services.controller.contact(
        anotherIdentity.deviceId,
      );
      expect(imported?.trustStatus, AppTrustStatus.unverified);
      final renderedText = tester
          .widgetList<Text>(find.byType(Text))
          .map((widget) => widget.data ?? widget.textSpan?.toPlainText() ?? '')
          .join(' | ');
      expect(find.text('Unverified'), findsOneWidget);
      expect(
        find.text('Verify contact'),
        findsOneWidget,
        reason: 'Rendered text: $renderedText',
      );
      expect(find.text('Start 1-to-1 session'), findsNothing);
    },
  );

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
      expect(find.text('Pending in encrypted outbox'), findsOneWidget);
      expect(find.byKey(const Key('offline-banner')), findsOneWidget);
    },
  );
}
