import 'package:echat_mobile/application/theme_preferences.dart';
import 'package:echat_mobile/ui/echat_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('theme preferences default safely and persist selections', () async {
    SharedPreferences.setMockInitialValues({});
    final store = ThemePreferenceStore();

    expect(await store.load(), ThemePreference.defaults);

    const selection = ThemePreference(
      mode: EchatThemeMode.amoled,
      accent: EchatAccent.purple,
    );
    await store.save(selection);
    expect(await store.load(), selection);
  });

  test('unknown saved theme values fall back to supported defaults', () async {
    SharedPreferences.setMockInitialValues({
      'echat.appearance.mode.v1': 'unsupported',
      'echat.appearance.accent.v1': 'unsupported',
    });

    expect(await ThemePreferenceStore().load(), ThemePreference.defaults);
  });

  test('central theme factory applies light, system, AMOLED, and accents', () {
    final light = EchatTheme.themed(
      mode: EchatThemeMode.light,
      accent: EchatAccent.blue,
    );
    expect(light.brightness, Brightness.light);
    expect(EchatColors.background, const Color(0xFFF4F6FA));

    final systemLight = EchatTheme.themed(
      mode: EchatThemeMode.system,
      accent: EchatAccent.cyan,
      systemBrightness: Brightness.light,
    );
    expect(systemLight.brightness, Brightness.light);

    final amoled = EchatTheme.themed(
      mode: EchatThemeMode.amoled,
      accent: EchatAccent.purple,
    );
    expect(amoled.brightness, Brightness.dark);
    expect(EchatColors.background, const Color(0xFF000000));
    expect(EchatColors.accent, const Color(0xFFC4A1FF));

    final green = EchatTheme.themed(
      mode: EchatThemeMode.dark,
      accent: EchatAccent.green,
    );
    expect(EchatColors.accent, const Color(0xFF83D7A0));
    expect(green.useMaterial3, isTrue);
  });
}
