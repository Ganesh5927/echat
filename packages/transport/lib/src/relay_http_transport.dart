import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:echat_identity/echat_identity.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:meta/meta.dart';

import 'packet_transport.dart';
import 'relay_authentication.dart';

typedef RelayCredentialProvider = Future<String?> Function();

class HttpsRelayTransport implements PacketTransport {
  factory HttpsRelayTransport({
    required Uri endpoint,
    IdentityService? identityService,
    RelayCredentialProvider? credentialProvider,
    Duration requestTimeout = const Duration(seconds: 15),
  }) => HttpsRelayTransport._(
    endpoint: _validateEndpoint(endpoint),
    identityService: identityService,
    credentialProvider: credentialProvider,
    requestTimeout: requestTimeout,
    clientFactory: _createHttpClient,
  );

  @visibleForTesting
  factory HttpsRelayTransport.forTesting({
    required Uri endpoint,
    IdentityService? identityService,
    RelayCredentialProvider? credentialProvider,
    required http.Client Function() clientFactory,
    Duration requestTimeout = const Duration(seconds: 15),
  }) => HttpsRelayTransport._(
    endpoint: _validateEndpoint(endpoint),
    identityService: identityService,
    credentialProvider: credentialProvider,
    requestTimeout: requestTimeout,
    clientFactory: clientFactory,
  );

  HttpsRelayTransport._({
    required Uri endpoint,
    required IdentityService? identityService,
    required RelayCredentialProvider? credentialProvider,
    required this.requestTimeout,
    required http.Client Function() clientFactory,
  }) : _endpoint = endpoint,
       _identityService = identityService,
       _credentialProvider = credentialProvider,
       _httpClientFactory = clientFactory {
    if (requestTimeout <= Duration.zero) {
      throw ArgumentError.value(requestTimeout, 'requestTimeout');
    }
    if ((identityService == null) == (credentialProvider == null)) {
      throw ArgumentError(
        'Provide exactly one of identityService or credentialProvider.',
      );
    }
  }

  final Uri _endpoint;
  final IdentityService? _identityService;
  final RelayCredentialProvider? _credentialProvider;
  final Duration requestTimeout;
  final http.Client Function() _httpClientFactory;
  final StreamController<TransportConnectionState> _stateController =
      StreamController.broadcast(sync: true);
  http.Client? _httpClient;
  String? _bearerToken;
  DateTime? _bearerTokenExpiresAt;
  TransportConnectionState _state = TransportConnectionState.disconnected;

  @override
  TransportConnectionState get connectionState => _state;

  @override
  bool get isAuthenticated =>
      _identityService != null &&
      _bearerToken != null &&
      _bearerTokenExpiresAt?.isAfter(DateTime.now().toUtc()) == true;

  @override
  Stream<TransportConnectionState> get connectionStates =>
      _stateController.stream;

  @override
  Future<void> connect() async {
    if (_state == TransportConnectionState.connected) return;
    _setState(TransportConnectionState.connecting);
    _httpClient ??= _httpClientFactory();
    try {
      final response = await _request('GET', '/health');
      if (response.statusCode != HttpStatus.ok) {
        throw const TransportException('relay_unavailable');
      }
      final value = _decodeObject(response.bodyBytes);
      if (value['status'] != 'ok') {
        throw const TransportException('relay_unavailable');
      }
      final identityService = _identityService;
      if (identityService != null) {
        _setState(TransportConnectionState.authenticating);
        await _registerAndAuthenticate(identityService);
      }
      _setState(TransportConnectionState.connected);
    } on TransportException catch (error) {
      _setState(_failureState(error));
      _closeHttpClient();
      rethrow;
    } on Object {
      _setState(TransportConnectionState.disconnected);
      _closeHttpClient();
      throw const TransportException('relay_unavailable');
    }
  }

  @override
  Future<void> disconnect() async {
    _closeHttpClient();
    _bearerToken = null;
    _bearerTokenExpiresAt = null;
    _setState(TransportConnectionState.disconnected);
  }

  @override
  Future<PacketReceipt> sendPacket(PacketSubmission packet) async {
    _requireConnected();
    final response = await _request(
      'POST',
      '/v1/packets',
      body: jsonEncode(packet.toJson()),
      authenticated: true,
    );
    if (response.statusCode != HttpStatus.accepted &&
        response.statusCode != HttpStatus.ok) {
      throw _statusException(response.statusCode);
    }
    return PacketReceipt.fromJson(_decodeObject(response.bodyBytes));
  }

  @override
  Future<List<DeliveredPacket>> receivePackets() async {
    _requireConnected();
    final response = await _request('GET', '/v1/packets', authenticated: true);
    if (response.statusCode != HttpStatus.ok) {
      throw _statusException(response.statusCode);
    }
    final value = _decodeObject(response.bodyBytes);
    if (value.length != 1 || value['packets'] is! List<dynamic>) {
      throw const TransportException('malformed_relay_response');
    }
    return (value['packets'] as List<dynamic>)
        .map((entry) {
          if (entry is! Map<String, dynamic>) {
            throw const TransportException('malformed_relay_response');
          }
          return DeliveredPacket.fromJson(entry);
        })
        .toList(growable: false);
  }

  @override
  Future<void> acknowledge(String packetId) async {
    _requireConnected();
    PacketSubmission.validateRoute(packetId);
    final response = await _request(
      'POST',
      '/v1/packets/$packetId/acknowledgement',
      authenticated: true,
    );
    if (response.statusCode != HttpStatus.noContent &&
        response.statusCode != HttpStatus.ok) {
      throw _statusException(response.statusCode);
    }
  }

  Future<http.Response> _request(
    String method,
    String path, {
    String? body,
    bool authenticated = false,
    bool allowAuthenticationRefresh = true,
  }) async {
    final client = _httpClient ??= _httpClientFactory();
    final request = http.Request(method, _endpoint.resolve(path));
    request.headers['accept'] = 'application/json';
    if (body != null) {
      request.headers['content-type'] = 'application/json; charset=utf-8';
      request.body = body;
    }
    if (authenticated) {
      final credential = await _authorizationToken();
      if (credential == null || credential.isEmpty) {
        throw const TransportException('transport_authentication_required');
      }
      request.headers[HttpHeaders.authorizationHeader] = 'Bearer $credential';
    }
    try {
      final streamed = await client.send(request).timeout(requestTimeout);
      final bytes = await _readResponse(streamed).timeout(requestTimeout);
      final response = http.Response.bytes(
        bytes,
        streamed.statusCode,
        headers: streamed.headers,
        request: streamed.request,
        reasonPhrase: streamed.reasonPhrase,
      );
      final identityService = _identityService;
      if (authenticated &&
          allowAuthenticationRefresh &&
          response.statusCode == HttpStatus.unauthorized &&
          identityService != null) {
        _bearerToken = null;
        try {
          _setState(TransportConnectionState.authenticating);
          await _registerAndAuthenticate(identityService);
        } on TransportException catch (error) {
          _setState(_failureState(error));
          _closeHttpClient();
          rethrow;
        }
        _setState(TransportConnectionState.connected);
        return _request(
          method,
          path,
          body: body,
          authenticated: true,
          allowAuthenticationRefresh: false,
        );
      }
      return response;
    } on TimeoutException {
      _setState(TransportConnectionState.disconnected);
      _closeHttpClient();
      throw const TransportException('request_timeout');
    } on TransportException {
      rethrow;
    } on Object {
      _setState(TransportConnectionState.disconnected);
      _closeHttpClient();
      throw const TransportException('transport_unavailable');
    }
  }

  Future<String?> _authorizationToken() async {
    if (_identityService != null) return _bearerToken;
    return _credentialProvider!();
  }

  Future<void> _registerAndAuthenticate(IdentityService identityService) async {
    final identity = await identityService.loadIdentity();
    if (identity == null) {
      throw const TransportException('device_identity_required');
    }
    final registerChallenge = await _requestChallenge(
      identity.deviceId,
      'register',
    );
    final registerSignature = await identityService.signIdentityMessage(
      registerChallenge.signedMessage(
        operation: 'register',
        deviceId: identity.deviceId,
      ),
    );
    final registrationResponse = await _postJson('/v1/devices/register', {
      'deviceId': identity.deviceId,
      'publicKeyPem': identity.publicKeyPem,
      'fingerprint': identity.fingerprint,
      'createdAt': identity.createdAt.toUtc().toIso8601String(),
      'challengeId': registerChallenge.challengeId,
      'signature': base64Encode(registerSignature.bytes),
    });
    if (registrationResponse.statusCode != HttpStatus.created &&
        registrationResponse.statusCode != HttpStatus.ok) {
      throw _statusException(registrationResponse.statusCode);
    }

    final authChallenge = await _requestChallenge(
      identity.deviceId,
      'authenticate',
    );
    final authSignature = await identityService.signIdentityMessage(
      authChallenge.signedMessage(
        operation: 'authenticate',
        deviceId: identity.deviceId,
      ),
    );
    final authResponse = await _postJson('/v1/authenticate', {
      'deviceId': identity.deviceId,
      'challengeId': authChallenge.challengeId,
      'signature': base64Encode(authSignature.bytes),
    });
    if (authResponse.statusCode != HttpStatus.ok) {
      throw _statusException(authResponse.statusCode);
    }
    final credential = _decodeObject(authResponse.bodyBytes);
    if (credential.length != 2 ||
        credential['accessToken'] is! String ||
        credential['expiresAt'] is! String) {
      throw const TransportException('malformed_relay_response');
    }
    final token = credential['accessToken'] as String;
    if (!RegExp(r'^[A-Za-z0-9_-]{43}$').hasMatch(token)) {
      throw const TransportException('malformed_relay_response');
    }
    final expiresAt = DateTime.tryParse(credential['expiresAt'] as String);
    if (expiresAt == null || !expiresAt.isAfter(DateTime.now().toUtc())) {
      throw const TransportException('relay_authentication_failed');
    }
    _bearerToken = token;
    _bearerTokenExpiresAt = expiresAt.toUtc();
  }

  Future<RelayAuthChallenge> _requestChallenge(
    String deviceId,
    String operation,
  ) async {
    final response = await _postJson('/v1/auth/challenge', {
      'deviceId': deviceId,
      'operation': operation,
    });
    if (response.statusCode != HttpStatus.ok) {
      throw _statusException(response.statusCode);
    }
    final challenge = RelayAuthChallenge.fromJson(
      _decodeObject(response.bodyBytes),
    );
    if (!challenge.expiresAt.isAfter(DateTime.now().toUtc())) {
      throw const TransportException('relay_authentication_failed');
    }
    return challenge;
  }

  Future<http.Response> _postJson(String path, Map<String, Object?> body) =>
      _request('POST', path, body: jsonEncode(body));

  Future<List<int>> _readResponse(http.StreamedResponse response) async {
    final builder = BytesBuilder(copy: false);
    var total = 0;
    await for (final chunk in response.stream) {
      total += chunk.length;
      if (total > 24 * 1024 * 1024) {
        throw const TransportException('relay_response_too_large');
      }
      builder.add(chunk);
    }
    return builder.takeBytes();
  }

  Map<String, dynamic> _decodeObject(List<int> body) {
    try {
      final decoded = jsonDecode(utf8.decode(body));
      if (decoded is! Map<String, dynamic>) {
        throw const TransportException('malformed_relay_response');
      }
      return decoded;
    } on TransportException {
      rethrow;
    } on Object {
      throw const TransportException('malformed_relay_response');
    }
  }

  TransportException _statusException(int status) =>
      TransportException(switch (status) {
        HttpStatus.unauthorized => 'transport_unauthorized',
        HttpStatus.tooManyRequests => 'rate_limited',
        HttpStatus.requestEntityTooLarge => 'packet_too_large',
        HttpStatus.notFound => 'packet_not_found',
        HttpStatus.conflict => 'packet_conflict',
        _ => 'relay_rejected_request',
      }, statusCode: status);

  void _requireConnected() {
    if (_state != TransportConnectionState.connected) {
      throw const TransportException('transport_not_connected');
    }
  }

  void _setState(TransportConnectionState state) {
    if (_state == state) return;
    _state = state;
    _stateController.add(state);
  }

  TransportConnectionState _failureState(TransportException error) =>
      const {
        'transport_unavailable',
        'request_timeout',
        'relay_unavailable',
      }.contains(error.code)
      ? TransportConnectionState.disconnected
      : TransportConnectionState.authenticationFailed;

  void _closeHttpClient() {
    _httpClient?.close();
    _httpClient = null;
  }

  static Uri _validateEndpoint(Uri endpoint) {
    if (endpoint.scheme != 'https' ||
        endpoint.host.isEmpty ||
        endpoint.userInfo.isNotEmpty ||
        (endpoint.path.isNotEmpty && endpoint.path != '/') ||
        endpoint.hasQuery ||
        endpoint.hasFragment) {
      throw ArgumentError.value(
        endpoint,
        'endpoint',
        'A credential-free HTTPS origin is required.',
      );
    }
    return endpoint;
  }

  static http.Client _createHttpClient() => IOClient(HttpClient());
}
