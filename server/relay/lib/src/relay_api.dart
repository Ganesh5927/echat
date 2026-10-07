import 'dart:convert';
import 'dart:typed_data';

import 'package:echat_transport/echat_transport.dart';
import 'package:shelf/shelf.dart';

import 'relay_device_authenticator.dart';
import 'relay_service.dart';

class RelayApi {
  RelayApi({
    required RelayService service,
    required RelayAuthenticator authenticator,
    required RelayConfig config,
  }) : _service = service,
       _authenticator = authenticator,
       _config = config,
       _rateLimiter = SlidingWindowRateLimiter(
         maxRequests: config.rateLimitRequests,
         window: config.rateLimitWindow,
       ),
       _authRateLimiter = SlidingWindowRateLimiter(
         maxRequests: config.rateLimitRequests,
         window: config.rateLimitWindow,
       ) {
    config.validate();
  }

  final RelayService _service;
  final RelayAuthenticator _authenticator;
  final RelayConfig _config;
  final SlidingWindowRateLimiter _rateLimiter;
  final SlidingWindowRateLimiter _authRateLimiter;
  int _activeRequests = 0;

  Handler get handler => call;

  Future<void> initialize() async {
    await _service.initialize();
    final authenticator = _authenticator;
    if (authenticator is RelayDeviceAuthenticator) {
      await authenticator.initialize();
    }
  }

  Future<Response> call(Request request) async {
    if (_activeRequests >= _config.maxConcurrentRequests) {
      return _error(503, 'server_busy');
    }
    _activeRequests++;
    try {
      await initialize();
      await _service.cleanup();
      if (request.method == 'GET' && request.url.path == 'health') {
        return Response.ok(
          jsonEncode({'status': 'ok'}),
          headers: {'content-type': 'application/json'},
        );
      }

      final deviceAuthenticator = _authenticator;
      if (deviceAuthenticator is RelayDeviceAuthenticator) {
        if (_isAuthenticationRoute(request)) {
          if (!_authRateLimiter.allow('relay-auth')) {
            return _error(429, 'rate_limited');
          }
          return await _handleAuthenticationRequest(
            request,
            deviceAuthenticator,
          );
        }
      }

      final principal = await _authenticator.authenticate(
        request.headers['authorization'],
      );
      if (principal == null) return _error(401, 'unauthorized');
      try {
        PacketSubmission.validateRoute(principal);
      } on TransportException {
        return _error(401, 'unauthorized');
      }
      if (!_rateLimiter.allow(principal)) {
        return _error(429, 'rate_limited');
      }

      if (request.method == 'POST' && request.url.path == 'v1/packets') {
        return await _submit(request, principal);
      }
      if (request.method == 'GET' && request.url.path == 'v1/packets') {
        return await _receive(principal);
      }
      final acknowledgementMatch = RegExp(
        r'^v1/packets/([A-Za-z0-9_-]{8,128})/acknowledgement$',
      ).firstMatch(request.url.path);
      if (request.method == 'POST' && acknowledgementMatch != null) {
        return await _acknowledge(principal, acknowledgementMatch.group(1)!);
      }
      if (request.url.path == 'v1/packets') {
        return _error(405, 'method_not_allowed');
      }
      return _error(404, 'not_found');
    } on RelayServiceException catch (error) {
      return _error(error.statusCode, error.code);
    } on RelayAuthenticationException catch (error) {
      return _error(error.statusCode, error.code);
    } on Object {
      return _error(500, 'internal_error');
    } finally {
      _activeRequests--;
    }
  }

  bool _isAuthenticationRoute(Request request) =>
      request.method == 'POST' &&
      const {
        'v1/auth/challenge',
        'v1/devices/register',
        'v1/authenticate',
      }.contains(request.url.path);

  Future<Response> _handleAuthenticationRequest(
    Request request,
    RelayDeviceAuthenticator authenticator,
  ) async {
    switch (request.url.path) {
      case 'v1/auth/challenge':
        return _issueChallenge(request, authenticator);
      case 'v1/devices/register':
        return _registerDevice(request, authenticator);
      case 'v1/authenticate':
        return _authenticateDevice(request, authenticator);
    }
    return _error(404, 'not_found');
  }

  Future<Response> _issueChallenge(
    Request request,
    RelayDeviceAuthenticator authenticator,
  ) async {
    final json = await _readJsonObject(request, maxBytes: 16 * 1024);
    if (json == null ||
        json.length != 2 ||
        !json.keys.toSet().containsAll(const {'deviceId', 'operation'}) ||
        json['deviceId'] is! String ||
        json['operation'] is! String) {
      return _error(400, 'malformed_auth_request');
    }
    final challenge = await authenticator.issueChallenge(
      deviceId: json['deviceId'] as String,
      operation: json['operation'] as String,
    );
    return Response.ok(
      jsonEncode({
        'challengeId': challenge.challengeId,
        'nonce': challenge.nonce,
        'expiresAt': challenge.expiresAt.toUtc().toIso8601String(),
      }),
      headers: _privateJsonHeaders,
    );
  }

  Future<Response> _registerDevice(
    Request request,
    RelayDeviceAuthenticator authenticator,
  ) async {
    final json = await _readJsonObject(request, maxBytes: 16 * 1024);
    const fields = {
      'deviceId',
      'publicKeyPem',
      'fingerprint',
      'createdAt',
      'challengeId',
      'signature',
    };
    if (json == null ||
        json.length != fields.length ||
        !json.keys.toSet().containsAll(fields) ||
        fields.any((field) => json[field] is! String)) {
      return _error(400, 'malformed_registration');
    }
    final createdAt = DateTime.tryParse(json['createdAt'] as String);
    if (createdAt == null) return _error(400, 'malformed_registration');
    await authenticator.registerDevice(
      deviceId: json['deviceId'] as String,
      publicKeyPem: json['publicKeyPem'] as String,
      fingerprint: json['fingerprint'] as String,
      createdAt: createdAt.toUtc(),
      challengeId: json['challengeId'] as String,
      signature: json['signature'] as String,
    );
    return Response(
      201,
      body: jsonEncode({'deviceId': json['deviceId'], 'state': 'registered'}),
      headers: _privateJsonHeaders,
    );
  }

  Future<Response> _authenticateDevice(
    Request request,
    RelayDeviceAuthenticator authenticator,
  ) async {
    final json = await _readJsonObject(request, maxBytes: 16 * 1024);
    const fields = {'deviceId', 'challengeId', 'signature'};
    if (json == null ||
        json.length != fields.length ||
        !json.keys.toSet().containsAll(fields) ||
        fields.any((field) => json[field] is! String)) {
      return _error(400, 'malformed_auth_request');
    }
    final credential = await authenticator.authenticateDevice(
      deviceId: json['deviceId'] as String,
      challengeId: json['challengeId'] as String,
      signature: json['signature'] as String,
    );
    return Response.ok(
      jsonEncode({
        'accessToken': credential.token,
        'expiresAt': credential.expiresAt.toUtc().toIso8601String(),
      }),
      headers: _privateJsonHeaders,
    );
  }

  Future<Response> _submit(Request request, String senderRouteId) async {
    if (request.contentLength != null &&
        request.contentLength! > _config.maxRequestBytes) {
      return _error(413, 'request_too_large');
    }
    if (request.mimeType != 'application/json') {
      return _error(415, 'unsupported_media_type');
    }
    final body = await _readBoundedBody(request);
    final Map<String, dynamic> json;
    try {
      final decoded = jsonDecode(utf8.decode(body));
      if (decoded is! Map<String, dynamic>) {
        return _error(400, 'malformed_packet');
      }
      json = decoded;
    } on Object {
      return _error(400, 'malformed_packet');
    }
    final PacketSubmission packet;
    try {
      packet = PacketSubmission.fromJson(json);
    } on TransportException catch (error) {
      if (error.code == 'invalid_packet_size') {
        return _error(413, 'packet_too_large');
      }
      return _error(400, error.code);
    }
    if (!await _authenticator.isRegisteredDeviceRoute(
      packet.recipientRouteId,
    )) {
      return _error(404, 'recipient_not_registered');
    }
    if (utf8.encode(base64Encode(packet.encryptedPacket)).length + 1024 >
        _config.maxRequestBytes) {
      return _error(413, 'request_too_large');
    }
    final result = await _service.submit(
      authenticatedSenderRouteId: senderRouteId,
      packet: packet,
    );
    return Response(
      result.state == 'queued' ? 202 : 200,
      body: jsonEncode(result.toJson()),
      headers: {'content-type': 'application/json'},
    );
  }

  Future<Response> _receive(String recipientRouteId) async {
    final packets = await _service.receive(
      authenticatedRecipientRouteId: recipientRouteId,
    );
    return Response.ok(
      jsonEncode({
        'packets': packets.map((packet) => packet.toJson()).toList(),
      }),
      headers: {'content-type': 'application/json'},
    );
  }

  Future<Response> _acknowledge(
    String recipientRouteId,
    String packetId,
  ) async {
    try {
      PacketSubmission.validateRoute(packetId);
    } on TransportException {
      return _error(404, 'packet_not_found');
    }
    final result = await _service.acknowledge(
      authenticatedRecipientRouteId: recipientRouteId,
      packetId: packetId,
    );
    return Response.ok(
      jsonEncode(result.toJson()),
      headers: {'content-type': 'application/json'},
    );
  }

  Future<Map<String, dynamic>?> _readJsonObject(
    Request request, {
    required int maxBytes,
  }) async {
    if (request.contentLength != null && request.contentLength! > maxBytes) {
      throw const RelayServiceException('request_too_large', 413);
    }
    if (request.mimeType != 'application/json') return null;
    final body = await _readBoundedBody(request, maxBytes: maxBytes);
    try {
      final decoded = jsonDecode(utf8.decode(body));
      return decoded is Map<String, dynamic> ? decoded : null;
    } on Object {
      return null;
    }
  }

  Future<List<int>> _readBoundedBody(Request request, {int? maxBytes}) async {
    final limit = maxBytes ?? _config.maxRequestBytes;
    final builder = BytesBuilder(copy: false);
    var size = 0;
    await for (final chunk in request.read()) {
      size += chunk.length;
      if (size > limit) {
        throw const RelayServiceException('request_too_large', 413);
      }
      builder.add(chunk);
    }
    return builder.takeBytes();
  }

  static const _privateJsonHeaders = {
    'content-type': 'application/json',
    'cache-control': 'no-store',
  };

  Response _error(int status, String code) => Response(
    status,
    body: jsonEncode({'error': code}),
    headers: _privateJsonHeaders,
  );
}
