import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:wordchain/core/services/ad_service.dart';
import 'package:wordchain/features/auth/cubit/auth_cubit.dart';
import 'package:wordchain/features/game/data/game_repository.dart';
import 'package:wordchain/features/rewards/data/rewards_repository.dart';

import '../../helpers/game_fakes.dart';

RewardItem reward(
  String id,
  String kind, {
  String detail = '',
  int coins = 30,
  bool claimed = false,
}) => RewardItem(
  id: id,
  kind: kind,
  detail: detail,
  coins: coins,
  claimed: claimed,
  createdAt: DateTime.utc(2026, 10, 25),
);

/// One of every kind, a claimed one among them, in the server's order.
List<RewardItem> sampleRewards() => [
  reward('a', 'daily_login', coins: 10),
  reward('b', 'streak', detail: '7', coins: 100, claimed: true),
  reward('c', 'weekly_rank', detail: '2', coins: 300),
  reward('d', 'daily_rank', detail: '1', coins: 100),
  reward('e', 'daily_done', coins: 10),
  reward('f', 'referral_reward', detail: 'سارا', coins: 50),
  reward('g', 'admin_gift', coins: 200),
];

/// Signed-in player whose balance the screen reads and the cubit writes.
class FakeRewardsAuth extends FakeAuthCubit {
  AuthState _state;
  final _changes = StreamController<AuthState>.broadcast();
  final bool guest;

  FakeRewardsAuth({int coins = 90, this.guest = false})
    : _state =
          guest
              ? const AuthGuest()
              : AuthAuthenticated(userId: 'me', username: 'آرش', coins: coins),
      super();

  @override
  AuthState get state => _state;

  @override
  Stream<AuthState> get stream => _changes.stream;

  @override
  bool get isGuest => guest;

  void _set(AuthState s) {
    _state = s;
    _changes.add(s);
  }

  @override
  Future<void> setCoins(int coins) async {
    final s = _state;
    if (s is AuthAuthenticated) _set(s.copyWith(coins: coins));
  }

  @override
  Future<void> creditCoins(int amount) async {
    final s = _state;
    if (s is AuthAuthenticated) _set(s.copyWith(coins: s.coins + amount));
  }
}

class FakeRewardsRepo extends Fake implements RewardsRepository {
  List<RewardItem> items;
  int coins;
  RewardsException? fetchError;
  Completer<void>? fetchGate;
  Completer<void>? claimGate;
  RewardsException? claimError;
  int fetches = 0;
  final claimed = <String>[];

  FakeRewardsRepo(this.items, {this.coins = 90});

  @override
  Future<RewardsSnapshot> fetch() async {
    fetches++;
    await fetchGate?.future;
    final e = fetchError;
    if (e != null) throw e;
    return RewardsSnapshot(items: List.of(items), coins: coins);
  }

  @override
  Future<int> claim(String id) async {
    await claimGate?.future;
    final e = claimError;
    if (e != null) throw e;
    claimed.add(id);
    return items.firstWhere((i) => i.id == id).coins;
  }
}

class FakeRewardedAds extends Fake implements AdService {
  @override
  final bool rewardedEnabled;
  bool watched = true;
  int shown = 0;

  FakeRewardedAds({this.rewardedEnabled = false});

  @override
  Future<bool> showRewardedAd() async {
    shown++;
    return watched;
  }
}

class FakeAdGameRepo extends Fake implements GameRepository {
  int balance = 500;

  @override
  Future<int> claimRewardedAd() async => balance;
}
