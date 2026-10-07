import 'package:shared_preferences/shared_preferences.dart';

import '../ui/echat_theme.dart';

class ThemePreference {
  const ThemePreference({
    this.mode = EchatThemeMode.dark,
    this.accent = EchatAccent.cyan,
  });

  final EchatThemeMode mode;
  final EchatAccent accent;

  static const ThemePreference defaults = ThemePreference();

  ThemePreference copyWith({EchatThemeMode? mode, EchatAccent? accent}) =>
      ThemePreference(mode: mode ?? this.mode, accent: accent ?? this.accent);

  @override
  bool operator ==(Object other) =>
      other is ThemePreference && other.mode == mode && other.accent == accent;

  @override
  int get hashCode => Object.hash(mode, accent);
}

class ThemePreferenceStore {
  static const String _modeKey = 'echat.appearance.mode.v1';
  static const String _accentKey = 'echat.appearance.accent.v1';
  Future<void> _writeTail = Future<void>.value();

  Future<ThemePreference> load() async {
    final preferences = await SharedPreferences.getInstance();
    return ThemePreference(
      mode: _parse(
        preferences.getString(_modeKey),
        EchatThemeMode.values,
        ThemePreference.defaults.mode,
      ),
      accent: _parse(
        preferences.getString(_accentKey),
        EchatAccent.values,
        ThemePreference.defaults.accent,
      ),
    );
  }

  Future<void> save(ThemePreference preference) {
    final previous = _writeTail;
    final next = previous.catchError((Object _) {}).then((_) async {
      final preferences = await SharedPreferences.getInstance();
      final savedMode = await preferences.setString(
        _modeKey,
        preference.mode.name,
      );
      final savedAccent = await preferences.setString(
        _accentKey,
        preference.accent.name,
      );
      if (!savedMode || !savedAccent) {
        throw StateError('Appearance preference could not be persisted.');
      }
    });
    _writeTail = next;
    return next;
  }

  static T _parse<T extends Enum>(String? value, List<T> values, T fallback) {
    for (final candidate in values) {
      if (candidate.name == value) return candidate;
    }
    return fallback;
  }
}
