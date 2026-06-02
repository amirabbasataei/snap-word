abstract class MonetizationService {
  int get coinBalance;

  /// Returns true if the user watched the full ad.
  Future<bool> showRewardedAd();

  /// Shows an interstitial ad between sessions (no-op in mock).
  Future<void> showInterstitialAd();

  Future<List<Product>> getProducts();
  Future<PurchaseResult> purchase(String productId);

  /// Deducts [amount] from the local coin balance. Returns false if insufficient.
  bool spendCoins(int amount);

  void awardCoins(int amount);
}

enum ProductType { coins, removeAds, premium }

class Product {
  final String id;
  final String title;
  final String price;
  final ProductType type;
  final int? coinsAwarded;

  const Product({
    required this.id,
    required this.title,
    required this.price,
    required this.type,
    this.coinsAwarded,
  });
}

enum PurchaseStatus { success, failed, cancelled }

class PurchaseResult {
  final PurchaseStatus status;
  final String? error;

  const PurchaseResult({required this.status, this.error});
}

/// Mock implementation — swap for AdMob + RevenueCat in production.
class MockMonetizationService implements MonetizationService {
  int _coins;

  MockMonetizationService({int initialCoins = 100}) : _coins = initialCoins;

  @override
  int get coinBalance => _coins;

  @override
  Future<bool> showRewardedAd() async {
    // Always succeeds in mock; real implementation shows an AdMob rewarded ad.
    await Future.delayed(const Duration(milliseconds: 500));
    return true;
  }

  @override
  Future<void> showInterstitialAd() async {
    // No-op in mock; real implementation shows an AdMob interstitial.
    await Future.delayed(const Duration(milliseconds: 200));
  }

  @override
  Future<List<Product>> getProducts() async {
    return const [
      Product(
        id: 'coins_099',
        title: '100 Coins',
        price: '\$0.99',
        type: ProductType.coins,
        coinsAwarded: 100,
      ),
      Product(
        id: 'coins_299',
        title: '350 Coins',
        price: '\$2.99',
        type: ProductType.coins,
        coinsAwarded: 350,
      ),
      Product(
        id: 'coins_999',
        title: '1500 Coins',
        price: '\$9.99',
        type: ProductType.coins,
        coinsAwarded: 1500,
      ),
      Product(
        id: 'remove_ads',
        title: 'Remove Ads',
        price: '\$2.99',
        type: ProductType.removeAds,
      ),
      Product(
        id: 'premium_monthly',
        title: 'Premium — no ads + 200 coins/week',
        price: '\$3.99/mo',
        type: ProductType.premium,
      ),
    ];
  }

  @override
  Future<PurchaseResult> purchase(String productId) async {
    await Future.delayed(const Duration(milliseconds: 300));
    final products = await getProducts();
    final product = products.where((p) => p.id == productId).firstOrNull;
    if (product == null) {
      return const PurchaseResult(
        status: PurchaseStatus.failed,
        error: 'Product not found',
      );
    }
    if (product.type == ProductType.coins && product.coinsAwarded != null) {
      awardCoins(product.coinsAwarded!);
    }
    return const PurchaseResult(status: PurchaseStatus.success);
  }

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
