import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:echat_identity/echat_identity.dart';
import 'package:uuid/uuid.dart';

import 'message_envelope.dart';

class MessageService {
  static const int maxPlaintextBytes = 11 * 1024 * 1024;

  MessageService({
    required SessionService sessionService,
    required String localDeviceId,
  }) : _sessionService = sessionService,
       _localDeviceId = localDeviceId;

  final SessionService _sessionService;
  final String _localDeviceId;
  final AesGcm _aead = AesGcm.with256bits(nonceLength: 12);

  Future<SessionRecord?> getSessionRecord(String sessionId) =>
      _sessionService.getSession(sessionId);

  Future<TransportPacket> sendEncryptedMessage({
    required String sessionId,
    required String plaintext,
    TransportMetadata transportMetadata = const TransportMetadata(),
  }) async {
    final messageId = const Uuid().v4();
    final cleartext = utf8.encode(plaintext);
    if (cleartext.length > maxPlaintextBytes) {
      cleartext.fillRange(0, cleartext.length, 0);
      throw const MessageProtocolException('Message is too large.');
    }
    try {
      return await _sessionService.withNextSendMessageKey<TransportPacket>(
        sessionId: sessionId,
        messageId: messageId,
        encryptAndBuild: (messageKey, context) async {
          if (context.senderDeviceId != _localDeviceId) {
            throw const MessageProtocolException(
              'Local device does not match the session sender.',
            );
          }
          try {
            final nonce = _aead.newNonce();
            final header = MessageEnvelope(
              protocolVersion: MessageEnvelope.currentVersion,
              messageType: 'text',
              messageId: messageId,
              senderDeviceId: context.senderDeviceId,
              recipientDeviceId: context.recipientDeviceId,
              sessionId: sessionId,
              sequenceNumber: context.sequence,
              keyEpoch: MessageEnvelope.currentKeyEpoch,
              nonce: base64Encode(nonce),
              ciphertext: '',
              authenticationTag: '',
            );
            final secretBox = await _aead.encrypt(
              cleartext,
              secretKey: messageKey,
              nonce: nonce,
              aad: header.associatedDataBytes,
            );
            return TransportPacket(
              envelope: header.withCiphertext(
                ciphertext: base64Encode(secretBox.cipherText),
                authenticationTag: base64Encode(secretBox.mac.bytes),
              ),
              transportMetadata: transportMetadata,
            );
          } on MessageProtocolException {
            rethrow;
          } on Object {
            throw const MessageProtocolException('Message encryption failed.');
          }
        },
      );
    } finally {
      cleartext.fillRange(0, cleartext.length, 0);
    }
  }

  Future<String> decryptIncomingMessage(
    String serializedPacket, {
    Future<void> Function(String plaintext, TransportPacket packet)?
    onAuthenticated,
  }) async {
    final packet = TransportPacket.fromJson(serializedPacket);
    final envelope = packet.envelope;
    if (envelope.recipientDeviceId != _localDeviceId) {
      throw const MessageProtocolException(
        'Message is addressed to another device.',
      );
    }

    try {
      return await _sessionService.processReceivedMessage<String>(
        sessionId: envelope.sessionId,
        senderDeviceId: envelope.senderDeviceId,
        recipientDeviceId: envelope.recipientDeviceId,
        messageId: envelope.messageId,
        sequence: envelope.sequenceNumber,
        keyEpoch: envelope.keyEpoch,
        authenticateAndDecrypt: (messageKey) async {
          final secretBox = SecretBox(
            base64Decode(envelope.ciphertext),
            nonce: base64Decode(envelope.nonce),
            mac: Mac(base64Decode(envelope.authenticationTag)),
          );
          final cleartext = await _aead.decrypt(
            secretBox,
            secretKey: messageKey,
            aad: envelope.associatedDataBytes,
          );
          try {
            final plaintext = utf8.decode(cleartext);
            await onAuthenticated?.call(plaintext, packet);
            return plaintext;
          } on FormatException {
            throw const MessageProtocolException(
              'Authenticated message text is malformed.',
            );
          } finally {
            cleartext.fillRange(0, cleartext.length, 0);
          }
        },
      );
    } on SessionReplayException {
      throw const MessageProtocolException(
        'Duplicate or stale message rejected.',
      );
    } on SessionValidationException {
      throw const MessageProtocolException(
        'Message session validation failed.',
      );
    } on MessageProtocolException {
      rethrow;
    } on Object {
      throw const MessageProtocolException('Message authentication failed.');
    }
  }
}
