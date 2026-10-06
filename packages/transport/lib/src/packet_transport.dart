import 'dart:convert';
import 'dart:typed_data';

enum TransportConnectionState { disconnected, connecting, connected }

enum RelayPacketState { queued, delivered }

class TransportException implements Exception {
  const TransportException(this.code, {this.statusCode});

  final String code;
  final int? statusCode;

  @override
  String toString() =>
      statusCode == null
          ? 'TransportException: $code'
          : 'TransportException: $code ($statusCode)';
}

class PacketSubmission {
  PacketSubmission({
    this.transportVersion = currentVersion,
    required this.packetId,
    required this.recipientRouteId,
    required this.expiresAt,
    required List<int> encryptedPacket,
  }) : encryptedPacket = List<int>.unmodifiable(
         Uint8List.fromList(encryptedPacket),
       ) {
    _validateRoute(packetId);
    _validateRoute(recipientRouteId);
    if (encryptedPacket.isEmpty ||
        encryptedPacket.length > maxEncryptedPacketBytes) {
      throw const TransportException('invalid_packet_size');
    }
  }

  static const int maxEncryptedPacketBytes = 16 * 1024 * 1024;
  static const int currentVersion = 1;
  static final RegExp _routePattern = RegExp(r'^[A-Za-z0-9_-]{8,128}$');

  final int transportVersion;
  final String packetId;
  final String recipientRouteId;
  final DateTime expiresAt;
  final List<int> encryptedPacket;

  void validate() {
    if (transportVersion != currentVersion) {
      throw const TransportException('unsupported_transport_version');
    }
    _validateRoute(packetId);
    _validateRoute(recipientRouteId);
    if (encryptedPacket.isEmpty ||
        encryptedPacket.length > maxEncryptedPacketBytes) {
      throw const TransportException('invalid_packet_size');
    }
  }

  Map<String, dynamic> toJson() {
    validate();
    return {
      'transportVersion': transportVersion,
      'packetId': packetId,
      'recipientRouteId': recipientRouteId,
      'expiresAt': expiresAt.toUtc().toIso8601String(),
      'encryptedPacket': base64Encode(encryptedPacket),
    };
  }

  factory PacketSubmission.fromJson(Map<String, dynamic> json) {
    _requireKeys(json, const {
      'transportVersion',
      'packetId',
      'recipientRouteId',
      'expiresAt',
      'encryptedPacket',
    });
    try {
      final payload = _string(json, 'encryptedPacket');
      final bytes = base64Decode(payload);
      if (base64Encode(bytes) != payload) {
        throw const TransportException('invalid_packet_encoding');
      }
      if (_int(json, 'transportVersion') != currentVersion) {
        throw const TransportException('unsupported_transport_version');
      }
      return PacketSubmission(
        transportVersion: _int(json, 'transportVersion'),
        packetId: _string(json, 'packetId'),
        recipientRouteId: _string(json, 'recipientRouteId'),
        expiresAt: DateTime.parse(_string(json, 'expiresAt')).toUtc(),
        encryptedPacket: bytes,
      );
    } on TransportException {
      rethrow;
    } on Object {
      throw const TransportException('malformed_packet');
    }
  }

  static void validateRoute(String value) => _validateRoute(value);

  static void _validateRoute(String value) {
    if (!_routePattern.hasMatch(value)) {
      throw const TransportException('invalid_route_reference');
    }
  }
}

class DeliveredPacket {
  DeliveredPacket({
    this.transportVersion = PacketSubmission.currentVersion,
    required this.packetId,
    required this.senderRouteId,
    required this.recipientRouteId,
    required this.createdAt,
    required this.expiresAt,
    required this.state,
    required List<int> encryptedPacket,
  }) : encryptedPacket = List<int>.unmodifiable(
         Uint8List.fromList(encryptedPacket),
       );

  final int transportVersion;
  final String packetId;
  final String senderRouteId;
  final String recipientRouteId;
  final DateTime createdAt;
  final DateTime expiresAt;
  final RelayPacketState state;
  final List<int> encryptedPacket;

  Map<String, dynamic> toJson() => {
    'transportVersion': transportVersion,
    'packetId': packetId,
    'senderRouteId': senderRouteId,
    'recipientRouteId': recipientRouteId,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'expiresAt': expiresAt.toUtc().toIso8601String(),
    'state': state.name,
    'encryptedPacket': base64Encode(encryptedPacket),
  };

  factory DeliveredPacket.fromJson(Map<String, dynamic> json) {
    _requireKeys(json, const {
      'transportVersion',
      'packetId',
      'senderRouteId',
      'recipientRouteId',
      'createdAt',
      'expiresAt',
      'state',
      'encryptedPacket',
    });
    try {
      final encodedPacket = _string(json, 'encryptedPacket');
      final bytes = base64Decode(encodedPacket);
      if (base64Encode(bytes) != encodedPacket ||
          bytes.isEmpty ||
          bytes.length > PacketSubmission.maxEncryptedPacketBytes) {
        throw const TransportException('invalid_packet_encoding');
      }
      if (_int(json, 'transportVersion') != PacketSubmission.currentVersion) {
        throw const TransportException('unsupported_transport_version');
      }
      PacketSubmission.validateRoute(_string(json, 'packetId'));
      PacketSubmission.validateRoute(_string(json, 'senderRouteId'));
      PacketSubmission.validateRoute(_string(json, 'recipientRouteId'));
      final state = RelayPacketState.values.firstWhere(
        (value) => value.name == _string(json, 'state'),
      );
      return DeliveredPacket(
        transportVersion: _int(json, 'transportVersion'),
        packetId: _string(json, 'packetId'),
        senderRouteId: _string(json, 'senderRouteId'),
        recipientRouteId: _string(json, 'recipientRouteId'),
        createdAt: DateTime.parse(_string(json, 'createdAt')).toUtc(),
        expiresAt: DateTime.parse(_string(json, 'expiresAt')).toUtc(),
        state: state,
        encryptedPacket: bytes,
      );
    } on TransportException {
      rethrow;
    } on Object {
      throw const TransportException('malformed_delivery_packet');
    }
  }
}

class PacketReceipt {
  const PacketReceipt({
    required this.packetId,
    required this.state,
    this.queuedAt,
    this.expiresAt,
  });

  final String packetId;
  final String state;
  final DateTime? queuedAt;
  final DateTime? expiresAt;

  factory PacketReceipt.fromJson(Map<String, dynamic> json) {
    _requireKeys(json, const {'packetId', 'state', 'queuedAt', 'expiresAt'});
    final packetId = _string(json, 'packetId');
    PacketSubmission.validateRoute(packetId);
    final state = _string(json, 'state');
    if (!const {
      'queued',
      'duplicate',
      'delivered',
      'acknowledged',
      'expired',
    }.contains(state)) {
      throw const TransportException('invalid_receipt_state');
    }
    return PacketReceipt(
      packetId: packetId,
      state: state,
      queuedAt: _dateTime(json, 'queuedAt'),
      expiresAt: _dateTime(json, 'expiresAt'),
    );
  }
}

abstract interface class PacketTransport {
  TransportConnectionState get connectionState;
  Stream<TransportConnectionState> get connectionStates;

  Future<void> connect();
  Future<void> disconnect();
  Future<PacketReceipt> sendPacket(PacketSubmission packet);
  Future<List<DeliveredPacket>> receivePackets();
  Future<void> acknowledge(String packetId);
}

void _requireKeys(Map<String, dynamic> json, Set<String> keys) {
  if (json.length != keys.length || !json.keys.toSet().containsAll(keys)) {
    throw const TransportException('invalid_schema');
  }
}

String _string(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! String || value.isEmpty) {
    throw const TransportException('invalid_schema');
  }
  return value;
}

int _int(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! int) {
    throw const TransportException('invalid_schema');
  }
  return value;
}

DateTime _dateTime(Map<String, dynamic> json, String key) {
  try {
    return DateTime.parse(_string(json, key)).toUtc();
  } on Object {
    throw const TransportException('invalid_schema');
  }
}