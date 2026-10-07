import 'package:flutter/material.dart';

import '../application/messaging_models.dart';

const String echatTemporaryLocalModeDisclosure =
    'Temporary local mode is active. Identity data may not persist after restart. Do not use this mode for a final security-sensitive deployment.';

class EchatSpacing {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double xxl = 24;
}

class EchatColors {
  static const Color background = Color(0xFF0B1020);
  static const Color surface = Color(0xFF101827);
  static const Color surfaceElevated = Color(0xFF172033);
  static const Color surfaceHigh = Color(0xFF1C2438);
  static const Color border = Color(0xFF2B3650);
  static const Color textPrimary = Color(0xFFEAF2FF);
  static const Color textSecondary = Color(0xFF9AA9C0);
  static const Color accent = Color(0xFF7DD3FC);
  static const Color success = Color(0xFF4ADE80);
  static const Color warning = Color(0xFFFACC15);
  static const Color danger = Color(0xFFF87171);
  static const Color muted = Color(0xFF7C8AA5);
}

class EchatTheme {
  static ThemeData dark() {
    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      fontFamily: 'Roboto',
      scaffoldBackgroundColor: EchatColors.background,
      colorScheme: ColorScheme.fromSeed(
        seedColor: EchatColors.accent,
        brightness: Brightness.dark,
        surface: EchatColors.surface,
        primary: EchatColors.accent,
        secondary: EchatColors.success,
        tertiary: EchatColors.warning,
      ),
    );

    return base.copyWith(
      appBarTheme: AppBarTheme(
        backgroundColor: EchatColors.background,
        foregroundColor: EchatColors.textPrimary,
        centerTitle: false,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: base.textTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.w600,
          color: EchatColors.textPrimary,
        ),
      ),
      cardTheme: CardThemeData(
        color: EchatColors.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: const BorderSide(color: EchatColors.border),
        ),
        margin: const EdgeInsets.symmetric(vertical: 6),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: EchatColors.surface,
        indicatorColor: EchatColors.accent.withValues(alpha: 0.18),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return base.textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w600,
              color: EchatColors.textPrimary,
            );
          }
          return base.textTheme.labelMedium?.copyWith(
            color: EchatColors.textSecondary,
          );
        }),
      ),
      inputDecorationTheme: InputDecorationTheme(
        fillColor: EchatColors.surface,
        filled: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: EchatColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: EchatColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: EchatColors.accent),
        ),
        hintStyle: base.textTheme.bodyMedium?.copyWith(
          color: EchatColors.textSecondary,
        ),
        labelStyle: base.textTheme.bodyMedium?.copyWith(
          color: EchatColors.textSecondary,
        ),
      ),
      dividerColor: EchatColors.border,
      textTheme: base.textTheme.apply(
        bodyColor: EchatColors.textPrimary,
        displayColor: EchatColors.textPrimary,
      ),
    );
  }
}

class EchatStatusChip extends StatelessWidget {
  const EchatStatusChip({
    super.key,
    required this.label,
    required this.color,
    this.icon,
  });

  final String label;
  final Color color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 14, color: color),
              const SizedBox(width: 6),
            ],
            Text(
              label,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: color,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class EchatTrustBadge extends StatelessWidget {
  const EchatTrustBadge({super.key, required this.status});

  final AppTrustStatus status;

  @override
  Widget build(BuildContext context) {
    final value = switch (status) {
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

    return EchatStatusChip(
      label: value.label,
      color: value.color,
      icon: value.icon,
    );
  }
}

class EchatEmptyState extends StatelessWidget {
  const EchatEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.all(EchatSpacing.xxl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: EchatColors.accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: EchatColors.border),
                ),
                child: Icon(icon, size: 30, color: EchatColors.accent),
              ),
              const SizedBox(height: 20),
              Text(
                title,
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 10),
              Text(
                message,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: EchatColors.textSecondary,
                  height: 1.4,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class EchatSectionHeader extends StatelessWidget {
  const EchatSectionHeader({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: EchatSpacing.sm),
    child: Text(
      label,
      style: Theme.of(context).textTheme.titleSmall?.copyWith(
        color: EchatColors.textSecondary,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.4,
      ),
    ),
  );
}
