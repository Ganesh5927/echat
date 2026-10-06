import 'dart:convert';

import 'package:echat_identity/echat_identity.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const EchatIdentityApp());
}

class EchatIdentityApp extends StatelessWidget {
  const EchatIdentityApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'eChat',
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorSchemeSeed: const Color(0xFF5AC8FA),
      ),
      home: const IdentityHomePage(),
    );
  }
}

class IdentityHomePage extends StatefulWidget {
  const IdentityHomePage({super.key});

  @override
  State<IdentityHomePage> createState() => _IdentityHomePageState();
}

class _IdentityHomePageState extends State<IdentityHomePage> {
  late final IdentityService _identityService;
  bool _isLoading = true;
  DeviceIdentity? _identity;

  @override
  void initState() {
    super.initState();
    _identityService = IdentityService(store: AppSecureIdentityStore());
    _loadState();
  }

  Future<void> _loadState() async {
    final identity = await _identityService.loadIdentity();
    if (!mounted) {
      return;
    }
    setState(() {
      _identity = identity;
      _isLoading = false;
    });
  }

  Future<void> _createIdentity() async {
    setState(() => _isLoading = true);
    final identity = await _identityService.createIdentity();
    if (!mounted) {
      return;
    }
    setState(() {
      _identity = identity;
      _isLoading = false;
    });
  }

  Future<void> _deleteIdentity() async {
    setState(() => _isLoading = true);
    await _identityService.deleteIdentity();
    if (!mounted) {
      return;
    }
    setState(() {
      _identity = null;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const SplashScreen();
    }

    if (_identity == null) {
      return CreateIdentityScreen(onCreate: _createIdentity);
    }

    return MyIdentityScreen(
      identity: _identity!,
      fingerprint: _identity!.fingerprint,
      onDelete: _deleteIdentity,
      onRefresh: _loadState,
      service: _identityService,
    );
  }
}

class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.shield_outlined, size: 72),
            SizedBox(height: 24),
            Text(
              'eChat',
              style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 12),
            Text('Loading secure identity…'),
          ],
        ),
      ),
    );
  }
}

class CreateIdentityScreen extends StatelessWidget {
  const CreateIdentityScreen({super.key, required this.onCreate});

  final Future<void> Function() onCreate;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(Icons.fingerprint_rounded, size: 72),
              const SizedBox(height: 24),
              const Text(
                'Create device identity',
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              const Text(
                'This device generates a local cryptographic identity and stores private key material in secure platform storage.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              FilledButton.icon(
                onPressed: () async {
                  await onCreate();
                },
                icon: const Icon(Icons.security_rounded),
                label: const Text('Create Identity'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class MyIdentityScreen extends StatefulWidget {
  const MyIdentityScreen({
    super.key,
    required this.identity,
    required this.fingerprint,
    required this.onDelete,
    required this.onRefresh,
    required this.service,
  });

  final DeviceIdentity identity;
  final String fingerprint;
  final Future<void> Function() onDelete;
  final Future<void> Function() onRefresh;
  final IdentityService service;

  @override
  State<MyIdentityScreen> createState() => _MyIdentityScreenState();
}

class _MyIdentityScreenState extends State<MyIdentityScreen> {
  bool _verified = false;

  @override
  Widget build(BuildContext context) {
    final identityStatus = _verified ? 'IDENTITY VERIFIED' : 'IDENTITY CREATED';
    final qrPayload = widget.service
        .createQrPayload(widget.identity)
        .toQrString();
    final preview = base64Encode(utf8.encode(qrPayload)).substring(0, 32);

    return Scaffold(
      appBar: AppBar(title: const Text('My Identity')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Security Status',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Chip(label: Text(identityStatus)),
                    const SizedBox(height: 16),
                    const Text('Device identity'),
                    const SizedBox(height: 8),
                    Text(widget.identity.deviceId),
                    const SizedBox(height: 16),
                    const Text('Verification fingerprint'),
                    const SizedBox(height: 8),
                    SelectableText(widget.identity.fingerprint),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Public identity representation',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        color: Theme.of(
                          context,
                        ).colorScheme.surfaceContainerHighest,
                      ),
                      child: SelectableText(widget.identity.publicKeyPem),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Safe QR payload (public data only)',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: Theme.of(context).dividerColor,
                        ),
                      ),
                      child: Text('QR placeholder: $preview'),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: FilledButton.tonal(
                    onPressed: () async {
                      setState(() => _verified = true);
                    },
                    child: const Text('Mark Verified'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: () async {
                      await widget.onDelete();
                    },
                    child: const Text('Delete Identity'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextButton.icon(
              onPressed: () async {
                await widget.onRefresh();
              },
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Refresh state'),
            ),
          ],
        ),
      ),
    );
  }
}

class AppSecureIdentityStore implements SecureIdentityStore {
  AppSecureIdentityStore({FlutterSecureStorage? secureStorage})
    : _secureStorage = secureStorage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _secureStorage;
  static const String _privateKeyKey = 'echat.identity.private_key';
  static const String _publicIdentityKey = 'echat.identity.public_identity';

  Future<SharedPreferences> get _prefs async => SharedPreferences.getInstance();

  @override
  Future<void> savePrivateKey(String privateKeyPem) async {
    await _secureStorage.write(key: _privateKeyKey, value: privateKeyPem);
  }

  @override
  Future<String?> loadPrivateKey() async {
    return _secureStorage.read(key: _privateKeyKey);
  }

  @override
  Future<void> savePublicIdentity(Map<String, dynamic> publicIdentity) async {
    final prefs = await _prefs;
    await prefs.setString(_publicIdentityKey, jsonEncode(publicIdentity));
  }

  @override
  Future<Map<String, dynamic>?> loadPublicIdentity() async {
    final prefs = await _prefs;
    final value = prefs.getString(_publicIdentityKey);
    if (value == null || value.isEmpty) {
      return null;
    }
    return jsonDecode(value) as Map<String, dynamic>;
  }

  @override
  Future<void> deleteAll() async {
    final prefs = await _prefs;
    await _secureStorage.delete(key: _privateKeyKey);
    await prefs.remove(_publicIdentityKey);
  }

  @override
  Future<bool> hasIdentity() async {
    final prefs = await _prefs;
    final privateKey = await loadPrivateKey();
    return privateKey != null &&
        privateKey.isNotEmpty &&
        prefs.containsKey(_publicIdentityKey);
  }
}

class AppSecureSessionStore implements SecureSessionStore {
  AppSecureSessionStore({FlutterSecureStorage? secureStorage})
    : _secureStorage = secureStorage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _secureStorage;
  static const String _recordPrefix = 'echat.session.record.';
  static const String _secretPrefix = 'echat.session.secret.';

  Future<SharedPreferences> get _prefs async => SharedPreferences.getInstance();

  @override
  Future<void> saveSessionRecord(String sessionId, SessionRecord record) async {
    final prefs = await _prefs;
    await prefs.setString(
      '$_recordPrefix$sessionId',
      jsonEncode(record.toJson()),
    );
  }

  @override
  Future<SessionRecord?> loadSessionRecord(String sessionId) async {
    final prefs = await _prefs;
    final value = prefs.getString('$_recordPrefix$sessionId');
    if (value == null || value.isEmpty) {
      return null;
    }
    return SessionRecord.fromJson(jsonDecode(value) as Map<String, dynamic>);
  }

  @override
  Future<void> saveSessionSecret(
    String sessionId,
    SessionSecretBundle bundle,
  ) async {
    await _secureStorage.write(
      key: '$_secretPrefix$sessionId',
      value: jsonEncode(bundle.toJson()),
    );
  }

  @override
  Future<SessionSecretBundle?> loadSessionSecret(String sessionId) async {
    final value = await _secureStorage.read(key: '$_secretPrefix$sessionId');
    if (value == null || value.isEmpty) {
      return null;
    }
    return SessionSecretBundle.fromJson(
      jsonDecode(value) as Map<String, dynamic>,
    );
  }

  @override
  Future<void> deleteSession(String sessionId) async {
    final prefs = await _prefs;
    await prefs.remove('$_recordPrefix$sessionId');
    await deleteSessionSecret(sessionId);
  }

  @override
  Future<void> deleteSessionSecret(String sessionId) async {
    await _secureStorage.delete(key: '$_secretPrefix$sessionId');
  }

  @override
  Future<bool> hasSession(String sessionId) async {
    final prefs = await _prefs;
    return prefs.containsKey('$_recordPrefix$sessionId') ||
        await _secureStorage.containsKey(key: '$_secretPrefix$sessionId');
  }
}
