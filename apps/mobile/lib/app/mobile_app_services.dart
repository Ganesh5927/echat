import 'dart:io';

import 'package:echat_identity/echat_identity.dart';
import 'package:echat_storage/echat_storage.dart';
import 'package:echat_transport/echat_transport.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';

import '../application/messaging_controller.dart';
import '../application/session_exchange_gateway.dart';
import '../platform/app_local_storage_key_provider.dart';
import '../platform/app_secure_stores.dart';
import '../platform/secure_value_store.dart';
import '../platform/unavailable_packet_transport.dart';

class MobileAppServices {
  MobileAppServices._({
    required this.controller,
    required this.relayConfigurationMessage,
  });

  static const String relayCredentialStorageKey =
      'echat.relay.bearer_credential';
  static const String defaultRelayOrigin = String.fromEnvironment(
    'ECHAT_RELAY_ORIGIN',
  );

  final MessagingController controller;
  final String relayConfigurationMessage;

  static Future<MobileAppServices> bootstrap({
    Directory? supportDirectory,
    String relayOrigin = defaultRelayOrigin,
    SecureValueStore? secureValueStore,
    EncryptedRecordBackend? messageBackend,
    EncryptedRecordBackend? contactTrustBackend,
    PacketTransport? packetTransport,
    SessionExchangeGateway sessionExchangeGateway =
        const UnavailableSessionExchangeGateway(),
  }) async {
    final secureValues =
        secureValueStore ??
        FlutterSecureValueStore(storage: const FlutterSecureStorage());
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
    final keyProvider = AppLocalStorageKeyProvider(store: secureValues);

    final identityService = IdentityService(
      store: AppSecureIdentityStore(secureStore: secureValues),
    );
    final sessionStore = AppSecureSessionStore(secureStore: secureValues);
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
            secureStore: secureValues,
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
      relayConfigurationMessage: configuredTransport.$2,
    );
    final identity = await identityService.loadIdentity();
    if (identity != null) await controller.activateIdentity(identity);
    return services;
  }

  static Future<(PacketTransport, String)> _buildTransport({
    required String relayOrigin,
    required SecureValueStore secureStore,
  }) async {
    final endpointText = relayOrigin.trim();
    if (endpointText.isEmpty) {
      return (
        UnavailablePacketTransport('relay_endpoint_not_configured'),
        'Relay endpoint is not configured.',
      );
    }
    final credential = await secureStore.read(relayCredentialStorageKey);
    if (credential == null || credential.isEmpty) {
      return (
        UnavailablePacketTransport('relay_credentials_not_configured'),
        'Relay credentials are not configured in secure storage.',
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
          credentialProvider: () => secureStore.read(relayCredentialStorageKey),
        ),
        'HTTPS relay configured.',
      );
    } on Object {
      return (
        UnavailablePacketTransport('invalid_relay_endpoint'),
        'A valid HTTPS relay origin is required.',
      );
    }
  }
}
