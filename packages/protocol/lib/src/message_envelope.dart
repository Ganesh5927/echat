import 'dart:convert';

class MessageProtocolException implements Exception {
  const MessageProtocolException(this.message);

  final String message;

  @override
  String toString() => 'MessageProtocolException: $message';
}

class MessageEnvelope {
  const MessageEnvelope({
    required this.protocolVersion,
    required this.messageType,
    required this.messageId,
    required this.senderDeviceId,
    required this.recipientDeviceId,
    required this.sessionId,
    required this.sequenceNumber,
    required this.keyEpoch,
    required this.nonce,
    required this.ciphertext,
    required this.authenticationTag,
  });

  static const int currentVersion = 1;
  static const int currentKeyEpoch = 0;
  static final RegExp _uuidV4 = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
    caseSensitive: false,
  );

  final int protocolVersion;
  final String messageType;
  final String messageId;
  final String senderDeviceId;
  final String recipientDeviceId;
  final String sessionId;
  final int sequenceNumber;
  final int keyEpoch;
  final String nonce;
  final String ciphertext;
  final String authenticationTag;

  Map<String, dynamic> _associatedDataObject() => {
    'protocolVersion': protocolVersion,
    'messageType': messageType,
    'messageId': messageId,
    'senderDeviceId': senderDeviceId,
    'recipientDeviceId': recipientDeviceId,
    'sessionId': sessionId,
    'sequenceNumber': sequenceNumber,
    'keyEpoch': keyEpoch,
    'nonce': nonce,
  };

  List<int> get associatedDataBytes {
    _validateHeader();
    return utf8.encode(jsonEncode(_associatedDataObject()));
  }

  Map<String, dynamic> toJson() {
    validate();
    return {
      ..._associatedDataObject(),
      'ciphertext': ciphertext,
      'authenticationTag': authenticationTag,
    };
  }

  String toCanonicalJson() => jsonEncode(toJson());

  factory MessageEnvelope.fromJson(Map<String, dynamic> json) {
    _requireExactKeys(json, const {
      'protocolVersion',
      'messageType',
      'messageId',
      'senderDeviceId',
      'recipientDeviceId',
      'sessionId',
      'sequenceNumber',
      'keyEpoch',
      'nonce',
      'ciphertext',
      'authenticationTag',
    });
    final envelope = MessageEnvelope(
      protocolVersion: _requiredInt(json, 'protocolVersion'),
      messageType: _requiredString(json, 'messageType'),
      messageId: _requiredString(json, 'messageId'),
      senderDeviceId: _requiredString(json, 'senderDeviceId'),
      recipientDeviceId: _requiredString(json, 'recipientDeviceId'),
      sessionId: _requiredString(json, 'sessionId'),
      sequenceNumber: _requiredInt(json, 'sequenceNumber'),
      keyEpoch: _requiredInt(json, 'keyEpoch'),
      nonce: _requiredString(json, 'nonce'),
      ciphertext: _requiredString(json, 'ciphertext'),
      authenticationTag: _requiredString(json, 'authenticationTag'),
    );
    envelope.validate();
    return envelope;
  }

  void validate() {
    _validateHeader();
    _decodeBase64(ciphertext, 'ciphertext');
    _decodeBase64(authenticationTag, 'authentication tag', expectedLength: 16);
  }

  MessageEnvelope withCiphertext({
    required String ciphertext,
    required String authenticationTag,
  }) {
    return MessageEnvelope(
      protocolVersion: protocolVersion,
      messageType: messageType,
      messageId: messageId,
      senderDeviceId: senderDeviceId,
      recipientDeviceId: recipientDeviceId,
      sessionId: sessionId,
      sequenceNumber: sequenceNumber,
      keyEpoch: keyEpoch,
      nonce: nonce,
      ciphertext: ciphertext,
      authenticationTag: authenticationTag,
    );
  }

  MessageEnvelope copyWith({
    int? protocolVersion,
    String? messageType,
    String? messageId,
    String? senderDeviceId,
    String? recipientDeviceId,
    String? sessionId,
    int? sequenceNumber,
    int? keyEpoch,
    String? nonce,
    String? ciphertext,
    String? authenticationTag,
  }) {
    return MessageEnvelope(
      protocolVersion: protocolVersion ?? this.protocolVersion,
      messageType: messageType ?? this.messageType,
      messageId: messageId ?? this.messageId,
      senderDeviceId: senderDeviceId ?? this.senderDeviceId,
      recipientDeviceId: recipientDeviceId ?? this.recipientDeviceId,
      sessionId: sessionId ?? this.sessionId,
      sequenceNumber: sequenceNumber ?? this.sequenceNumber,
      keyEpoch: keyEpoch ?? this.keyEpoch,
      nonce: nonce ?? this.nonce,
      ciphertext: ciphertext ?? this.ciphertext,
      authenticationTag: authenticationTag ?? this.authenticationTag,
    );
  }

  void _validateHeader() {
    if (protocolVersion != currentVersion) {
      throw const MessageProtocolException('Unsupported message version.');
    }
    if (messageType != 'text') {
      throw const MessageProtocolException('Unsupported message type.');
    }
    if (!_uuidV4.hasMatch(messageId) ||
        !_uuidV4.hasMatch(senderDeviceId) ||
        !_uuidV4.hasMatch(recipientDeviceId) ||
        !_uuidV4.hasMatch(sessionId)) {
      throw const MessageProtocolException('Message references are invalid.');
    }
    if (sequenceNumber < 1 || keyEpoch != currentKeyEpoch) {
      throw const MessageProtocolException(
        'Message sequence or epoch is invalid.',
      );
    }
    _decodeBase64(nonce, 'nonce', expectedLength: 12);
  }
}

class TransportMetadata {
  const TransportMetadata({this.routeHint, this.queueId, this.ackId});

  final String? routeHint;
  final String? queueId;
  final String? ackId;

  Map<String, dynamic> toJson() {
    for (final value in [routeHint, queueId, ackId]) {
      if (value != null && value.length > 256) {
        throw const MessageProtocolException(
          'Transport metadata field is too long.',
        );
      }
    }
    return {'routeHint': routeHint, 'queueId': queueId, 'ackId': ackId};
  }

  factory TransportMetadata.fromJson(Map<String, dynamic> json) {
    _requireExactKeys(json, const {'routeHint', 'queueId', 'ackId'});
    return TransportMetadata(
      routeHint: _optionalString(json, 'routeHint'),
      queueId: _optionalString(json, 'queueId'),
      ackId: _optionalString(json, 'ackId'),
    );
  }
}

class TransportPacket {
  static const int maxSerializedBytes = 16 * 1024 * 1024;

  const TransportPacket({
    required this.envelope,
    this.transportMetadata = const TransportMetadata(),
  });

  final MessageEnvelope envelope;
  final TransportMetadata transportMetadata;

  Map<String, dynamic> toJson() => {
    'envelope': envelope.toJson(),
    'transportMetadata': transportMetadata.toJson(),
  };

  String toCanonicalJson() {
    final serialized = jsonEncode(toJson());
    if (utf8.encode(serialized).length > maxSerializedBytes) {
      throw const MessageProtocolException('Serialized packet is too large.');
    }
    return serialized;
  }

  factory TransportPacket.fromJson(String serialized) {
    if (utf8.encode(serialized).length > maxSerializedBytes) {
      throw const MessageProtocolException('Serialized packet is too large.');
    }
    try {
      final decoded = jsonDecode(serialized);
      if (decoded is! Map<String, dynamic>) {
        throw const MessageProtocolException('Packet must be a JSON object.');
      }
      _requireExactKeys(decoded, const {'envelope', 'transportMetadata'});
      final envelopeObject = decoded['envelope'];
      final metadataObject = decoded['transportMetadata'];
      if (envelopeObject is! Map<String, dynamic> ||
          metadataObject is! Map<String, dynamic>) {
        throw const MessageProtocolException('Packet sections are malformed.');
      }
      final packet = TransportPacket(
        envelope: MessageEnvelope.fromJson(envelopeObject),
        transportMetadata: TransportMetadata.fromJson(metadataObject),
      );
      if (packet.toCanonicalJson() != serialized) {
        throw const MessageProtocolException(
          'Packet is not canonically serialized.',
        );
      }
      return packet;
    } on MessageProtocolException {
      rethrow;
    } on Object {
      throw const MessageProtocolException('Serialized packet is malformed.');
    }
  }
}

void _requireExactKeys(Map<String, dynamic> value, Set<String> expected) {
  if (value.length != expected.length ||
      !value.keys.toSet().containsAll(expected)) {
    throw const MessageProtocolException(
      'Object fields do not match the schema.',
    );
  }
}

String _requiredString(Map<String, dynamic> value, String key) {
  final entry = value[key];
  if (entry is! String) {
    throw const MessageProtocolException('A string field is malformed.');
  }
  return entry;
}

String? _optionalString(Map<String, dynamic> value, String key) {
  final entry = value[key];
  if (entry != null && entry is! String) {
    throw const MessageProtocolException('A transport field is malformed.');
  }
  return entry as String?;
}

int _requiredInt(Map<String, dynamic> value, String key) {
  final entry = value[key];
  if (entry is! int) {
    throw const MessageProtocolException('An integer field is malformed.');
  }
  return entry;
}

List<int> _decodeBase64(String value, String field, {int? expectedLength}) {
  try {
    final decoded = base64Decode(value);
    if (base64Encode(decoded) != value ||
        (expectedLength != null && decoded.length != expectedLength)) {
      throw MessageProtocolException('The $field field is invalid.');
    }
    return decoded;
  } on MessageProtocolException {
    rethrow;
  } on Object {
    throw MessageProtocolException('The $field field is malformed.');
  }
}
