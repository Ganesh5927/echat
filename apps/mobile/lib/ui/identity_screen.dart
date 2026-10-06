import 'package:flutter/material.dart';

import '../application/messaging_models.dart';

class IdentityScreen extends StatelessWidget {
  const IdentityScreen({
    super.key,
    required this.identity,
    required this.relayConfigurationMessage,
    required this.onDelete,
    required this.onRefresh,
  });

  final LocalIdentityView identity;
  final String relayConfigurationMessage;
  final Future<void> Function() onDelete;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Device identity'),
      actions: [
        IconButton(
          tooltip: 'Refresh identity',
          onPressed: onRefresh,
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        ListTile(
          leading: const Icon(Icons.verified_user_outlined),
          title: Text(identity.statusLabel),
          subtitle: const Text(
            'Local device status; this does not verify contacts.',
          ),
        ),
        const SizedBox(height: 12),
        const Text('Device ID'),
        SelectableText(identity.deviceId),
        const SizedBox(height: 16),
        const Text('Verification fingerprint'),
        SelectableText(identity.fingerprint),
        const SizedBox(height: 16),
        const Text('Public identity payload'),
        const SizedBox(height: 8),
        SelectableText(identity.publicQrJson),
        const SizedBox(height: 20),
        const Text('Relay configuration'),
        const SizedBox(height: 6),
        Text(relayConfigurationMessage),
        const SizedBox(height: 20),
        OutlinedButton.icon(
          key: const Key('delete-local-identity'),
          onPressed: onDelete,
          icon: const Icon(Icons.delete_outline),
          label: const Text('Delete local identity'),
        ),
      ],
    ),
  );
}
