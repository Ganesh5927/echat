import 'dart:async';

import 'package:echat_transport/echat_transport.dart';

class UnavailablePacketTransport implements PacketTransport {
  UnavailablePacketTransport(this.reason);

  final String reason;

  @override
  TransportConnectionState get connectionState =>
      TransportConnectionState.disconnected;

  @override
  Stream<TransportConnectionState> get connectionStates => const Stream.empty();

  TransportException _unavailable() => TransportException(reason);

  @override
  Future<void> connect() async => throw _unavailable();

  @override
  Future<void> disconnect() async {}

  @override
  Future<PacketReceipt> sendPacket(PacketSubmission packet) async =>
      throw _unavailable();

  @override
  Future<List<DeliveredPacket>> receivePackets() async => throw _unavailable();

  @override
  Future<void> acknowledge(String packetId) async => throw _unavailable();
}
