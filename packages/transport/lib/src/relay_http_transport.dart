import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:meta/meta.dart';

import 'packet_transport.dart';

typedef RelayCredentialProvider = Future<String?> Function();

class HttpsRelayTransport implements PacketTransport {
  factory HttpsRelayTransport({
    required Uri endpoint,
    required RelayCredentialProvider credentialProvider,
    Duration requestTimeout = const Duration(seconds: 15),
  }) => HttpsRelayTransport._(
    endpoint: _validateEndpoint(endpoint),
    credentialProvider: credentialProvider,
    requestTimeout: requestTimeout,
    clientFactory: _createHttpClient,
  );

  @visibleForTesting
  factory HttpsRelayTransport.forTesting({
    required Uri endpoint,
    required RelayCredentialProvider credentialProvider,
    required http.Client Function() clientFactory,
    Duration requestTimeout = const Duration(seconds: 15),
  }) => HttpsRelayTransport._(
    endpoint: _validateEndpoint(endpoint),
    credentialProvider: credentialProvider,
    requestTimeout: requestTimeout,
    clientFactory: clientFactory,
  );

  HttpsRelayTransport._({
    required Uri endpoint,
    required RelayCredentialProvider credentialProvider,
    required this.requestTimeout,
    required http.Client Function() clientFactory,
  }) : _endpoint = endpoint,
       _credentialProvider = credentialProvider,
       _httpClientFactory = clientFactory {
    if (requestTimeout <= Duration.zero) {
      throw ArgumentError.value(requestTimeout, 'requestTimeout');
    }
  }

  final Uri _endpoint;
  final RelayCredentialProvider _credentialProvider;
  final Duration requestTimeout;
  final http.Client Function() _httpClientFactory;
  final StreamController<TransportConnectionState> _stateController =
      StreamController.broadcast(sync: true);
  http.Client? _httpClient;
  TransportConnectionState _state = TransportConnectionState.disconnected;

  @override
  TransportConnectionState get connectionState => _state;

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
      _setState(TransportConnectionState.connected);
    } on Object {
      _setState(TransportConnectionState.disconnected);
      _closeHttpClient();
      throw const TransportException('relay_unavailable');
    }
  }

  @override
  Future<void> disconnect() async {
    _closeHttpClient();
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
    final response = await _request(
      'GET',
      '/v1/packets',
      authenticated: true,
    );
    if (response.statusCode != HttpStatus.ok) {
      throw _statusException(response.statusCode);
    }
    final value = _decodeObject(response.bodyBytes);
    if (value.length != 1 || value['packets'] is! List<dynamic>) {
      throw const TransportException('malformed_relay_response');
    }
    return (value['packets'] as List<dynamic>).map((entry) {
      if (entry is! Map<String, dynamic>) {
        throw const TransportException('malformed_relay_response');
      }
      return DeliveredPacket.fromJson(entry);
    }).toList(growable: false);
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
  }) async {
    final client = _httpClient ??= _httpClientFactory();
    final request = http.Request(method, _endpoint.resolve(path));
    request.headers['accept'] = 'application/json';
    if (body != null) {
      request.headers['content-type'] = 'application/json; charset=utf-8';
      request.body = body;
    }
    if (authenticated) {
      final credential = await _credentialProvider();
      if (credential == null || credential.isEmpty) {
        throw const TransportException('transport_authentication_required');
      }
      request.headers[HttpHeaders.authorizationHeader] = 'Bearer $credential';
    }
    try {
      final streamed = await client.send(request).timeout(requestTimeout);
      final bytes = await _readResponse(streamed).timeout(requestTimeout);
      return http.Response.bytes(
        bytes,
        streamed.statusCode,
        headers: streamed.headers,
        request: streamed.request,
        reasonPhrase: streamed.reasonPhrase,
      );
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

  TransportException _statusException(int status) => TransportException(
    switch (status) {
      HttpStatus.unauthorized => 'transport_unauthorized',
      HttpStatus.tooManyRequests => 'rate_limited',
      HttpStatus.requestEntityTooLarge => 'packet_too_large',
      HttpStatus.notFound => 'packet_not_found',
      HttpStatus.conflict => 'packet_conflict',
      _ => 'relay_rejected_request',
    },
    statusCode: status,
  );

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