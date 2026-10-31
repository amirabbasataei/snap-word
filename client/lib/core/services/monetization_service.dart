abstract class MonetizationService {
  int get coinBalance;

  /// Deducts [amount] from the local coin balance. Returns false if insufficient.
  bool spendCoins(int amount);

  void awardCoins(int amount);
}

/// Local coin balance used by the solo «continue with coins» flow. Real-money
/// purchases live in `StorePurchaseService`; ads in `AdService`.
class MockMonetizationService implements MonetizationService {
  int _coins;

  MockMonetizationService({int initialCoins = 100}) : _coins = initialCoins;

  @override
  int get coinBalance => _coins;

  @override
  bool spendCoins(int amount) {
    if (_coins < amount) return false;
    _coins -= amount;
    return true;
  }

  @override
  void awardCoins(int amount) {
    _coins += amount;
  }
}
