import 'package:flutter/material.dart';

import '../app/mobile_app_services.dart';
import '../application/messaging_controller.dart';
import '../application/messaging_models.dart';
import 'contacts_screen.dart';
import 'conversations_screen.dart';
import 'identity_screen.dart';

class EchatApp extends StatefulWidget {
  const EchatApp({super.key, required this.services});

  final MobileAppServices services;

  @override
  State<EchatApp> createState() => _EchatAppState();
}

class _EchatAppState extends State<EchatApp> {
  LocalIdentityView? _identity;
  String? _loadError;
  bool _loading = true;

  MessagingController get _controller => widget.services.controller;

  @override
  void initState() {
    super.initState();
    _loadIdentity();
  }

  Future<void> _loadIdentity() async {
    try {
      final identity = await _controller.loadLocalIdentity();
      if (!mounted) return;
      setState(() {
        _identity = identity;
        _loadError = null;
        _loading = false;
      });
    } on Object {
      if (!mounted) return;
      setState(() {
        _loadError = 'Identity storage is unavailable.';
        _loading = false;
      });
    }
  }

  Future<void> _createIdentity() async {
    setState(() => _loading = true);
    try {
      final identity = await _controller.createLocalIdentity();
      if (!mounted) return;
      setState(() {
        _identity = identity;
        _loadError = null;
        _loading = false;
      });
    } on Object {
      if (!mounted) return;
      setState(() {
        _loadError = 'Identity could not be created securely.';
        _loading = false;
      });
    }
  }

  Future<void> _deleteIdentity() async {
    await _controller.deleteLocalIdentity();
    if (!mounted) return;
    setState(() => _identity = null);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'eChat',
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorSchemeSeed: const Color(0xFF5AC8FA),
      ),
      home: _loading
          ? const _StartupScreen()
          : _identity == null
          ? _IdentitySetupScreen(error: _loadError, onCreate: _createIdentity)
          : _MobileHome(
              controller: _controller,
              identity: _identity!,
              relayConfigurationMessage:
                  widget.services.relayConfigurationMessage,
              onDeleteIdentity: _deleteIdentity,
              onRefreshIdentity: _loadIdentity,
            ),
    );
  }
}

class _StartupScreen extends StatelessWidget {
  const _StartupScreen();

  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Center(child: CircularProgressIndicator()));
}

class _IdentitySetupScreen extends StatelessWidget {
  const _IdentitySetupScreen({required this.error, required this.onCreate});

  final String? error;
  final Future<void> Function() onCreate;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(Icons.shield_outlined, size: 56),
                const SizedBox(height: 20),
                const Text(
                  'Create device identity',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 26, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Private identity material stays in platform secure storage.',
                  textAlign: TextAlign.center,
                ),
                if (error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: () => onCreate(),
                  icon: const Icon(Icons.fingerprint),
                  label: const Text('Create Identity'),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class _MobileHome extends StatefulWidget {
  const _MobileHome({
    required this.controller,
    required this.identity,
    required this.relayConfigurationMessage,
    required this.onDeleteIdentity,
    required this.onRefreshIdentity,
  });

  final MessagingController controller;
  final LocalIdentityView identity;
  final String relayConfigurationMessage;
  final Future<void> Function() onDeleteIdentity;
  final Future<void> Function() onRefreshIdentity;

  @override
  State<_MobileHome> createState() => _MobileHomeState();
}

class _MobileHomeState extends State<_MobileHome> {
  int _selectedIndex = 0;

  @override
  Widget build(BuildContext context) {
    final pages = [
      ConversationsScreen(controller: widget.controller),
      ContactsScreen(controller: widget.controller),
      IdentityScreen(
        identity: widget.identity,
        relayConfigurationMessage: widget.relayConfigurationMessage,
        onDelete: widget.onDeleteIdentity,
        onRefresh: widget.onRefreshIdentity,
      ),
    ];
    return Scaffold(
      body: SafeArea(
        child: IndexedStack(index: _selectedIndex, children: pages),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (index) =>
            setState(() => _selectedIndex = index),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.chat_bubble_outline),
            selectedIcon: Icon(Icons.chat_bubble),
            label: 'Chats',
          ),
          NavigationDestination(
            icon: Icon(Icons.people_outline),
            selectedIcon: Icon(Icons.people),
            label: 'Contacts',
          ),
          NavigationDestination(
            icon: Icon(Icons.fingerprint),
            selectedIcon: Icon(Icons.verified_user),
            label: 'Identity',
          ),
        ],
      ),
    );
  }
}
