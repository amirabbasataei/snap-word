import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _prefsKey = 'theme_mode';

/// Persists the user's حالت شب (night mode) choice, toggled from ZProfile.
/// With no saved choice the app follows the system setting.
class ThemeCubit extends Cubit<ThemeMode> {
  final SharedPreferences _prefs;

  ThemeCubit(this._prefs) : super(_modeFromString(_prefs.getString(_prefsKey)));

  static ThemeMode _modeFromString(String? value) {
    switch (value) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      default:
        return ThemeMode.system;
    }
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    emit(mode);
    await _prefs.setString(
      _prefsKey,
      mode == ThemeMode.light ? 'light' : 'dark',
    );
  }

  /// Flips relative to what's actually on screen, so the first toggle from
  /// [ThemeMode.system] always does something visible.
  Future<void> toggle(Brightness current) => setThemeMode(
    current == Brightness.dark ? ThemeMode.light : ThemeMode.dark,
  );
}
