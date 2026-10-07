import 'dart:io';

import 'package:shelf/shelf_io.dart' as shelf_io;

import 'relay_api.dart';

Future<HttpServer> serveRelaySecurely({
  required RelayApi api,
  required InternetAddress address,
  required int port,
  required SecurityContext tlsContext,
}) async {
  if (port < 1 || port > 65535) {
    throw ArgumentError('Relay listener configuration is invalid.');
  }
  await api.initialize();
  final server = await shelf_io.serve(
    api.handler,
    address,
    port,
    securityContext: tlsContext,
    poweredByHeader: null,
  );
  return server;
}
