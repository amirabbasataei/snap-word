import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wordchain/core/utils/premium_catalog.dart';

Set<String> _goMapKeys(String source, String varName) {
  final block =
      RegExp(
        'var $varName = map\\[string\\]bool\\{(.*?)\\n\\}',
        dotAll: true,
      ).firstMatch(source)!.group(1)!;
  return RegExp(
    r'"([a-z_]+)":\s*true',
  ).allMatches(block).map((m) => m[1]!).toSet();
}

void main() {
  final goConfig =
      File('../backend/internal/config/config.go').readAsStringSync();

  test('taunt ids match the backend whitelist (config.TauntIDs)', () {
    expect(
      PremiumCatalog.taunts.keys.toSet(),
      _goMapKeys(goConfig, 'TauntIDs'),
    );
  });

  test('avatar ids match the backend catalogue (config.AvatarIDs)', () {
    expect(PremiumCatalog.avatarIds.toSet(), _goMapKeys(goConfig, 'AvatarIDs'));
  });

  test('every avatar id has a bundled image', () {
    for (final id in PremiumCatalog.avatarIds) {
      expect(
        File(PremiumCatalog.avatarAsset(id)).existsSync(),
        isTrue,
        reason: id,
      );
    }
  });

  test('taunt text is Persian (emoji allowed, no Latin letters)', () {
    final latin = RegExp(r'[A-Za-z]');
    for (final text in PremiumCatalog.taunts.values) {
      expect(latin.hasMatch(text), isFalse, reason: text);
    }
  });

  test('lookups tolerate unknown / null ids', () {
    expect(PremiumCatalog.hasAvatar(null), isFalse);
    expect(PremiumCatalog.hasAvatar('nope'), isFalse);
    expect(PremiumCatalog.tauntText('nope'), isNull);
  });
}
