import 'dart:convert';
import 'dart:typed_data';

import 'package:echat_transport/echat_transport.dart';
import 'package:shelf/shelf.dart';

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
       ) {
    config.validate();
  }

  final RelayService _service;
  final RelayAuthenticator _authenticator;
  final RelayConfig _config;
  final SlidingWindowRateLimiter _rateLimiter;
  int _activeRequests = 0;

  Handler get handler => call;

  Future<Response> call(Request request) async {
    if (_activeRequests >= _config.maxConcurrentRequests) {
      return _error(503, 'server_busy');
    }
    _activeRequests++;
    try {
      _service.cleanup();
      if (request.method == 'GET' && request.url.path == 'health') {
        return Response.ok(
          jsonEncode({'status': 'ok'}),
          headers: {'content-type': 'application/json'},
        );
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
      if (request.url.path == 'v1/packets') return _error(405, 'method_not_allowed');
      return _error(404, 'not_found');
    } on RelayServiceException catch (error) {
      return _error(error.statusCode, error.code);
    } on Object {
      return _error(500, 'internal_error');
    } finally {
      _activeRequests--;
    }
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
      jsonEncode({'packets': packets.map((packet) => packet.toJson()).toList()}),
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

  Future<List<int>> _readBoundedBody(Request request) async {
    final builder = BytesBuilder(copy: false);
    var size = 0;
    await for (final chunk in request.read()) {
      size += chunk.length;
      if (size > _config.maxRequestBytes) {
        throw const RelayServiceException('request_too_large', 413);
      }
      builder.add(chunk);
    }
    return builder.takeBytes();
  }

  Response _error(int status, String code) => Response(
    status,
    body: jsonEncode({'error': code}),
    headers: {'content-type': 'application/json', 'cache-control': 'no-store'},
  );
}