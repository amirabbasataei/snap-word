import 'package:flutter_test/flutter_test.dart';
import 'package:wordchain/core/utils/avatar_initial.dart';

void main() {
  group('nameInitial', () {
    test('first character, upper-cased; fallback only for an empty name', () {
      expect(nameInitial('امیر'), 'ا');
      expect(nameInitial('  sara'), 'S');
      expect(nameInitial('_x'), '_');
      expect(nameInitial(null), '؟');
      expect(nameInitial('  '), '؟');
      expect(nameInitial('', fallback: 'ت'), 'ت');
    });

    test('takes a whole code point, not half a surrogate pair', () {
      expect(nameInitial('😀x'), '😀');
    });
  });

  group('avatarInitial', () {
    test('letters only; ت for guests and non-letters', () {
      expect(avatarInitial('امیر'), 'ا');
      expect(avatarInitial('  sara'), 'S');
      expect(avatarInitial(null), 'ت');
      expect(avatarInitial(''), 'ت');
      expect(avatarInitial('_x'), 'ت');
      expect(avatarInitial('۱۲۳'), 'ت');
    });
  });
}
