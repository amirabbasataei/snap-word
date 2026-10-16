import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wordchain/core/theme/theme_cubit.dart';

void main() {
  Future<ThemeCubit> cubit([Map<String, Object> prefs = const {}]) async {
    SharedPreferences.setMockInitialValues(prefs);
    return ThemeCubit(await SharedPreferences.getInstance());
  }

  test('follows the system until the user picks a mode', () async {
    expect((await cubit()).state, ThemeMode.system);
  });

  test('toggle flips relative to what is on screen and persists', () async {
    final c = await cubit();
    await c.toggle(Brightness.dark); // system → showing dark
    expect(c.state, ThemeMode.light);
    await c.toggle(Brightness.light);
    expect(c.state, ThemeMode.dark);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('theme_mode'), 'dark');
    expect(ThemeCubit(prefs).state, ThemeMode.dark);
  });
}
