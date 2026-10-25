import 'package:flutter_test/flutter_test.dart';
import 'package:wordchain/features/friends/cubit/invite_code_cubit.dart';

void main() {
  test('starts loading, then holds the code', () async {
    final cubit = InviteCodeCubit(fetch: () async => 'K7M2QX');
    expect(cubit.state.status, InviteCodeStatus.loading);

    await cubit.load();
    expect(cubit.state.status, InviteCodeStatus.ready);
    expect(cubit.state.code, 'K7M2QX');
    await cubit.close();
  });

  test(
    'a failure or an empty code is «failed», and a retry recovers',
    () async {
      var attempt = 0;
      final cubit = InviteCodeCubit(
        fetch: () async {
          attempt++;
          if (attempt == 1) throw Exception('offline');
          if (attempt == 2) return '';
          return 'ABC234';
        },
      );

      await cubit.load();
      expect(cubit.state.status, InviteCodeStatus.failed);
      await cubit.load();
      expect(cubit.state.status, InviteCodeStatus.failed);
      await cubit.load();
      expect(cubit.state.code, 'ABC234');
      await cubit.close();
    },
  );

  test('a late answer after close is ignored', () async {
    final cubit = InviteCodeCubit(fetch: () async => 'K7M2QX');
    final pending = cubit.load();
    await cubit.close();
    await pending;
    expect(cubit.isClosed, isTrue);
  });
}
