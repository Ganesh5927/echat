import 'package:flutter/material.dart';

import '../app/mobile_app_services.dart';
import '../application/messaging_controller.dart';
import '../application/messaging_models.dart';
import 'contacts_screen.dart';
import 'conversations_screen.dart';
import 'echat_theme.dart';
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
        _loadError = 'Local identity or session records could not be loaded.';
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
      theme: EchatTheme.dark(),
      home: _loading
          ? const _StartupScreen()
          : _identity == null
          ? _IdentitySetupScreen(
              error: _loadError,
              onCreate: _createIdentity,
              isTemporaryLocalMode: widget.services.isTemporaryLocalMode,
            )
          : _MobileHome(
              controller: _controller,
              identity: _identity!,
              relayConfigurationMessage:
                  widget.services.relayConfigurationMessage,
              isTemporaryLocalMode: widget.services.isTemporaryLocalMode,
              onDeleteIdentity: _deleteIdentity,
              onRefreshIdentity: _loadIdentity,
            ),
    );
  }
}

class _StartupScreen extends StatelessWidget {
  const _StartupScreen();

  @override
  Widget build(BuildContext context) {
    return Material(
      color: EchatColors.background,
      child: Scaffold(
        backgroundColor: EchatColors.background,
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: Padding(
                padding: const EdgeInsets.all(EchatSpacing.xxl),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.shield_outlined,
                      size: 56,
                      color: EchatColors.accent,
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'eChat',
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Preparing secure local messaging…',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: EchatColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 24),
                    const LinearProgressIndicator(
                      minHeight: 5,
                      borderRadius: BorderRadius.all(Radius.circular(99)),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _IdentitySetupScreen extends StatelessWidget {
  const _IdentitySetupScreen({
    required this.error,
    required this.onCreate,
    required this.isTemporaryLocalMode,
  });

  final String? error;
  final Future<void> Function() onCreate;
  final bool isTemporaryLocalMode;

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: EchatColors.background,
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Padding(
            padding: const EdgeInsets.all(EchatSpacing.xxl),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  width: 92,
                  height: 92,
                  decoration: BoxDecoration(
                    color: EchatColors.accent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(28),
                    border: Border.all(color: EchatColors.border),
                  ),
                  child: const Icon(
                    Icons.fingerprint_rounded,
                    size: 48,
                    color: EchatColors.accent,
                  ),
                ),
                const SizedBox(height: 24),
                const Text(
                  'Create device identity',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 28, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 12),
                Text(
                  isTemporaryLocalMode
                      ? echatTemporaryLocalModeDisclosure
                      : 'Private identity material is stored using the platform\'s secure storage.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: isTemporaryLocalMode
                        ? EchatColors.warning
                        : EchatColors.textSecondary,
                    height: 1.4,
                  ),
                ),
                if (error != null) ...[
                  const SizedBox(height: 18),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.errorContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text(
                        error!,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onErrorContainer,
                        ),
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: () => onCreate(),
                  icon: const Icon(Icons.shield_rounded),
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
    required this.isTemporaryLocalMode,
    required this.onDeleteIdentity,
    required this.onRefreshIdentity,
  });

  final MessagingController controller;
  final LocalIdentityView identity;
  final String relayConfigurationMessage;
  final bool isTemporaryLocalMode;
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
        isTemporaryLocalMode: widget.isTemporaryLocalMode,
        onDelete: widget.onDeleteIdentity,
        onRefresh: widget.onRefreshIdentity,
      ),
    ];
    return Scaffold(
      backgroundColor: EchatColors.background,
      body: SafeArea(
        child: IndexedStack(index: _selectedIndex, children: pages),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (index) =>
            setState(() => _selectedIndex = index),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.chat_bubble_outline_rounded),
            selectedIcon: Icon(Icons.chat_bubble_rounded),
            label: 'Conversations',
          ),
          NavigationDestination(
            icon: Icon(Icons.people_outline_rounded),
            selectedIcon: Icon(Icons.people_rounded),
            label: 'Contacts',
          ),
          NavigationDestination(
            icon: Icon(Icons.fingerprint_rounded),
            selectedIcon: Icon(Icons.verified_user_rounded),
            label: 'Identity',
          ),
        ],
      ),
    );
  }
}
