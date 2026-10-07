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

enum EchatThemeMode { system, light, dark, amoled }

enum EchatAccent { blue, cyan, purple, green }

class EchatColors {
  static Color background = const Color(0xFF0B1020);
  static Color surface = const Color(0xFF101827);
  static Color surfaceElevated = const Color(0xFF172033);
  static Color surfaceHigh = const Color(0xFF1C2438);
  static Color border = const Color(0xFF2B3650);
  static Color textPrimary = const Color(0xFFEAF2FF);
  static Color textSecondary = const Color(0xFF9AA9C0);
  static Color accent = const Color(0xFF7DD3FC);
  static Color success = const Color(0xFF4ADE80);
  static Color warning = const Color(0xFFFACC15);
  static Color danger = const Color(0xFFF87171);
  static Color muted = const Color(0xFF7C8AA5);
}

class EchatTheme {
  static ThemeData dark() =>
      themed(mode: EchatThemeMode.dark, accent: EchatAccent.cyan);

  static ThemeData themed({
    required EchatThemeMode mode,
    required EchatAccent accent,
    Brightness systemBrightness = Brightness.dark,
  }) {
    final brightness = switch (mode) {
      EchatThemeMode.system => systemBrightness,
      EchatThemeMode.light => Brightness.light,
      EchatThemeMode.dark || EchatThemeMode.amoled => Brightness.dark,
    };
    final isDark = brightness == Brightness.dark;
    final isAmoled = mode == EchatThemeMode.amoled;
    final accentColor = _accentColor(accent, isDark);
    EchatColors.background = isDark
        ? (isAmoled ? const Color(0xFF000000) : const Color(0xFF0B1020))
        : const Color(0xFFF4F6FA);
    EchatColors.surface = isDark
        ? (isAmoled ? const Color(0xFF080B11) : const Color(0xFF101827))
        : const Color(0xFFFFFFFF);
    EchatColors.surfaceElevated = isDark
        ? (isAmoled ? const Color(0xFF10141D) : const Color(0xFF172033))
        : const Color(0xFFEAF0F7);
    EchatColors.surfaceHigh = isDark
        ? (isAmoled ? const Color(0xFF171C27) : const Color(0xFF1C2438))
        : const Color(0xFFDDE6F1);
    EchatColors.border = isDark
        ? const Color(0xFF2B3650)
        : const Color(0xFFC7D2E0);
    EchatColors.textPrimary = isDark
        ? const Color(0xFFEAF2FF)
        : const Color(0xFF172033);
    EchatColors.textSecondary = isDark
        ? const Color(0xFF9AA9C0)
        : const Color(0xFF46546A);
    EchatColors.accent = accentColor;
    EchatColors.success = isDark
        ? const Color(0xFF4ADE80)
        : const Color(0xFF167A3E);
    EchatColors.warning = isDark
        ? const Color(0xFFFACC15)
        : const Color(0xFF8A5700);
    EchatColors.danger = isDark
        ? const Color(0xFFF87171)
        : const Color(0xFFB42332);
    EchatColors.muted = isDark
        ? const Color(0xFF7C8AA5)
        : const Color(0xFF59677C);

    final base = ThemeData(
      useMaterial3: true,
      brightness: brightness,
      fontFamily: 'Roboto',
      scaffoldBackgroundColor: EchatColors.background,
      colorScheme: ColorScheme.fromSeed(
        seedColor: accentColor,
        brightness: brightness,
        surface: EchatColors.surface,
        primary: accentColor,
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
          side: BorderSide(color: EchatColors.border),
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
          borderSide: BorderSide(color: EchatColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: EchatColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: EchatColors.accent),
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

  static Color _accentColor(EchatAccent accent, bool isDark) =>
      switch ((accent, isDark)) {
        (EchatAccent.blue, true) => const Color(0xFF93B4FF),
        (EchatAccent.blue, false) => const Color(0xFF2458B8),
        (EchatAccent.cyan, true) => const Color(0xFF7DD3FC),
        (EchatAccent.cyan, false) => const Color(0xFF087E9B),
        (EchatAccent.purple, true) => const Color(0xFFC4A1FF),
        (EchatAccent.purple, false) => const Color(0xFF7041A8),
        (EchatAccent.green, true) => const Color(0xFF83D7A0),
        (EchatAccent.green, false) => const Color(0xFF23734A),
      };
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
