import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../application/messaging_models.dart';
import 'echat_theme.dart';

class IdentityScreen extends StatelessWidget {
  const IdentityScreen({
    super.key,
    required this.identity,
    required this.relayConfigurationMessage,
    required this.isTemporaryLocalMode,
    required this.onDelete,
    required this.onRefresh,
  });

  final LocalIdentityView identity;
  final String relayConfigurationMessage;
  final bool isTemporaryLocalMode;
  final Future<void> Function() onDelete;
  final Future<void> Function() onRefresh;

  Future<void> _confirmDelete(BuildContext context) async {
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete local identity?'),
        content: const Text(
          'This removes the device identity key and public identity record. It does not delete saved contacts, session records or secrets, encrypted messages, or the local storage key. Those records remain on this device. Contacts will need a new public identity if you create another.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete identity'),
          ),
        ],
      ),
    );
    if (shouldDelete != true) return;
    try {
      await onDelete();
    } on Exception {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Identity could not be deleted. Check device storage and try again.',
            ),
          ),
        );
      }
    }
  }

  Future<void> _copyPublicIdentity(BuildContext context) async {
    try {
      await Clipboard.setData(ClipboardData(text: identity.publicQrJson));
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Public identity payload copied.')),
        );
      }
    } on Object {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Public identity could not be copied.')),
        );
      }
    }
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
      actions: [
        Semantics(
          label: 'Refresh identity',
          button: true,
          child: IconButton(
            tooltip: 'Refresh identity',
            onPressed: onRefresh,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ),
      ],
    ),
    body: ListView(
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
                        'My Identity',
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: EchatSpacing.xs),
                      Text(
                        'Review the public identity for this device. Keep private key material to yourself.',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: EchatColors.textSecondary,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
                Card(
                  margin: EdgeInsets.zero,
                  child: Padding(
                    padding: const EdgeInsets.all(EchatSpacing.md),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          isTemporaryLocalMode
                              ? Icons.warning_amber_rounded
                              : Icons.lock_outline_rounded,
                          color: isTemporaryLocalMode
                              ? EchatColors.warning
                              : EchatColors.success,
                        ),
                        const SizedBox(width: EchatSpacing.md),
                        Expanded(
                          child: Text(
                            isTemporaryLocalMode
                                ? echatTemporaryLocalModeDisclosure
                                : 'Private identity material is stored using the platform\'s secure storage.',
                            key: const Key('identity-storage-disclosure'),
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  color: isTemporaryLocalMode
                                      ? EchatColors.warning
                                      : EchatColors.textSecondary,
                                  height: 1.4,
                                ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: EchatSpacing.md),
                Card(
                  margin: EdgeInsets.zero,
                  child: Padding(
                    padding: const EdgeInsets.all(EchatSpacing.lg),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 48,
                              height: 48,
                              decoration: BoxDecoration(
                                color: EchatColors.accent.withValues(
                                  alpha: 0.12,
                                ),
                                borderRadius: BorderRadius.circular(15),
                              ),
                              child: Icon(
                                Icons.fingerprint_rounded,
                                color: EchatColors.accent,
                              ),
                            ),
                            const SizedBox(width: EchatSpacing.md),
                            Expanded(
                              child: Text(
                                'Device identity',
                                style: Theme.of(context).textTheme.titleMedium
                                    ?.copyWith(fontWeight: FontWeight.w600),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: EchatSpacing.md),
                        Semantics(
                          label: 'Identity status: ${identity.statusLabel}',
                          child: ExcludeSemantics(
                            child: EchatStatusChip(
                              label: identity.statusLabel,
                              color: EchatColors.accent,
                              icon: Icons.fingerprint_rounded,
                            ),
                          ),
                        ),
                        const SizedBox(height: EchatSpacing.lg),
                        const EchatSectionHeader(label: 'Public fingerprint'),
                        SelectableText(
                          identity.fingerprint,
                          key: const Key('identity-fingerprint'),
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(fontFamily: 'monospace', height: 1.5),
                        ),
                        const SizedBox(height: EchatSpacing.lg),
                        const EchatSectionHeader(label: 'Device ID'),
                        SelectableText(
                          identity.deviceId,
                          key: const Key('identity-device-id'),
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(fontFamily: 'monospace'),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: EchatSpacing.lg),
                Card(
                  margin: EdgeInsets.zero,
                  child: Padding(
                    padding: const EdgeInsets.all(EchatSpacing.lg),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.ios_share_rounded,
                              color: EchatColors.accent,
                            ),
                            const SizedBox(width: EchatSpacing.sm),
                            Expanded(
                              child: Text(
                                'Public identity information',
                                style: Theme.of(context).textTheme.titleMedium
                                    ?.copyWith(fontWeight: FontWeight.w600),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: EchatSpacing.sm),
                        Text(
                          'Share this public payload with a contact. Compare fingerprints through an independent, trusted channel before they verify your identity.',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: EchatColors.textSecondary,
                                height: 1.45,
                              ),
                        ),
                        const SizedBox(height: EchatSpacing.md),
                        Center(
                          child: Semantics(
                            image: true,
                            label:
                                'QR code containing public identity information',
                            child: Container(
                              padding: const EdgeInsets.all(EchatSpacing.md),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: QrImageView(
                                key: const Key('public-identity-qr'),
                                data: identity.publicQrJson,
                                version: QrVersions.auto,
                                size: 220,
                                backgroundColor: Colors.white,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: EchatSpacing.md),
                        Semantics(
                          label: 'Copy public identity payload',
                          button: true,
                          child: OutlinedButton.icon(
                            key: const Key('copy-public-identity'),
                            onPressed: () => _copyPublicIdentity(context),
                            icon: const Icon(Icons.copy_rounded),
                            label: const Text('Copy public identity payload'),
                          ),
                        ),
                        const SizedBox(height: EchatSpacing.md),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(EchatSpacing.md),
                          decoration: BoxDecoration(
                            color: EchatColors.surfaceElevated,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: EchatColors.border),
                          ),
                          child: SelectableText(
                            identity.publicQrJson,
                            key: const Key('public-identity-payload'),
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  fontFamily: 'monospace',
                                  height: 1.45,
                                ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: EchatSpacing.md),
                Card(
                  margin: EdgeInsets.zero,
                  child: Padding(
                    padding: const EdgeInsets.all(EchatSpacing.lg),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.lock_outline_rounded,
                          color: EchatColors.success,
                        ),
                        const SizedBox(width: EchatSpacing.md),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Private key material',
                                style: Theme.of(context).textTheme.titleSmall
                                    ?.copyWith(fontWeight: FontWeight.w600),
                              ),
                              const SizedBox(height: EchatSpacing.xs),
                              Text(
                                'Private key material is not shown here. Keep it on this device and never share it.',
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(
                                      color: EchatColors.textSecondary,
                                      height: 1.45,
                                    ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: EchatSpacing.md),
                Card(
                  margin: EdgeInsets.zero,
                  child: Padding(
                    padding: const EdgeInsets.all(EchatSpacing.lg),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const EchatSectionHeader(label: 'Relay configuration'),
                        Text(
                          relayConfigurationMessage,
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(
                                color: EchatColors.textSecondary,
                                height: 1.4,
                              ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: EchatSpacing.xl),
                Semantics(
                  label: 'Delete local identity',
                  button: true,
                  child: OutlinedButton.icon(
                    key: const Key('delete-local-identity'),
                    onPressed: () => _confirmDelete(context),
                    icon: const Icon(Icons.delete_outline_rounded),
                    label: const Text('Delete local identity'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}
