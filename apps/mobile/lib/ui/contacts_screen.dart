import 'package:flutter/material.dart';

import '../application/messaging_controller.dart';
import '../application/messaging_models.dart';
import 'conversations_screen.dart';

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
    setState(() => _importing = true);
    AppContact contact;
    try {
      contact = await widget.controller.observeContactQr(
        _payloadController.text,
      );
    } on Object {
      if (mounted) _showMessage('Public identity data is invalid.');
      if (mounted) setState(() => _importing = false);
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
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Contacts')),
    body: RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          TextField(
            key: const Key('contact-public-payload'),
            controller: _payloadController,
            minLines: 2,
            maxLines: 5,
            decoration: const InputDecoration(
              labelText: 'Public identity payload',
              hintText: 'Paste a contact payload; QR scanning is not configured.',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.tonalIcon(
              key: const Key('import-contact'),
              onPressed: _importing ? null : _importPublicIdentity,
              icon: const Icon(Icons.person_add_alt_1),
              label: Text(_importing ? 'Importing…' : 'Import public identity'),
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'Local contacts',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          FutureBuilder<List<AppContact>>(
            future: _contacts,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return const ListTile(
                  title: Text('Contacts unavailable'),
                );
              }
              if (!snapshot.hasData) {
                return const Padding(
                  padding: EdgeInsets.all(20),
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              if (snapshot.data!.isEmpty) {
                return const ListTile(title: Text('No contacts yet'));
              }
              return Column(
                children: [
                  for (final contact in snapshot.data!)
                    ListTile(
                      key: Key('contact-${contact.deviceId}'),
                      leading: const Icon(Icons.person_outline),
                      title: Text(contact.displayAlias),
                      subtitle: Text(_trustLabel(contact.trustStatus)),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => _openContact(contact),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    ),
  );
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
      appBar: AppBar(title: const Text('Contact details')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(_contact.displayAlias, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Text('Trust: ${_trustLabel(_contact.trustStatus)}'),
          const SizedBox(height: 16),
          if (changed && _contact.previousFingerprint != null) ...[
            const Text('Previously verified fingerprint'),
            SelectableText(_contact.previousFingerprint!),
            const SizedBox(height: 12),
          ],
          Text(changed ? 'New candidate fingerprint' : 'Fingerprint'),
          SelectableText(_contact.fingerprint),
          if (!verified && !revoked) ...[
            const SizedBox(height: 20),
            const Text(
              'Compare this fingerprint with the contact through a trusted channel before confirming.',
            ),
            const SizedBox(height: 8),
            TextField(
              key: const Key('fingerprint-confirmation'),
              controller: _fingerprintController,
              decoration: const InputDecoration(
                labelText: 'Independently compared fingerprint',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            FilledButton(
              key: const Key('confirm-contact-trust'),
              onPressed: _busy ? null : _verify,
              child: Text(changed ? 'Re-verify changed identity' : 'Verify contact'),
            ),
          ],
          if (verified) ...[
            const SizedBox(height: 20),
            FilledButton.tonalIcon(
              key: const Key('start-conversation'),
              onPressed: _busy ? null : _startConversation,
              icon: const Icon(Icons.chat_outlined),
              label: const Text('Start 1-to-1 session'),
            ),
          ],
          if (!revoked) ...[
            const SizedBox(height: 12),
            OutlinedButton.icon(
              key: const Key('revoke-contact'),
              onPressed: _busy ? null : _revoke,
              icon: const Icon(Icons.block),
              label: const Text('Revoke contact on this device'),
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
  AppTrustStatus.unverified => 'Unverified',
  AppTrustStatus.verified => 'Verified',
  AppTrustStatus.identityChanged => 'Identity changed',
  AppTrustStatus.revoked => 'Revoked',
};