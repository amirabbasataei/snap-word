import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _prefsKey = 'theme_mode';

/// Persists the user's حالت شب (night mode) choice. Defaults to dark: most
/// screens are still built against the legacy dark-only `AppColors` palette
/// (see `app_theme.dart`) and don't respond to `ThemeMode.light` yet — the
/// toggle itself is surfaced in ZProfile once that screen is ported
/// (Phase 17 Stage 5). Safe to construct and wire into `MaterialApp` now:
/// unmigrated screens simply ignore whichever theme is active.
class ThemeCubit extends Cubit<ThemeMode> {
  final SharedPreferences _prefs;

  ThemeCubit(this._prefs)
      : super(_modeFromString(_prefs.getString(_prefsKey)));

  static ThemeMode _modeFromString(String? value) {
    switch (value) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      default:
        return ThemeMode.dark;
    }
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    emit(mode);
    await _prefs.setString(_prefsKey, mode == ThemeMode.light ? 'light' : 'dark');
  }

  Future<void> toggle() =>
      setThemeMode(state == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark);
}
