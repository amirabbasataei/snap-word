import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wordchain/core/widgets/avatar_tile.dart';

import '../../helpers/z_test_app.dart';

void main() {
  testWidgets('shows the initial without a premium avatar', (tester) async {
    await tester.pumpWidget(zTestApp(const AvatarTile(name: 'sara')));
    expect(find.text('S'), findsOneWidget);
  });

  testWidgets(
    'an avatar id loads its image, keeping the initial as placeholder',
    (tester) async {
      await tester.pumpWidget(
        zTestApp(const AvatarTile(name: 'sara', avatarId: 'lion')),
      );
      expect(find.byType(Image), findsOneWidget);
      // Tests have no network, so the image never arrives: the initial shows.
      expect(find.text('S'), findsOneWidget);
    },
  );

  testWidgets('an empty avatar id is treated as no avatar', (tester) async {
    await tester.pumpWidget(
      zTestApp(const AvatarTile(name: 'sara', avatarId: '')),
    );
    expect(find.byType(Image), findsNothing);
    expect(find.text('S'), findsOneWidget);
  });
}
