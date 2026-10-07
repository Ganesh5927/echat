import 'dart:async';

import 'package:echat_transport/echat_transport.dart';
import 'package:flutter/material.dart';

import '../application/theme_preferences.dart';
import '../application/messaging_controller.dart';
import '../application/messaging_models.dart';
import 'echat_theme.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    required this.controller,
    required this.identity,
    required this.relayConfigurationMessage,
    required this.isTemporaryLocalMode,
    required this.onOpenIdentity,
    required this.onOpenContacts,
    required this.onOpenProfile,
    required this.themePreference,
    required this.themePreferenceLoadFailed,
    required this.onThemePreferenceChanged,
  });

  final MessagingController controller;
  final LocalIdentityView identity;
  final String relayConfigurationMessage;
  final bool isTemporaryLocalMode;
  final Future<void> Function() onOpenIdentity;
  final Future<void> Function() onOpenContacts;
  final Future<void> Function() onOpenProfile;
  final ThemePreference themePreference;
  final bool themePreferenceLoadFailed;
  final Future<void> Function(ThemePreference) onThemePreferenceChanged;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late Future<_SettingsData> _data;
  StreamSubscription<TransportConnectionState>? _connectionSubscription;

  @override
  void initState() {
    super.initState();
    _data = _loadData();
    _listenForConnectionChanges();
  }

  @override
  void didUpdateWidget(covariant SettingsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      _data = _loadData();
      _connectionSubscription?.cancel();
      _listenForConnectionChanges();
    }
  }

  void _listenForConnectionChanges() {
    _connectionSubscription = widget.controller.connectionStates.listen((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _connectionSubscription?.cancel();
    super.dispose();
  }

  Future<_SettingsData> _loadData() async {
    final values = await Future.wait<Object>([
      widget.controller.contacts(),
      widget.controller.conversations(),
    ]);
    return _SettingsData(
      contacts: values[0] as List<AppContact>,
      conversations: values[1] as List<AppConversation>,
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: EchatColors.background,
    appBar: AppBar(
      title: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: EchatColors.accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              Icons.shield_rounded,
              size: 20,
              color: EchatColors.accent,
            ),
          ),
          const SizedBox(width: EchatSpacing.md),
          const Text('eChat'),
        ],
      ),
    ),
    body: FutureBuilder<_SettingsData>(
      future: _data,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(EchatSpacing.xl),
              child: Text('Settings could not load local account information.'),
            ),
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        return _buildContent(context, snapshot.data!);
      },
    ),
  );

  Widget _buildContent(BuildContext context, _SettingsData data) {
    final connection = _connectionSummary(widget.controller.connectionStatus);
    final trustCounts = _trustCounts(data.contacts);
    final sessionSummary = _sessionSummary(data.conversations);
    final pendingCount = data.conversations.fold<int>(
      0,
      (count, conversation) => count + conversation.pendingMessageCount,
    );

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
        EchatSpacing.lg,
        EchatSpacing.sm,
        EchatSpacing.lg,
        EchatSpacing.xxl,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Settings',
            style: Theme.of(
              context,
            ).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: EchatSpacing.xs),
          Text(
            'Manage your identity, privacy, and local messaging setup.',
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: EchatColors.textSecondary),
          ),
          const SizedBox(height: EchatSpacing.lg),
          _SettingsSection(
            title: 'My Profile',
            icon: Icons.person_outline_rounded,
            children: [
              _SettingsTile(
                icon: Icons.account_circle_outlined,
                title: 'Display name and avatar',
                subtitle: 'Edit your local profile',
                semanticLabel: 'Open My Profile',
                onTap: widget.onOpenProfile,
              ),
            ],
          ),
          _SettingsSection(
            title: 'Appearance',
            icon: Icons.palette_outlined,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: EchatSpacing.md,
                  vertical: EchatSpacing.sm,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Semantics(
                      label: 'Theme mode',
                      child: DropdownButtonFormField<EchatThemeMode>(
                        key: const Key('appearance-theme-mode'),
                        initialValue: widget.themePreference.mode,
                        isExpanded: true,
                        decoration: const InputDecoration(labelText: 'Theme'),
                        items: EchatThemeMode.values
                            .map(
                              (mode) => DropdownMenuItem(
                                value: mode,
                                child: Text(_themeModeLabel(mode)),
                              ),
                            )
                            .toList(growable: false),
                        onChanged: (mode) {
                          if (mode != null) {
                            _applyThemePreference(
                              widget.themePreference.copyWith(mode: mode),
                            );
                          }
                        },
                      ),
                    ),
                    const SizedBox(height: EchatSpacing.md),
                    Semantics(
                      label: 'Accent color',
                      child: DropdownButtonFormField<EchatAccent>(
                        key: const Key('appearance-accent'),
                        initialValue: widget.themePreference.accent,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Accent color',
                        ),
                        items: EchatAccent.values
                            .map(
                              (accent) => DropdownMenuItem(
                                value: accent,
                                child: Text(_accentLabel(accent)),
                              ),
                            )
                            .toList(growable: false),
                        onChanged: (accent) {
                          if (accent != null) {
                            _applyThemePreference(
                              widget.themePreference.copyWith(accent: accent),
                            );
                          }
                        },
                      ),
                    ),
                    if (widget.themePreferenceLoadFailed) ...[
                      const SizedBox(height: EchatSpacing.sm),
                      Text(
                        'Appearance could not be saved. The current selection is active for this session.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: EchatColors.warning,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          _SettingsSection(
            title: 'My Identity',
            icon: Icons.fingerprint_rounded,
            children: [
              _SettingsTile(
                icon: Icons.verified_user_outlined,
                title: 'Device identity',
                subtitle:
                    'Identity created · ${_shortId(widget.identity.deviceId)}',
                semanticLabel: 'Open My Identity screen',
                onTap: widget.onOpenIdentity,
              ),
              _SettingsTile(
                icon: Icons.key_outlined,
                title: 'Public fingerprint',
                subtitle: widget.identity.fingerprint,
                semanticLabel:
                    'Open My Identity to view the public fingerprint',
                onTap: widget.onOpenIdentity,
              ),
            ],
          ),
          _SettingsSection(
            title: 'Privacy & Security',
            icon: Icons.lock_outline_rounded,
            children: [
              const _InformationTile(
                icon: Icons.enhanced_encryption_outlined,
                title: 'End-to-end encrypted messaging',
                subtitle:
                    'Messages are encrypted for the peer device before relay submission when an established session is available.',
              ),
              const _InformationTile(
                icon: Icons.phonelink_lock_outlined,
                title: 'Device identity',
                subtitle:
                    'Your public identity identifies this device. Private identity material is not shown here.',
              ),
              _InformationTile(
                icon: Icons.verified_outlined,
                title: 'Contact verification',
                subtitle: trustCounts,
              ),
              _InformationTile(
                icon: Icons.lock_person_outlined,
                title: 'Session security',
                subtitle: sessionSummary,
              ),
              const _InformationTile(
                icon: Icons.storage_outlined,
                title: 'Local message storage',
                subtitle:
                    'Messages are stored on this device in encrypted local records.',
              ),
              _InformationTile(
                icon: Icons.security_outlined,
                title: 'Secure storage',
                subtitle: widget.isTemporaryLocalMode
                    ? 'Temporary in-memory mode is active. Identity and local records may not persist after restart.'
                    : 'Platform secure storage is used for identity material and local storage keys.',
                warning: widget.isTemporaryLocalMode,
              ),
              const _InformationTile(
                icon: Icons.cloud_outlined,
                title: 'Relay trust',
                subtitle:
                    'The relay forwards opaque encrypted packets but can observe routing, timing, and packet-size metadata.',
              ),
            ],
          ),
          _SettingsSection(
            title: 'Contacts & Trust',
            icon: Icons.people_outline_rounded,
            children: [
              _SettingsTile(
                icon: Icons.people_alt_outlined,
                title: 'Your contacts',
                subtitle: '${data.contacts.length} locally stored',
                semanticLabel: 'Open Contacts',
                onTap: widget.onOpenContacts,
              ),
              _SettingsTile(
                icon: Icons.rule_folder_outlined,
                title: 'Trust states',
                subtitle: trustCounts,
                semanticLabel: 'Open Contacts to review trust states',
                onTap: widget.onOpenContacts,
              ),
            ],
          ),
          _SettingsSection(
            title: 'Messaging',
            icon: Icons.chat_bubble_outline_rounded,
            children: [
              _InformationTile(
                icon: Icons.devices_outlined,
                title: 'Sessions',
                subtitle: sessionSummary,
              ),
              _InformationTile(
                icon: Icons.outbox_outlined,
                title: 'Pending outgoing messages',
                subtitle:
                    '$pendingCount stored locally and awaiting submission',
              ),
              _InformationTile(
                icon: widget.controller.sessionExchangeAvailable
                    ? Icons.sync_alt_rounded
                    : Icons.sync_disabled_rounded,
                title: widget.controller.sessionExchangeAvailable
                    ? 'Session exchange configured'
                    : 'Session exchange unavailable',
                subtitle: widget.controller.sessionExchangeAvailable
                    ? 'A session exchange transport is configured. Sessions still require verified peer identities and authenticated protocol completion.'
                    : 'This app build has no session-exchange delivery gateway. Two devices need a configured channel to exchange signed session-initiation and response messages.',
                warning: !widget.controller.sessionExchangeAvailable,
              ),
              const _InformationTile(
                icon: Icons.notifications_off_outlined,
                title: 'Notifications unavailable',
                subtitle:
                    'This build has no configured local notification or push provider. No notification permission or enabled state is implied.',
                warning: true,
              ),
              const _InformationTile(
                icon: Icons.sync_disabled_rounded,
                title: 'Foreground sync only',
                subtitle:
                    'Use Synchronize on the Conversations screen while the app is open. Native background execution is not configured.',
              ),
            ],
          ),
          _SettingsSection(
            title: 'Connection / Relay',
            icon: Icons.hub_outlined,
            children: [
              _InformationTile(
                icon: connection.icon,
                title: connection.label,
                subtitle: [
                  connection.detail,
                  if (widget.relayConfigurationMessage != connection.detail)
                    widget.relayConfigurationMessage,
                ].join(' '),
                statusColor: connection.color,
              ),
              const _InformationTile(
                icon: Icons.lock_clock_outlined,
                title: 'Authentication',
                subtitle:
                    'When connected, this device authenticates using a signed challenge from its device identity.',
              ),
            ],
          ),
          _SettingsSection(
            title: 'Storage',
            icon: Icons.save_outlined,
            children: [
              _InformationTile(
                icon: Icons.message_outlined,
                title: 'Messages, contacts & sessions',
                subtitle: widget.isTemporaryLocalMode
                    ? 'Records use in-memory storage in this mode and may be lost when the app restarts.'
                    : 'Records are stored locally in encrypted app records. Storage keys are kept separately using platform secure storage.',
                warning: widget.isTemporaryLocalMode,
              ),
              const _InformationTile(
                icon: Icons.key_off_outlined,
                title: 'Secret material',
                subtitle:
                    'Private keys, session secrets, and storage keys are not displayed in Settings.',
              ),
            ],
          ),
          const _SettingsSection(
            title: 'About eChat',
            icon: Icons.info_outline_rounded,
            children: [
              _InformationTile(
                icon: Icons.shield_outlined,
                title: 'eChat',
                subtitle:
                    'Privacy-focused, device-to-device messaging with an untrusted encrypted-packet relay.',
              ),
              _InformationTile(
                icon: Icons.account_tree_outlined,
                title: 'Architecture principles',
                subtitle:
                    'Identity keys remain on device; contacts require verification; the relay does not decrypt message content.',
              ),
              _InformationTile(
                icon: Icons.info_outline,
                title: 'App version',
                subtitle: '0.1.0',
              ),
              _InformationTile(
                icon: Icons.fact_check_outlined,
                title: 'Security status',
                subtitle:
                    'Project-specific protocol composition has not been independently audited and is not production-approved.',
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _applyThemePreference(ThemePreference preference) async {
    try {
      await widget.onThemePreferenceChanged(preference);
    } on Object {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Appearance could not be saved. The selection is active for this session.',
          ),
        ),
      );
    }
  }

  static String _themeModeLabel(EchatThemeMode mode) => switch (mode) {
    EchatThemeMode.system => 'System default',
    EchatThemeMode.light => 'Light',
    EchatThemeMode.dark => 'Dark',
    EchatThemeMode.amoled => 'AMOLED',
  };

  static String _accentLabel(EchatAccent accent) => switch (accent) {
    EchatAccent.blue => 'Blue',
    EchatAccent.cyan => 'Cyan',
    EchatAccent.purple => 'Purple',
    EchatAccent.green => 'Green',
  };

  static String _shortId(String value) => value.length <= 18
      ? value
      : '${value.substring(0, 8)}…${value.substring(value.length - 6)}';

  static String _trustCounts(List<AppContact> contacts) {
    if (contacts.isEmpty) return 'No locally stored contacts';
    final counts = <AppTrustStatus, int>{};
    for (final contact in contacts) {
      counts.update(
        contact.trustStatus,
        (value) => value + 1,
        ifAbsent: () => 1,
      );
    }
    const labels = {
      AppTrustStatus.verified: 'Verified',
      AppTrustStatus.unverified: 'Unverified',
      AppTrustStatus.identityChanged: 'Identity changed',
      AppTrustStatus.revoked: 'Revoked',
    };
    return AppTrustStatus.values
        .where(counts.containsKey)
        .map((status) => '${labels[status]} ${counts[status]}')
        .join(' · ');
  }

  static String _sessionSummary(List<AppConversation> conversations) {
    if (conversations.isEmpty) return 'No local sessions';
    final established = conversations
        .where(
          (conversation) =>
              conversation.sessionStatus == AppSessionStatus.established,
        )
        .length;
    final needsReview = conversations
        .where(
          (conversation) =>
              conversation.sessionStatus ==
              AppSessionStatus.restoredNeedsReview,
        )
        .length;
    final pending = conversations.length - established - needsReview;
    final values = <String>[
      if (established > 0) '$established established',
      if (needsReview > 0) '$needsReview restored · review required',
      if (pending > 0) '$pending pending or closed',
    ];
    return values.join(' · ');
  }

  static _ConnectionDisplay _connectionSummary(
    AppConnectionStatus status,
  ) => switch (status) {
    AppConnectionStatus.notConfigured => _ConnectionDisplay(
      'Not configured',
      'Relay endpoint is not configured.',
      Icons.link_off_rounded,
      EchatColors.muted,
    ),
    AppConnectionStatus.connecting => _ConnectionDisplay(
      'Connecting',
      'The relay health connection is in progress.',
      Icons.sync_rounded,
      EchatColors.warning,
    ),
    AppConnectionStatus.authenticating => _ConnectionDisplay(
      'Authenticating',
      'The device is completing signed relay registration and authentication.',
      Icons.verified_user_outlined,
      EchatColors.warning,
    ),
    AppConnectionStatus.authenticationFailed => _ConnectionDisplay(
      'Authentication failed',
      'No authenticated relay connection is active. Review the relay configuration and try again.',
      Icons.gpp_bad_outlined,
      EchatColors.danger,
    ),
    AppConnectionStatus.connected => _ConnectionDisplay(
      'Connected · authenticated',
      'The relay transport reports an authenticated connection.',
      Icons.cloud_done_outlined,
      EchatColors.success,
    ),
    AppConnectionStatus.disconnected => _ConnectionDisplay(
      'Offline / unavailable',
      'No authenticated relay connection is currently active.',
      Icons.cloud_off_outlined,
      EchatColors.warning,
    ),
  };
}

class _SettingsData {
  const _SettingsData({required this.contacts, required this.conversations});

  final List<AppContact> contacts;
  final List<AppConversation> conversations;
}

class _ConnectionDisplay {
  const _ConnectionDisplay(this.label, this.detail, this.icon, this.color);

  final String label;
  final String detail;
  final IconData icon;
  final Color color;
}

class _SettingsSection extends StatelessWidget {
  const _SettingsSection({
    required this.title,
    required this.icon,
    required this.children,
  });

  final String title;
  final IconData icon;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.only(bottom: EchatSpacing.md),
    child: Padding(
      padding: const EdgeInsets.fromLTRB(
        EchatSpacing.md,
        EchatSpacing.md,
        EchatSpacing.md,
        EchatSpacing.sm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 20, color: EchatColors.accent),
              const SizedBox(width: EchatSpacing.sm),
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: EchatSpacing.sm),
          ...children,
        ],
      ),
    ),
  );
}

class _SettingsTile extends StatelessWidget {
  const _SettingsTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    required this.semanticLabel,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Future<void> Function() onTap;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: semanticLabel,
    child: ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, color: EchatColors.textSecondary),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.chevron_right_rounded),
      onTap: onTap,
    ),
  );
}

class _InformationTile extends StatelessWidget {
  const _InformationTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.warning = false,
    this.statusColor,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool warning;
  final Color? statusColor;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: EchatSpacing.sm),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          icon,
          size: 20,
          color:
              statusColor ??
              (warning ? EchatColors.warning : EchatColors.textSecondary),
        ),
        const SizedBox(width: EchatSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: EchatSpacing.xs),
              Text(
                subtitle,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: warning
                      ? EchatColors.warning
                      : EchatColors.textSecondary,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}
