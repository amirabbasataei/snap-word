import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wordchain/core/widgets/avatar_tile.dart';

import '../../helpers/z_test_app.dart';

void main() {
  testWidgets('shows the initial without a premium avatar', (tester) async {
    await tester.pumpWidget(zTestApp(const AvatarTile(name: 'sara')));
    expect(find.text('S'), findsOneWidget);
  });

  testWidgets('a known avatar id replaces the initial with its image', (
    tester,
  ) async {
    await tester.pumpWidget(
      zTestApp(const AvatarTile(name: 'sara', avatarId: 'lion')),
    );
    expect(find.byType(Image), findsOneWidget);
    expect(find.text('S'), findsNothing);
  });

  testWidgets('an unknown avatar id falls back to the initial', (tester) async {
    await tester.pumpWidget(
      zTestApp(const AvatarTile(name: 'sara', avatarId: 'nope')),
    );
    expect(find.text('S'), findsOneWidget);
  });
}
