import 'dart:io';

import 'package:echat_identity/echat_identity.dart';
import 'package:echat_storage/echat_storage.dart';
import 'package:echat_transport/echat_transport.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';

import '../application/messaging_controller.dart';
import '../application/local_profile_service.dart';
import '../application/session_exchange_gateway.dart';
import '../platform/app_local_storage_key_provider.dart';
import '../platform/app_secure_stores.dart';
import '../platform/secure_value_store.dart';
import '../platform/unavailable_packet_transport.dart';

class MobileAppServices {
  MobileAppServices._({
    required this.controller,
    required this.profileService,
    required this.relayConfigurationMessage,
    required this.messageStore,
    required this.isTemporaryLocalMode,
  });

  static const String defaultRelayOrigin = String.fromEnvironment(
    'ECHAT_RELAY_ORIGIN',
  );

  final MessagingController controller;
  final LocalProfileService profileService;
  final String relayConfigurationMessage;
  final EncryptedMessageStore messageStore;
  final bool isTemporaryLocalMode;

  static Future<MobileAppServices> bootstrap({
    Directory? supportDirectory,
    String relayOrigin = defaultRelayOrigin,
    SecureValueStore? secureValueStore,
    EncryptedRecordBackend? messageBackend,
    EncryptedRecordBackend? contactTrustBackend,
    EncryptedRecordBackend? sessionBackend,
    EncryptedRecordBackend? profileBackend,
    PacketTransport? packetTransport,
    SessionExchangeGateway sessionExchangeGateway =
        const UnavailableSessionExchangeGateway(),
  }) async {
    final fallbackSecureStore = _InMemorySecureValueStore();
    try {
      final secureValues =
          secureValueStore ??
          (kIsWeb
              ? fallbackSecureStore
              : FlutterSecureValueStore(storage: const FlutterSecureStorage()));

      if (kIsWeb) {
        final keyProvider = AppLocalStorageKeyProvider(store: secureValues);
        final profileService = LocalProfileService(
          store: EncryptedProfileStore(
            backend: profileBackend ?? MemoryEncryptedRecordBackend(),
            keyProvider: keyProvider.call,
          ),
        );
        final identityService = IdentityService(
          store: AppSecureIdentityStore(secureStore: secureValues),
        );
        final sessionStore = AppSecureSessionStore(
          secureStore: secureValues,
          encryptedRecords: EncryptedSessionRecordStore(
            backend: sessionBackend ?? MemoryEncryptedRecordBackend(),
            keyProvider: keyProvider.call,
          ),
        );
        final sessionService = SessionService(
          identityService: identityService,
          sessionStore: sessionStore,
        );
        final contactTrustStore = EncryptedContactTrustStore(
          backend: MemoryEncryptedRecordBackend(),
          keyProvider: keyProvider.call,
        );
        final messageStore = EncryptedMessageStore(
          backend: MemoryEncryptedRecordBackend(),
          keyProvider: keyProvider.call,
        );
        final configuredTransport = packetTransport == null
            ? await _buildTransport(
                relayOrigin: relayOrigin,
                identityService: identityService,
              )
            : (
                packetTransport,
                'Transport supplied by application composition.',
              );
        final controller = MessagingController(
          identityService: identityService,
          sessionService: sessionService,
          sessionStore: sessionStore,
          contactTrustService: ContactTrustService(store: contactTrustStore),
          messageStore: messageStore,
          packetTransport: configuredTransport.$1,
          sessionExchangeGateway: sessionExchangeGateway,
        );
        return MobileAppServices._(
          controller: controller,
          profileService: profileService,
          relayConfigurationMessage: configuredTransport.$2,
          messageStore: messageStore,
          isTemporaryLocalMode: true,
        );
      }

      final root = supportDirectory ?? await getApplicationSupportDirectory();
      final appDirectory = Directory(
        '${root.path}${Platform.pathSeparator}echat',
      );
      final messageDirectory = Directory(
        '${appDirectory.path}${Platform.pathSeparator}messages',
      );
      final contactDirectory = Directory(
        '${appDirectory.path}${Platform.pathSeparator}contact-trust',
      );
      final sessionDirectory = Directory(
        '${appDirectory.path}${Platform.pathSeparator}sessions',
      );
      final profileDirectory = Directory(
        '${appDirectory.path}${Platform.pathSeparator}profile',
      );
      final keyProvider = AppLocalStorageKeyProvider(store: secureValues);
      final profileService = LocalProfileService(
        store: EncryptedProfileStore(
          backend:
              profileBackend ??
              FileEncryptedRecordBackend(directory: profileDirectory),
          keyProvider: keyProvider.call,
        ),
      );

      final identityService = IdentityService(
        store: AppSecureIdentityStore(secureStore: secureValues),
      );
      final sessionStore = AppSecureSessionStore(
        secureStore: secureValues,
        encryptedRecords: EncryptedSessionRecordStore(
          backend:
              sessionBackend ??
              FileEncryptedRecordBackend(directory: sessionDirectory),
          keyProvider: keyProvider.call,
        ),
      );
      final sessionService = SessionService(
        identityService: identityService,
        sessionStore: sessionStore,
      );
      final contactTrustStore = EncryptedContactTrustStore(
        backend:
            contactTrustBackend ??
            FileEncryptedRecordBackend(directory: contactDirectory),
        keyProvider: keyProvider.call,
      );
      final messageStore = EncryptedMessageStore(
        backend:
            messageBackend ??
            FileEncryptedRecordBackend(directory: messageDirectory),
        keyProvider: keyProvider.call,
      );
      final configuredTransport = packetTransport == null
          ? await _buildTransport(
              relayOrigin: relayOrigin,
              identityService: identityService,
            )
          : (packetTransport, 'Transport supplied by application composition.');
      final trustService = ContactTrustService(store: contactTrustStore);
      final controller = MessagingController(
        identityService: identityService,
        sessionService: sessionService,
        sessionStore: sessionStore,
        contactTrustService: trustService,
        messageStore: messageStore,
        packetTransport: configuredTransport.$1,
        sessionExchangeGateway: sessionExchangeGateway,
      );

      final services = MobileAppServices._(
        controller: controller,
        profileService: profileService,
        relayConfigurationMessage: configuredTransport.$2,
        messageStore: messageStore,
        isTemporaryLocalMode: false,
      );
      final identity = await identityService.loadIdentity();
      if (identity != null) await controller.activateIdentity(identity);
      return services;
    } on Object {
      final fallbackKeyProvider = AppLocalStorageKeyProvider(
        store: fallbackSecureStore,
      );
      final fallbackProfileService = LocalProfileService(
        store: EncryptedProfileStore(
          backend: MemoryEncryptedRecordBackend(),
          keyProvider: fallbackKeyProvider.call,
        ),
      );
      final fallbackIdentityService = IdentityService(
        store: AppSecureIdentityStore(secureStore: fallbackSecureStore),
      );
      final fallbackSessionStore = AppSecureSessionStore(
        secureStore: fallbackSecureStore,
        encryptedRecords: EncryptedSessionRecordStore(
          backend: MemoryEncryptedRecordBackend(),
          keyProvider: fallbackKeyProvider.call,
        ),
      );
      final fallbackSessionService = SessionService(
        identityService: fallbackIdentityService,
        sessionStore: fallbackSessionStore,
      );
      final fallbackContactTrustStore = EncryptedContactTrustStore(
        backend: MemoryEncryptedRecordBackend(),
        keyProvider: fallbackKeyProvider.call,
      );
      final fallbackMessageStore = EncryptedMessageStore(
        backend: MemoryEncryptedRecordBackend(),
        keyProvider: fallbackKeyProvider.call,
      );
      final fallbackController = MessagingController(
        identityService: fallbackIdentityService,
        sessionService: fallbackSessionService,
        sessionStore: fallbackSessionStore,
        contactTrustService: ContactTrustService(
          store: fallbackContactTrustStore,
        ),
        messageStore: fallbackMessageStore,
        packetTransport: UnavailablePacketTransport(
          'secure_storage_unavailable',
        ),
        sessionExchangeGateway: sessionExchangeGateway,
      );
      return MobileAppServices._(
        controller: fallbackController,
        profileService: fallbackProfileService,
        relayConfigurationMessage:
            'Local secure storage unavailable; relay and session exchange remain unavailable.',
        messageStore: fallbackMessageStore,
        isTemporaryLocalMode: true,
      );
    }
  }

  static Future<(PacketTransport, String)> _buildTransport({
    required String relayOrigin,
    required IdentityService identityService,
  }) async {
    final endpointText = relayOrigin.trim();
    if (endpointText.isEmpty) {
      return (
        UnavailablePacketTransport('relay_endpoint_not_configured'),
        'Relay endpoint is not configured.',
      );
    }
    try {
      final endpoint = Uri.parse(endpointText);
      if (endpoint.scheme != 'https' || endpoint.host.isEmpty) {
        return (
          UnavailablePacketTransport('invalid_relay_endpoint'),
          'A valid HTTPS relay origin is required.',
        );
      }
      return (
        HttpsRelayTransport(
          endpoint: endpoint,
          identityService: identityService,
        ),
        'HTTPS relay configured; device registration is required on connect.',
      );
    } on Object {
      return (
        UnavailablePacketTransport('invalid_relay_endpoint'),
        'A valid HTTPS relay origin is required.',
      );
    }
  }
}

class _InMemorySecureValueStore implements SecureValueStore {
  final Map<String, String> _values = <String, String>{};

  @override
  Future<void> delete(String key) async => _values.remove(key);

  @override
  Future<String?> read(String key) async => _values[key];

  @override
  Future<void> write(String key, String value) async => _values[key] = value;
}
