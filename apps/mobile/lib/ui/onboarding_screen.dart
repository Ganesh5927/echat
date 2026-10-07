import 'package:flutter/material.dart';

import 'echat_theme.dart';

class OnboardingScreen extends StatelessWidget {
  const OnboardingScreen({
    super.key,
    required this.error,
    required this.identityLoadFailed,
    required this.hasCreatedIdentity,
    required this.onCreateIdentity,
    required this.onRetryIdentityLoad,
    required this.onContinue,
    required this.isTemporaryLocalMode,
  });

  final String? error;
  final bool identityLoadFailed;
  final bool hasCreatedIdentity;
  final Future<void> Function() onCreateIdentity;
  final Future<void> Function() onRetryIdentityLoad;
  final VoidCallback onContinue;
  final bool isTemporaryLocalMode;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: EchatColors.background,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: SizedBox(
              width: double.infinity,
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(
                  EchatSpacing.lg,
                  EchatSpacing.xxl,
                  EchatSpacing.lg,
                  EchatSpacing.xxl,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: Container(
                        width: 64,
                        height: 64,
                        decoration: BoxDecoration(
                          color: EchatColors.accent.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: EchatColors.border),
                        ),
                        child: Icon(
                          Icons.shield_rounded,
                          size: 34,
                          color: EchatColors.accent,
                        ),
                      ),
                    ),
                    const SizedBox(height: EchatSpacing.md),
                    Text(
                      'eChat',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: EchatSpacing.xxl),
                    Text(
                      hasCreatedIdentity
                          ? 'Your device identity is ready'
                          : 'Welcome to eChat',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: EchatSpacing.sm),
                    Text(
                      hasCreatedIdentity
                          ? 'Your device identity is used to authenticate this device and identify it to contacts.'
                          : 'A considered space for private conversations, built around device identities and encrypted messages.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: EchatColors.textSecondary,
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: EchatSpacing.xl),
                    if (!hasCreatedIdentity) ...[
                      const _OnboardingInformationCard(
                        icon: Icons.lock_outline_rounded,
                        title: 'Encrypted messages',
                        description:
                            'Messages are intended to be end-to-end encrypted between devices.',
                      ),
                      const SizedBox(height: EchatSpacing.sm),
                      const _OnboardingInformationCard(
                        icon: Icons.dns_outlined,
                        title: 'Relay transports encrypted data',
                        description:
                            'The relay does not receive the message decryption keys.',
                      ),
                      const SizedBox(height: EchatSpacing.sm),
                      const _OnboardingInformationCard(
                        icon: Icons.visibility_outlined,
                        title: 'Metadata may still be visible',
                        description:
                            'Infrastructure may observe connection timing, routing information, and packet size.',
                      ),
                    ] else ...[
                      const _OnboardingInformationCard(
                        icon: Icons.fingerprint_rounded,
                        title: 'This device identity',
                        description:
                            'It identifies this device in eChat and is used for device authentication. Your private identity material is not shown here.',
                      ),
                    ],
                    if (isTemporaryLocalMode) ...[
                      const SizedBox(height: EchatSpacing.md),
                      Semantics(
                        liveRegion: true,
                        child: Container(
                          padding: const EdgeInsets.all(EchatSpacing.md),
                          decoration: BoxDecoration(
                            color: EchatColors.warning.withValues(alpha: 0.10),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: EchatColors.warning.withValues(
                                alpha: 0.45,
                              ),
                            ),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                Icons.warning_amber_rounded,
                                color: EchatColors.warning,
                              ),
                              const SizedBox(width: EchatSpacing.sm),
                              Expanded(
                                child: Text(
                                  echatTemporaryLocalModeDisclosure,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: EchatColors.warning,
                                    height: 1.45,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                    if (!hasCreatedIdentity && !isTemporaryLocalMode) ...[
                      const SizedBox(height: EchatSpacing.md),
                      Text(
                        'Private identity material is stored using the platform\'s secure storage.',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: EchatColors.textSecondary,
                          height: 1.4,
                        ),
                      ),
                    ],
                    if (error != null && !hasCreatedIdentity) ...[
                      const SizedBox(height: EchatSpacing.md),
                      Semantics(
                        liveRegion: true,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: theme.colorScheme.errorContainer,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(EchatSpacing.md),
                            child: Text(
                              error!,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: theme.colorScheme.onErrorContainer,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: EchatSpacing.xl),
                    FilledButton.icon(
                      onPressed: hasCreatedIdentity
                          ? onContinue
                          : identityLoadFailed
                          ? onRetryIdentityLoad
                          : onCreateIdentity,
                      icon: Icon(
                        hasCreatedIdentity
                            ? Icons.arrow_forward_rounded
                            : identityLoadFailed
                            ? Icons.refresh_rounded
                            : Icons.fingerprint_rounded,
                      ),
                      label: Text(
                        hasCreatedIdentity
                            ? 'Continue to eChat'
                            : identityLoadFailed
                            ? 'Retry identity check'
                            : 'Create Device Identity',
                      ),
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

class _OnboardingInformationCard extends StatelessWidget {
  const _OnboardingInformationCard({
    required this.icon,
    required this.title,
    required this.description,
  });

  final IconData icon;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) => Card(
    margin: EdgeInsets.zero,
    child: Padding(
      padding: const EdgeInsets.all(EchatSpacing.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: EchatColors.accent),
          const SizedBox(width: EchatSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: EchatSpacing.xs),
                Text(
                  description,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: EchatColors.textSecondary,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}
