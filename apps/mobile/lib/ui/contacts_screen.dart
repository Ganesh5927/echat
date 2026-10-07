import 'package:flutter/material.dart';

import '../application/messaging_controller.dart';
import '../application/messaging_models.dart';
import 'conversations_screen.dart';
import 'echat_theme.dart';

class ContactsScreen extends StatefulWidget {
  const ContactsScreen({super.key, required this.controller});

  final MessagingController controller;

  @override
  State<ContactsScreen> createState() => _ContactsScreenState();
}

class _ContactsScreenState extends State<ContactsScreen> {
  final TextEditingController _payloadController = TextEditingController();
  late Future<List<AppContact>> _contacts;
  bool _importing = false;

  @override
  void initState() {
    super.initState();
    _contacts = widget.controller.contacts();
  }

  @override
  void dispose() {
    _payloadController.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    setState(() => _contacts = widget.controller.contacts());
  }

  Future<void> _importPublicIdentity() async {
    final payload = _payloadController.text.trim();
    if (payload.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Paste a public identity payload first.')),
      );
      return;
    }
    setState(() => _importing = true);
    AppContact contact;
    try {
      contact = await widget.controller.observeContactQr(payload);
    } on Object {
      if (mounted) {
        _showMessage('Public identity data is invalid.');
        setState(() => _importing = false);
      }
      return;
    }
    _payloadController.clear();
    await _refresh();
    if (!mounted) return;
    setState(() => _importing = false);
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => ContactDetailsScreen(
          controller: widget.controller,
          initialContact: contact,
        ),
      ),
    );
    await _refresh();
  }

  Future<void> _openContact(AppContact contact) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => ContactDetailsScreen(
          controller: widget.controller,
          initialContact: contact,
        ),
      ),
    );
    await _refresh();
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
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
            child: const Icon(
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
    body: RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(
          EchatSpacing.lg,
          EchatSpacing.sm,
          EchatSpacing.lg,
          EchatSpacing.xxl,
        ),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(
                      top: EchatSpacing.sm,
                      bottom: EchatSpacing.lg,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Contacts',
                          style: Theme.of(context).textTheme.headlineSmall
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: EchatSpacing.xs),
                        Text(
                          'Your contacts are stored locally. Compare fingerprints through a trusted channel before verifying.',
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(color: EchatColors.textSecondary),
                        ),
                      ],
                    ),
                  ),
                  Card(
                    margin: EdgeInsets.zero,
                    child: Padding(
                      padding: const EdgeInsets.all(EchatSpacing.lg),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(
                                Icons.person_add_alt_1_rounded,
                                color: EchatColors.accent,
                              ),
                              const SizedBox(width: EchatSpacing.sm),
                              Text(
                                'Add a contact',
                                style: Theme.of(context).textTheme.titleMedium
                                    ?.copyWith(fontWeight: FontWeight.w600),
                              ),
                            ],
                          ),
                          const SizedBox(height: EchatSpacing.xs),
                          Text(
                            'Import a public identity shared by your contact. Compare its fingerprint with them through a trusted channel before verifying.',
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  color: EchatColors.textSecondary,
                                  height: 1.4,
                                ),
                          ),
                          const SizedBox(height: EchatSpacing.md),
                          Semantics(
                            label: 'Public identity payload input',
                            child: TextField(
                              key: const Key('contact-public-payload'),
                              controller: _payloadController,
                              minLines: 2,
                              maxLines: 5,
                              decoration: const InputDecoration(
                                labelText: 'Public identity payload',
                                hintText: 'Paste the public identity data',
                                alignLabelWithHint: true,
                              ),
                            ),
                          ),
                          const SizedBox(height: EchatSpacing.md),
                          Align(
                            alignment: Alignment.centerRight,
                            child: Semantics(
                              label: 'Import public identity',
                              button: true,
                              child: FilledButton.tonalIcon(
                                key: const Key('import-contact'),
                                onPressed: _importing
                                    ? null
                                    : _importPublicIdentity,
                                icon: _importing
                                    ? const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Icon(
                                        Icons.person_add_alt_1_rounded,
                                      ),
                                label: Text(
                                  _importing
                                      ? 'Importing…'
                                      : 'Import public identity',
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: EchatSpacing.xl),
                  const EchatSectionHeader(label: 'Saved on this device'),
                  FutureBuilder<List<AppContact>>(
                    future: _contacts,
                    builder: (context, snapshot) {
                      if (snapshot.hasError) {
                        return const Card(
                          child: Padding(
                            padding: EdgeInsets.all(EchatSpacing.lg),
                            child: Text('Contacts could not be loaded.'),
                          ),
                        );
                      }
                      if (!snapshot.hasData) {
                        return const Padding(
                          padding: EdgeInsets.all(EchatSpacing.xl),
                          child: Center(child: CircularProgressIndicator()),
                        );
                      }
                      final contacts = snapshot.data!;
                      if (contacts.isEmpty) {
                        return const Card(
                          margin: EdgeInsets.zero,
                          child: Padding(
                            padding: EdgeInsets.all(EchatSpacing.xl),
                            child: EchatEmptyState(
                              icon: Icons.people_outline_rounded,
                              title: 'No contacts yet',
                              message:
                                  'Contacts appear here after you import a real public identity. Use the form above to add one.',
                            ),
                          ),
                        );
                      }
                      return Column(
                        key: const Key('contact-list'),
                        children: [
                          for (final contact in contacts) ...[
                            _ContactCard(
                              contact: contact,
                              onTap: () => _openContact(contact),
                            ),
                            const SizedBox(height: EchatSpacing.sm),
                          ],
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class _ContactCard extends StatelessWidget {
  const _ContactCard({required this.contact, required this.onTap});

  final AppContact contact;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final name = contact.displayAlias.trim().isEmpty
        ? contact.deviceId
        : contact.displayAlias;
    return Card(
      key: ValueKey<String>('contact-${contact.deviceId}'),
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Semantics(
        container: true,
        button: true,
        label:
            'Open contact details for $name. ${_trustLabel(contact.trustStatus)}.',
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(EchatSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      radius: 23,
                      backgroundColor: EchatColors.accent.withValues(
                        alpha: 0.12,
                      ),
                      child: Text(
                        name.characters.first.toUpperCase(),
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(
                              color: EchatColors.accent,
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                    ),
                    const SizedBox(width: EchatSpacing.md),
                    Expanded(
                      child: Text(
                        name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                    ),
                    const SizedBox(width: EchatSpacing.sm),
                    const Icon(
                      Icons.chevron_right_rounded,
                      color: EchatColors.muted,
                    ),
                  ],
                ),
                const SizedBox(height: EchatSpacing.md),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(width: 58),
                    _ContactTrustBadge(status: contact.trustStatus),
                    const SizedBox(width: EchatSpacing.sm),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(top: 3),
                        child: Text(
                          _trustLabel(contact.trustStatus),
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: EchatColors.textSecondary,
                                height: 1.35,
                              ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ContactTrustBadge extends StatelessWidget {
  const _ContactTrustBadge({required this.status});

  final AppTrustStatus status;

  @override
  Widget build(BuildContext context) {
    final style = switch (status) {
      AppTrustStatus.verified => (
        label: 'Verified',
        color: EchatColors.success,
        icon: Icons.verified_rounded,
      ),
      AppTrustStatus.unverified => (
        label: 'Unverified',
        color: EchatColors.warning,
        icon: Icons.gpp_maybe_rounded,
      ),
      AppTrustStatus.identityChanged => (
        label: 'Identity changed',
        color: EchatColors.warning,
        icon: Icons.warning_amber_rounded,
      ),
      AppTrustStatus.revoked => (
        label: 'Revoked',
        color: EchatColors.danger,
        icon: Icons.block_rounded,
      ),
    };
    return Semantics(
      label: style.label,
      child: ExcludeSemantics(
        child: EchatStatusChip(
          label: style.label,
          color: style.color,
          icon: style.icon,
        ),
      ),
    );
  }
}

class ContactDetailsScreen extends StatefulWidget {
  const ContactDetailsScreen({
    super.key,
    required this.controller,
    required this.initialContact,
  });

  final MessagingController controller;
  final AppContact initialContact;

  @override
  State<ContactDetailsScreen> createState() => _ContactDetailsScreenState();
}

class _ContactDetailsScreenState extends State<ContactDetailsScreen> {
  late AppContact _contact;
  final TextEditingController _fingerprintController = TextEditingController();
  bool _busy = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    _contact = widget.initialContact;
    _reload();
  }

  @override
  void dispose() {
    _fingerprintController.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    final current = await widget.controller.contact(_contact.deviceId);
    if (mounted && current != null) setState(() => _contact = current);
  }

  Future<void> _verify() async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      if (_contact.trustStatus == AppTrustStatus.identityChanged) {
        _contact = await widget.controller.reverifyChangedFingerprint(
          deviceId: _contact.deviceId,
          independentlyComparedFingerprint: _fingerprintController.text,
        );
      } else {
        _contact = await widget.controller.verifyContactFingerprint(
          deviceId: _contact.deviceId,
          independentlyComparedFingerprint: _fingerprintController.text,
        );
      }
    } on Object {
      _message = 'Fingerprint did not match or trust cannot be restored.';
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _revoke() async {
    try {
      setState(() => _busy = true);
      _contact = await widget.controller.revokeContact(_contact.deviceId);
      _message = 'Contact revoked on this device.';
    } on Object {
      _message = 'Contact could not be revoked.';
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _startConversation() async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final session = await widget.controller.requestSession(_contact.deviceId);
      if (!mounted) return;
      final conversations = await widget.controller.conversations();
      final conversation = conversations.cast<AppConversation?>().firstWhere(
        (item) => item?.sessionId == session.sessionId,
        orElse: () => null,
      );
      if (conversation != null && mounted) {
        await Navigator.of(context).push<void>(
          MaterialPageRoute<void>(
            builder: (_) => ConversationScreen(
              controller: widget.controller,
              conversation: conversation,
            ),
          ),
        );
      }
    } on Object {
      _message = 'A verified contact is required to request a session.';
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final changed = _contact.trustStatus == AppTrustStatus.identityChanged;
    final revoked = _contact.trustStatus == AppTrustStatus.revoked;
    final verified = _contact.trustStatus == AppTrustStatus.verified;
    return Scaffold(
      backgroundColor: EchatColors.background,
      appBar: AppBar(title: const Text('Contact details')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          _contact.displayAlias,
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                      ),
                      EchatTrustBadge(status: _contact.trustStatus),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Trust status',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  Text(_trustLabel(_contact.trustStatus)),
                  if (changed && _contact.previousFingerprint != null) ...[
                    const SizedBox(height: 16),
                    const Text(
                      'Previously verified fingerprint',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 8),
                    SelectableText(_contact.previousFingerprint!),
                  ],
                  const SizedBox(height: 16),
                  Text(
                    changed ? 'New candidate fingerprint' : 'Fingerprint',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  SelectableText(_contact.fingerprint),
                ],
              ),
            ),
          ),
          if (!verified && !revoked) ...[
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Compare this fingerprint with the contact through a trusted channel before confirming.',
                    ),
                    const SizedBox(height: 12),
                    Semantics(
                      label: 'Independently compared fingerprint',
                      child: TextField(
                        key: const Key('fingerprint-confirmation'),
                        controller: _fingerprintController,
                        decoration: const InputDecoration(
                          labelText: 'Independently compared fingerprint',
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Semantics(
                      label: changed
                          ? 'Re-verify changed identity'
                          : 'Verify contact',
                      button: true,
                      child: FilledButton(
                        key: const Key('confirm-contact-trust'),
                        onPressed: _busy ? null : _verify,
                        child: Text(
                          changed
                              ? 'Re-verify changed identity'
                              : 'Verify contact',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
          if (verified) ...[
            const SizedBox(height: 16),
            Semantics(
              label: 'Start 1-to-1 session',
              button: true,
              child: FilledButton.tonalIcon(
                key: const Key('start-conversation'),
                onPressed: _busy ? null : _startConversation,
                icon: const Icon(Icons.chat_bubble_outline_rounded),
                label: const Text('Start 1-to-1 session'),
              ),
            ),
          ],
          if (!revoked) ...[
            const SizedBox(height: 12),
            Semantics(
              label: 'Revoke contact on this device',
              button: true,
              child: OutlinedButton.icon(
                key: const Key('revoke-contact'),
                onPressed: _busy ? null : _revoke,
                icon: const Icon(Icons.block_rounded),
                label: const Text('Revoke contact on this device'),
              ),
            ),
          ],
          if (_message != null) ...[
            const SizedBox(height: 12),
            Text(_message!),
          ],
        ],
      ),
    );
  }
}

String _trustLabel(AppTrustStatus status) => switch (status) {
  AppTrustStatus.unverified => 'Identity not verified',
  AppTrustStatus.verified => 'Identity verified',
  AppTrustStatus.identityChanged =>
    'Identity changed — re-verification required',
  AppTrustStatus.revoked => 'Contact revoked',
};
