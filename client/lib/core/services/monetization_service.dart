import '../utils/persian_digits.dart';

abstract class MonetizationService {
  int get coinBalance;

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
  /// Store price in Toman (Bazaar/Myket bill in Rial = Toman × 10).
  final int priceToman;
  final ProductType type;
  final int? coinsAwarded;

  const Product({
    required this.id,
    required this.title,
    required this.priceToman,
    required this.type,
    this.coinsAwarded,
  });

  String get price => '${formatPersianNumber(priceToman)} تومان';
}

enum PurchaseStatus { success, failed, cancelled }

class PurchaseResult {
  final PurchaseStatus status;
  final String? error;

  const PurchaseResult({required this.status, this.error});
}

/// Mock implementation — swap for a real IAP provider in production. Ads live in `AdService`.
class MockMonetizationService implements MonetizationService {
  int _coins;

  MockMonetizationService({int initialCoins = 100}) : _coins = initialCoins;

  @override
  int get coinBalance => _coins;

  @override
  Future<List<Product>> getProducts() async {
    return const [
      Product(
        id: 'coins_100',
        title: '100 Coins',
        priceToman: 9000,
        type: ProductType.coins,
        coinsAwarded: 100,
      ),
      Product(
        id: 'coins_350',
        title: '350 Coins',
        priceToman: 25000,
        type: ProductType.coins,
        coinsAwarded: 350,
      ),
      Product(
        id: 'coins_1500',
        title: '1500 Coins',
        priceToman: 79000,
        type: ProductType.coins,
        coinsAwarded: 1500,
      ),
      Product(
        id: 'remove_ads',
        title: 'Remove Ads',
        priceToman: 15000,
        type: ProductType.removeAds,
      ),
      Product(
        id: 'premium_monthly',
        title: 'Premium — no ads + 200 coins/week',
        priceToman: 19000, // per month,
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
