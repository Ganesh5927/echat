import 'package:flutter/material.dart';

import '../app/mobile_app_services.dart';
import '../application/local_profile_service.dart';
import '../application/messaging_controller.dart';
import '../application/messaging_models.dart';
import '../application/theme_preferences.dart';
import 'contacts_screen.dart';
import 'conversations_screen.dart';
import 'echat_theme.dart';
import 'identity_screen.dart';
import 'onboarding_screen.dart';
import 'profile_screen.dart';
import 'settings_screen.dart';

class EchatApp extends StatefulWidget {
  const EchatApp({super.key, required this.services});

  final MobileAppServices services;

  @override
  State<EchatApp> createState() => _EchatAppState();
}

class _EchatAppState extends State<EchatApp> with WidgetsBindingObserver {
  LocalIdentityView? _identity;
  String? _loadError;
  bool _loading = true;
  bool _identityLoadFailed = false;
  bool _identityCreatedDuringOnboarding = false;
  final ThemePreferenceStore _themePreferenceStore = ThemePreferenceStore();
  ThemePreference _themePreference = ThemePreference.defaults;
  bool _themePreferenceLoadFailed = false;

  MessagingController get _controller => widget.services.controller;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadIdentity();
    _loadThemePreference();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangePlatformBrightness() {
    if (_themePreference.mode == EchatThemeMode.system && mounted) {
      setState(() {});
    }
  }

  Future<void> _loadThemePreference() async {
    try {
      final preference = await _themePreferenceStore.load();
      if (!mounted) return;
      setState(() {
        _themePreference = preference;
        _themePreferenceLoadFailed = false;
      });
    } on Object {
      if (!mounted) return;
      setState(() => _themePreferenceLoadFailed = true);
    }
  }

  Future<void> _changeThemePreference(ThemePreference preference) async {
    setState(() {
      _themePreference = preference;
      _themePreferenceLoadFailed = false;
    });
    try {
      await _themePreferenceStore.save(preference);
    } on Object {
      if (mounted) setState(() => _themePreferenceLoadFailed = true);
      rethrow;
    }
  }

  Future<void> _loadIdentity() async {
    try {
      final identity = await _controller.loadLocalIdentity();
      if (!mounted) return;
      setState(() {
        _identity = identity;
        _loadError = null;
        _identityLoadFailed = false;
        _loading = false;
        _identityCreatedDuringOnboarding = false;
      });
    } on Object {
      if (!mounted) return;
      setState(() {
        _loadError = 'Local identity or session records could not be loaded.';
        _identityLoadFailed = true;
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
        _identityLoadFailed = false;
        _loading = false;
        _identityCreatedDuringOnboarding = true;
      });
    } on Object {
      if (!mounted) return;
      setState(() {
        _loadError = 'Identity could not be created securely.';
        _identityLoadFailed = false;
        _loading = false;
      });
    }
  }

  Future<void> _deleteIdentity() async {
    await _controller.deleteLocalIdentity();
    if (!mounted) return;
    setState(() {
      _identity = null;
      _identityCreatedDuringOnboarding = false;
    });
  }

  void _continueAfterOnboarding() {
    setState(() => _identityCreatedDuringOnboarding = false);
  }

  Future<void> _retryIdentityLoad() async {
    setState(() => _loading = true);
    await _loadIdentity();
  }

  @override
  Widget build(BuildContext context) {
    final theme = EchatTheme.themed(
      mode: _themePreference.mode,
      accent: _themePreference.accent,
      systemBrightness:
          WidgetsBinding.instance.platformDispatcher.platformBrightness,
    );
    return MaterialApp(
      title: 'eChat',
      theme: theme,
      themeMode: ThemeMode.light,
      home: _loading
          ? const _StartupScreen()
          : _identity == null || _identityCreatedDuringOnboarding
          ? OnboardingScreen(
              error: _loadError,
              identityLoadFailed: _identityLoadFailed,
              hasCreatedIdentity: _identityCreatedDuringOnboarding,
              onCreateIdentity: _createIdentity,
              onRetryIdentityLoad: _retryIdentityLoad,
              onContinue: _continueAfterOnboarding,
              isTemporaryLocalMode: widget.services.isTemporaryLocalMode,
            )
          : _MobileHome(
              controller: _controller,
              identity: _identity!,
              relayConfigurationMessage:
                  widget.services.relayConfigurationMessage,
              isTemporaryLocalMode: widget.services.isTemporaryLocalMode,
              profileService: widget.services.profileService,
              themePreference: _themePreference,
              themePreferenceLoadFailed: _themePreferenceLoadFailed,
              onThemePreferenceChanged: _changeThemePreference,
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
                    Icon(
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

class _MobileHome extends StatefulWidget {
  const _MobileHome({
    required this.controller,
    required this.identity,
    required this.relayConfigurationMessage,
    required this.isTemporaryLocalMode,
    required this.profileService,
    required this.themePreference,
    required this.themePreferenceLoadFailed,
    required this.onThemePreferenceChanged,
    required this.onDeleteIdentity,
    required this.onRefreshIdentity,
  });

  final MessagingController controller;
  final LocalIdentityView identity;
  final String relayConfigurationMessage;
  final bool isTemporaryLocalMode;
  final LocalProfileService profileService;
  final ThemePreference themePreference;
  final bool themePreferenceLoadFailed;
  final Future<void> Function(ThemePreference) onThemePreferenceChanged;
  final Future<void> Function() onDeleteIdentity;
  final Future<void> Function() onRefreshIdentity;

  @override
  State<_MobileHome> createState() => _MobileHomeState();
}

class _MobileHomeState extends State<_MobileHome> {
  int _selectedIndex = 0;

  @override
  Widget build(BuildContext context) {
    Future<void> openIdentity() async {
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => IdentityScreen(
            identity: widget.identity,
            relayConfigurationMessage: widget.relayConfigurationMessage,
            isTemporaryLocalMode: widget.isTemporaryLocalMode,
            onDelete: widget.onDeleteIdentity,
            onRefresh: widget.onRefreshIdentity,
          ),
        ),
      );
      await widget.onRefreshIdentity();
    }

    Future<void> openContacts() async {
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => ContactsScreen(controller: widget.controller),
        ),
      );
    }

    Future<void> openProfile() async {
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => ProfileScreen(
            profileService: widget.profileService,
            isTemporaryLocalMode: widget.isTemporaryLocalMode,
          ),
        ),
      );
    }

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
      SettingsScreen(
        controller: widget.controller,
        identity: widget.identity,
        relayConfigurationMessage: widget.relayConfigurationMessage,
        isTemporaryLocalMode: widget.isTemporaryLocalMode,
        onOpenIdentity: openIdentity,
        onOpenContacts: openContacts,
        onOpenProfile: openProfile,
        themePreference: widget.themePreference,
        themePreferenceLoadFailed: widget.themePreferenceLoadFailed,
        onThemePreferenceChanged: widget.onThemePreferenceChanged,
      ),
    ];
    return PopScope(
      canPop: _selectedIndex == 0,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && _selectedIndex != 0) {
          setState(() => _selectedIndex = 0);
        }
      },
      child: Scaffold(
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
            NavigationDestination(
              icon: Icon(Icons.settings_outlined),
              selectedIcon: Icon(Icons.settings_rounded),
              label: 'Settings',
            ),
          ],
        ),
      ),
    );
  }
}
