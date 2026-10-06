import 'dart:async';
import 'dart:convert';

import 'package:echat_identity/echat_identity.dart';
import 'package:echat_protocol/echat_protocol.dart';
import 'package:test/test.dart';
import 'package:uuid/uuid.dart';

class _Harness {
  _Harness({
    required this.aDevice,
    required this.bDevice,
    required this.bIdentity,
    required this.aSession,
    required this.bSession,
    required this.aStore,
    required this.bStore,
    required this.aMessages,
    required this.bMessages,
    required this.sessionId,
  });

  final DeviceIdentity aDevice;
  final DeviceIdentity bDevice;
  final IdentityService bIdentity;
  final SessionService aSession;
  final SessionService bSession;
  final MemorySecureSessionStore aStore;
  final MemorySecureSessionStore bStore;
  final MessageService aMessages;
  final MessageService bMessages;
  final String sessionId;

  static Future<_Harness> create() async {
    final aIdentity = IdentityService(store: MemorySecureIdentityStore());
    final bIdentity = IdentityService(store: MemorySecureIdentityStore());
    final aDevice = await aIdentity.createIdentity();
    final bDevice = await bIdentity.createIdentity();
    final aStore = MemorySecureSessionStore();
    final bStore = MemorySecureSessionStore();
    final aSession = SessionService(
      identityService: aIdentity,
      sessionStore: aStore,
    );
    final bSession = SessionService(
      identityService: bIdentity,
      sessionStore: bStore,
    );
    final initiation = await aSession.createSession(
      remoteDeviceId: bDevice.deviceId,
      remoteIdentityPublicKeyPem: bDevice.publicKeyPem,
      localDeviceId: aDevice.deviceId,
    );
    final accepted = await bSession.acceptSession(
      message: initiation,
      localDeviceId: bDevice.deviceId,
      expectedRemoteIdentityPublicKeyPem: aDevice.publicKeyPem,
    );
    await aSession.establishAcceptedSession(
      message: accepted.response,
      localDeviceId: aDevice.deviceId,
    );
    return _Harness(
      aDevice: aDevice,
      bDevice: bDevice,
      bIdentity: bIdentity,
      aSession: aSession,
      bSession: bSession,
      aStore: aStore,
      bStore: bStore,
      aMessages: MessageService(
        sessionService: aSession,
        localDeviceId: aDevice.deviceId,
      ),
      bMessages: MessageService(
        sessionService: bSession,
        localDeviceId: bDevice.deviceId,
      ),
      sessionId: initiation.sessionId,
    );
  }

  Future<TransportPacket> send(String plaintext) {
    return aMessages.sendEncryptedMessage(
      sessionId: sessionId,
      plaintext: plaintext,
    );
  }
}

Future<void> _expectRejected(
  MessageService receiver,
  TransportPacket packet,
) async {
  await _expectRejectedSerialized(receiver, packet.toCanonicalJson());
}

Future<void> _expectRejectedSerialized(
  MessageService receiver,
  String serialized,
) async {
  await expectLater(
    receiver.decryptIncomingMessage(serialized),
    throwsA(isA<MessageProtocolException>()),
  );
}

String _base64Bytes(List<int> bytes) => base64Encode(bytes);

void main() {
  group('MessageService', () {
    test('encrypts and decrypts between the established devices', () async {
      final harness = await _Harness.create();
      final packet = await harness.send('confidential');

      expect(
        await harness.bMessages.decryptIncomingMessage(
          packet.toCanonicalJson(),
        ),
        'confidential',
      );
    });

    test('supports empty messages', () async {
      final harness = await _Harness.create();
      final packet = await harness.send('');

      expect(
        await harness.bMessages.decryptIncomingMessage(
          packet.toCanonicalJson(),
        ),
        '',
      );
    });

    test('supports Unicode messages', () async {
      final harness = await _Harness.create();
      const message = 'こんにちは 🔐 café';
      final packet = await harness.send(message);

      expect(
        await harness.bMessages.decryptIncomingMessage(
          packet.toCanonicalJson(),
        ),
        message,
      );
    });

    test('supports long messages', () async {
      final harness = await _Harness.create();
      final message = 'long-message-λ' * 12000;
      final packet = await harness.send(message);

      expect(
        await harness.bMessages.decryptIncomingMessage(
          packet.toCanonicalJson(),
        ),
        message,
      );
    });

    test('rejects messages beyond the documented plaintext bound', () async {
      final harness = await _Harness.create();
      final before = await harness.aSession.getSession(harness.sessionId);

      await expectLater(
        harness.send('x' * (MessageService.maxPlaintextBytes + 1)),
        throwsA(isA<MessageProtocolException>()),
      );

      final after = await harness.aSession.getSession(harness.sessionId);
      expect(after!.sendSequence, before!.sendSequence);
    });

    test(
      'different messages use different ciphertexts, IDs, and nonces',
      () async {
        final harness = await _Harness.create();
        final first = await harness.send('same plaintext');
        final second = await harness.send('same plaintext');

        expect(first.envelope.ciphertext, isNot(second.envelope.ciphertext));
        expect(first.envelope.messageId, isNot(second.envelope.messageId));
        expect(first.envelope.nonce, isNot(second.envelope.nonce));
      },
    );

    test(
      'transport metadata is separate and does not alter message AAD',
      () async {
        final harness = await _Harness.create();
        final packet = await harness.aMessages.sendEncryptedMessage(
          sessionId: harness.sessionId,
          plaintext: 'transport metadata is not authenticated',
          transportMetadata: const TransportMetadata(routeHint: 'route-a'),
        );
        final forwarded = TransportPacket(
          envelope: packet.envelope,
          transportMetadata: const TransportMetadata(routeHint: 'route-b'),
        );

        expect(
          await harness.bMessages.decryptIncomingMessage(
            forwarded.toCanonicalJson(),
          ),
          'transport metadata is not authenticated',
        );
      },
    );

    test('modified ciphertext is rejected', () async {
      final harness = await _Harness.create();
      final packet = await harness.send('ciphertext tamper');
      final bytes = base64Decode(packet.envelope.ciphertext);
      bytes[0] ^= 1;

      await _expectRejected(
        harness.bMessages,
        TransportPacket(
          envelope: packet.envelope.copyWith(ciphertext: base64Encode(bytes)),
        ),
      );
    });

    test('modified authentication tag is rejected', () async {
      final harness = await _Harness.create();
      final packet = await harness.send('tag tamper');
      final tag = base64Decode(packet.envelope.authenticationTag);
      tag[0] ^= 1;

      await _expectRejected(
        harness.bMessages,
        TransportPacket(
          envelope: packet.envelope.copyWith(
            authenticationTag: base64Encode(tag),
          ),
        ),
      );
    });

    test('modified message ID is rejected', () async {
      final harness = await _Harness.create();
      final packet = await harness.send('message ID tamper');
      await _expectRejected(
        harness.bMessages,
        TransportPacket(
          envelope: packet.envelope.copyWith(messageId: const Uuid().v4()),
        ),
      );
    });

    test('modified sender reference is rejected', () async {
      final harness = await _Harness.create();
      final packet = await harness.send('sender tamper');
      await _expectRejected(
        harness.bMessages,
        TransportPacket(
          envelope: packet.envelope.copyWith(senderDeviceId: const Uuid().v4()),
        ),
      );
    });

    test('modified recipient reference is rejected', () async {
      final harness = await _Harness.create();
      final packet = await harness.send('recipient tamper');
      await _expectRejected(
        harness.bMessages,
        TransportPacket(
          envelope: packet.envelope.copyWith(
            recipientDeviceId: const Uuid().v4(),
          ),
        ),
      );
    });

    test('modified session reference is rejected', () async {
      final harness = await _Harness.create();
      final packet = await harness.send('session tamper');
      await _expectRejected(
        harness.bMessages,
        TransportPacket(
          envelope: packet.envelope.copyWith(sessionId: const Uuid().v4()),
        ),
      );
    });

    test('modified sequence number is rejected', () async {
      final harness = await _Harness.create();
      final packet = await harness.send('sequence tamper');
      await _expectRejected(
        harness.bMessages,
        TransportPacket(
          envelope: packet.envelope.copyWith(
            sequenceNumber: packet.envelope.sequenceNumber + 1,
          ),
        ),
      );
    });

    test('modified protocol version is rejected', () async {
      final harness = await _Harness.create();
      final packet = await harness.send('version tamper');
      final serialized =
          jsonDecode(packet.toCanonicalJson()) as Map<String, dynamic>;
      (serialized['envelope'] as Map<String, dynamic>)['protocolVersion'] = 2;
      await _expectRejectedSerialized(
        harness.bMessages,
        jsonEncode(serialized),
      );
    });

    test('modified message type is rejected', () async {
      final harness = await _Harness.create();
      final packet = await harness.send('type tamper');
      final serialized =
          jsonDecode(packet.toCanonicalJson()) as Map<String, dynamic>;
      (serialized['envelope'] as Map<String, dynamic>)['messageType'] =
          'control';
      await _expectRejectedSerialized(
        harness.bMessages,
        jsonEncode(serialized),
      );
    });

    test('modified nonce and associated data are rejected', () async {
      final harness = await _Harness.create();
      final packet = await harness.send('nonce tamper');
      await _expectRejected(
        harness.bMessages,
        TransportPacket(
          envelope: packet.envelope.copyWith(
            nonce: _base64Bytes(List.filled(12, 8)),
          ),
        ),
      );
    });

    test('a message addressed to another device is rejected', () async {
      final harness = await _Harness.create();
      final packet = await harness.send('wrong recipient');
      final receiverForAnotherDevice = MessageService(
        sessionService: harness.bSession,
        localDeviceId: const Uuid().v4(),
      );

      await _expectRejected(receiverForAnotherDevice, packet);
    });

    test('wrong session is rejected', () async {
      final harness = await _Harness.create();
      final packet = await harness.send('wrong session');
      final receiver = packet.envelope.copyWith(sessionId: const Uuid().v4());

      await _expectRejected(
        harness.bMessages,
        TransportPacket(envelope: receiver),
      );
    });

    test('a different session root key cannot decrypt the message', () async {
      final harness = await _Harness.create();
      final packet = await harness.send('wrong key');
      final secret = await harness.bStore.loadSessionSecret(harness.sessionId);
      await harness.bStore.saveSessionSecret(
        harness.sessionId,
        SessionSecretBundle(
          sessionId: secret!.sessionId,
          sessionKeyHex: List.filled(
            32,
            7,
          ).map((byte) => byte.toRadixString(16).padLeft(2, '0')).join(),
          localEphemeralPrivateKeyBase64: secret.localEphemeralPrivateKeyBase64,
          remoteEphemeralPublicKeyBase64: secret.remoteEphemeralPublicKeyBase64,
          localIdentityPublicKeyPem: secret.localIdentityPublicKeyPem,
          remoteIdentityPublicKeyPem: secret.remoteIdentityPublicKeyPem,
          derivedKeyFingerprint: secret.derivedKeyFingerprint,
          createdAt: secret.createdAt,
          updatedAt: secret.updatedAt,
          seenMessageIds: secret.seenMessageIds,
        ),
      );

      await _expectRejected(harness.bMessages, packet);
    });

    test('truncated ciphertext is rejected', () async {
      final harness = await _Harness.create();
      final packet = await harness.send('truncated ciphertext');
      await _expectRejected(
        harness.bMessages,
        TransportPacket(
          envelope: packet.envelope.copyWith(ciphertext: base64Encode([1])),
        ),
      );
    });

    test(
      'invalid authentication tag length is rejected by the envelope',
      () async {
        final harness = await _Harness.create();
        final packet = await harness.send('short tag');
        expect(
          () => packet.envelope
              .copyWith(authenticationTag: base64Encode([1, 2]))
              .toJson(),
          throwsA(isA<MessageProtocolException>()),
        );
      },
    );

    test('replayed message is rejected', () async {
      final harness = await _Harness.create();
      final packet = await harness.send('replay');
      final serialized = packet.toCanonicalJson();
      expect(
        await harness.bMessages.decryptIncomingMessage(serialized),
        'replay',
      );
      await expectLater(
        harness.bMessages.decryptIncomingMessage(serialized),
        throwsA(isA<MessageProtocolException>()),
      );
    });

    test(
      'sequence gaps are accepted but late earlier packets are rejected',
      () async {
        final harness = await _Harness.create();
        final first = await harness.send('first');
        final second = await harness.send('second');

        expect(
          second.envelope.sequenceNumber,
          first.envelope.sequenceNumber + 1,
        );
        expect(
          await harness.bMessages.decryptIncomingMessage(
            second.toCanonicalJson(),
          ),
          'second',
        );
        await expectLater(
          harness.bMessages.decryptIncomingMessage(first.toCanonicalJson()),
          throwsA(isA<MessageProtocolException>()),
        );
      },
    );

    test('failed authentication does not consume a valid retry', () async {
      final harness = await _Harness.create();
      final packet = await harness.send('retry after tampering');
      final tag = base64Decode(packet.envelope.authenticationTag)..[0] ^= 1;
      final invalid = TransportPacket(
        envelope: packet.envelope.copyWith(
          authenticationTag: base64Encode(tag),
        ),
      );

      await _expectRejected(harness.bMessages, invalid);
      expect(
        await harness.bMessages.decryptIncomingMessage(
          packet.toCanonicalJson(),
        ),
        'retry after tampering',
      );
    });

    test(
      'failed authenticated persistence does not consume a valid retry',
      () async {
        final harness = await _Harness.create();
        final packet = await harness.send('retry after storage failure');
        final serialized = packet.toCanonicalJson();

        await expectLater(
          harness.bMessages.decryptIncomingMessage(
            serialized,
            onAuthenticated: (_, _) async => throw StateError('storage failed'),
          ),
          throwsA(isA<MessageProtocolException>()),
        );
        expect(
          await harness.bMessages.decryptIncomingMessage(serialized),
          'retry after storage failure',
        );
      },
    );

    test('retry resends the identical serialized packet and ID', () async {
      final harness = await _Harness.create();
      final packet = await harness.send('retry me');
      final firstSend = packet.toCanonicalJson();
      final retrySend = packet.toCanonicalJson();

      expect(retrySend, firstSend);
      expect(
        TransportPacket.fromJson(retrySend).envelope.messageId,
        packet.envelope.messageId,
      );
      expect(
        await harness.bMessages.decryptIncomingMessage(firstSend),
        'retry me',
      );
      await expectLater(
        harness.bMessages.decryptIncomingMessage(retrySend),
        throwsA(isA<MessageProtocolException>()),
      );
    });

    test('serialization round trip preserves the packet', () async {
      final harness = await _Harness.create();
      final packet = await harness.send('round trip');
      final serialized = packet.toCanonicalJson();
      final parsed = TransportPacket.fromJson(serialized);

      expect(parsed.toCanonicalJson(), serialized);
      expect(parsed.envelope.messageId, packet.envelope.messageId);
      expect(parsed.envelope.ciphertext, packet.envelope.ciphertext);
      expect(parsed.transportMetadata.routeHint, isNull);
    });

    test(
      'non-canonical serialization and duplicate fields are rejected',
      () async {
        final harness = await _Harness.create();
        final packet = await harness.send('canonical');
        final serialized = packet.toCanonicalJson();
        final duplicate = serialized.replaceFirst(
          '"protocolVersion":1',
          '"protocolVersion":1,"protocolVersion":1',
        );
        final reordered = serialized.replaceFirst(
          '"protocolVersion":1,"messageType":"text"',
          '"messageType":"text","protocolVersion":1',
        );

        expect(
          () => TransportPacket.fromJson(duplicate),
          throwsA(isA<MessageProtocolException>()),
        );
        expect(
          () => TransportPacket.fromJson(reordered),
          throwsA(isA<MessageProtocolException>()),
        );
      },
    );

    test('malformed envelope and unknown fields are rejected', () async {
      final harness = await _Harness.create();
      final packet = await harness.send('malformed');
      final value =
          jsonDecode(packet.toCanonicalJson()) as Map<String, dynamic>;
      (value['envelope'] as Map<String, dynamic>)['unknownRequiredField'] = 1;

      expect(
        () => TransportPacket.fromJson(jsonEncode(value)),
        throwsA(isA<MessageProtocolException>()),
      );
      expect(
        () => TransportPacket.fromJson('{not json'),
        throwsA(isA<MessageProtocolException>()),
      );
    });

    test('unknown protocol version is rejected safely', () async {
      final harness = await _Harness.create();
      final packet = await harness.send('unknown version');

      expect(
        () => packet.envelope.copyWith(protocolVersion: 99).toJson(),
        throwsA(isA<MessageProtocolException>()),
      );
    });

    test('send sequences increase monotonically', () async {
      final harness = await _Harness.create();
      final packets = await Future.wait([
        for (var index = 0; index < 20; index++) harness.send('seq-$index'),
      ]);
      final sequences =
          packets.map((packet) => packet.envelope.sequenceNumber).toList()
            ..sort();

      expect(sequences, List<int>.generate(20, (index) => index + 1));
    });

    test('parallel sends use unique message keys and nonces', () async {
      final harness = await _Harness.create();
      final packets = await Future.wait([
        for (var index = 0; index < 40; index++)
          harness.send('parallel-$index'),
      ]);

      expect(
        packets.map((packet) => packet.envelope.messageId).toSet(),
        hasLength(40),
      );
      expect(
        packets.map((packet) => packet.envelope.nonce).toSet(),
        hasLength(40),
      );
      expect(
        packets.map((packet) => packet.envelope.sequenceNumber).toSet(),
        hasLength(40),
      );
    });

    test('concurrent duplicate receives return plaintext only once', () async {
      final harness = await _Harness.create();
      final packet = await harness.send('concurrent replay');

      Future<Object> attempt() async {
        try {
          return await harness.bMessages.decryptIncomingMessage(
            packet.toCanonicalJson(),
          );
        } on Object catch (error) {
          return error;
        }
      }

      final results = await Future.wait([attempt(), attempt()]);
      expect(results.whereType<String>(), ['concurrent replay']);
      expect(results.whereType<MessageProtocolException>(), hasLength(1));
    });

    test('duplicate receive is serialized across service instances', () async {
      final harness = await _Harness.create();
      final packet = await harness.send('cross-instance replay');
      final secondService = MessageService(
        sessionService: SessionService(
          identityService: harness.bIdentity,
          sessionStore: harness.bStore,
        ),
        localDeviceId: harness.bDevice.deviceId,
      );

      Future<Object> attempt(MessageService receiver) async {
        try {
          return await receiver.decryptIncomingMessage(
            packet.toCanonicalJson(),
          );
        } on Object catch (error) {
          return error;
        }
      }

      final results = await Future.wait([
        attempt(harness.bMessages),
        attempt(secondService),
      ]);
      expect(results.whereType<String>(), ['cross-instance replay']);
      expect(results.whereType<MessageProtocolException>(), hasLength(1));
    });

    test('key derivation is separated by direction', () async {
      final harness = await _Harness.create();
      final aToB = await harness.send('direction one');
      expect(
        await harness.bMessages.decryptIncomingMessage(aToB.toCanonicalJson()),
        'direction one',
      );

      final bToA = await harness.bMessages.sendEncryptedMessage(
        sessionId: harness.sessionId,
        plaintext: 'direction two',
      );
      expect(
        await harness.aMessages.decryptIncomingMessage(bToA.toCanonicalJson()),
        'direction two',
      );
      expect(bToA.envelope.senderDeviceId, harness.bDevice.deviceId);
      expect(bToA.envelope.recipientDeviceId, harness.aDevice.deviceId);
    });

    test('message ID and sequence separate message keys', () async {
      final harness = await _Harness.create();
      final first = await harness.send('same body');
      final second = await harness.send('same body');

      expect(first.envelope.messageId, isNot(second.envelope.messageId));
      expect(
        first.envelope.sequenceNumber,
        isNot(second.envelope.sequenceNumber),
      );
      expect(first.envelope.ciphertext, isNot(second.envelope.ciphertext));
    });

    test(
      'message envelope excludes identity and session secrets and plaintext',
      () async {
        final harness = await _Harness.create();
        const plaintext = 'never-visible-plaintext';
        final packet = await harness.send(plaintext);
        final serialized = packet.toCanonicalJson();
        final json = jsonDecode(serialized) as Map<String, dynamic>;

        expect(serialized, isNot(contains(plaintext)));
        expect(serialized, isNot(contains('sessionKeyHex')));
        expect(serialized, isNot(contains('privateKey')));
        expect(json['envelope'], isNot(contains('transportMetadata')));
        expect(json, isNot(contains('plaintext')));
      },
    );

    test(
      'authentication errors do not disclose plaintext or key material',
      () async {
        final harness = await _Harness.create();
        const plaintext = 'sensitive-error-canary';
        final packet = await harness.send(plaintext);
        final invalid = TransportPacket(
          envelope: packet.envelope.copyWith(
            authenticationTag: base64Encode(List.filled(16, 0)),
          ),
        );
        try {
          await harness.bMessages.decryptIncomingMessage(
            invalid.toCanonicalJson(),
          );
          fail('Expected authentication failure.');
        } on MessageProtocolException catch (error) {
          expect(error.toString(), isNot(contains(plaintext)));
          expect(error.toString(), isNot(contains('sessionKey')));
        }
      },
    );

    test('message operations do not write sensitive values to logs', () async {
      final harness = await _Harness.create();
      final logs = <String>[];
      await runZoned(
        () async {
          await harness.send('log-canary-plaintext');
        },
        zoneSpecification: ZoneSpecification(
          print: (self, parent, zone, line) => logs.add(line),
        ),
      );

      expect(logs, isEmpty);
    });
  });
}
