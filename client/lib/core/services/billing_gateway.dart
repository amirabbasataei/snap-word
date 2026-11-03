import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/services.dart';
import 'package:flutter_poolakey/flutter_poolakey.dart';

/// One purchase held by the store.
class BillingItem {
  final String productId;
  final String token;
  final String payload;

  /// Bazaar's signed receipt (Poolakey `originalJson`) and its base64
  /// signature (`dataSignature`); the server verifies them with the app's RSA
  /// public key.
  final String receiptJson;
  final String signature;

  /// Bazaar reports refunded purchases too; they must not be redeemed.
  final bool refunded;

  const BillingItem({
    required this.productId,
    required this.token,
    this.payload = '',
    this.receiptJson = '',
    this.signature = '',
    this.refunded = false,
  });
}

/// The player closed the store's purchase screen.
class BillingCancelled implements Exception {
  const BillingCancelled();
}

/// The store app is missing or could not be reached (Bazaar not installed,
/// not on Android, connection refused).
class BillingUnavailable implements Exception {
  const BillingUnavailable();
}

/// The store started the purchase but it failed.
class BillingFailed implements Exception {
  const BillingFailed();
}

/// Thin seam over the store SDK so [StorePurchaseService] can be tested.
abstract class BillingGateway {
  Future<void> connect();
  Future<BillingItem> purchase(String productId, String payload);
  Future<BillingItem> subscribe(String productId, String payload);
  Future<void> consume(String token);
  Future<List<BillingItem>> ownedProducts();
  Future<List<BillingItem>> ownedSubscriptions();
}

/// Cafe Bazaar through Poolakey. The app's public RSA key (Bazaar panel →
/// in-app payments) is handed to Poolakey so it rejects forged purchase
/// results on the device; the server repeats the check on the signed receipt
/// and is the authoritative one. The key is public (it ships in every APK), so
/// it lives in the code. Empty = no on-device check, the server still checks.
class PoolakeyGateway implements BillingGateway {
  static const rsaKey =
      'MIHNMA0GCSqGSIb3DQEBAQUAA4G7ADCBtwKBrwCw8xIuy4pER4wLgmO9ohpSLVg3WmeA6bUqD1QzwOsPymHXEQVs0fcklAFA0SJGgwUJ1mLfD5oYbDRwa3vwuYkuoyLcBdiRVC5+OwZg8P9sf8rB2TDWPo1Vw5RhTMMBsTfP6ch7bbJ0LzNLreCb9epOIyE1ekdAVu1CDqaYRR6zmiKq74vAyt12bKxj0RbcY5AmgZ0hjaLaObRm2RWs0Fcv/7NbyOnh/HeGTrSFx1UCAwEAAQ==';

  static const _connectTimeout = Duration(seconds: 8);
  bool _connected = false;

  @override
  Future<void> connect() async {
    if (_connected) return;
    if (!Platform.isAndroid) throw const BillingUnavailable();
    final done = Completer<bool>();
    void finish(bool ok) {
      if (!done.isCompleted) done.complete(ok);
    }

    // The plugin's native `connect` never answers the method call itself (the
    // outcome arrives through the callbacks), so awaiting the returned future
    // would hang forever. Only its errors matter.
    unawaited(
      FlutterPoolakey.connect(
        rsaKey.isEmpty ? null : rsaKey,
        onSucceed: () => finish(true),
        onFailed: () => finish(false),
        onDisconnected: () => _connected = false,
      ).then<void>((_) {}, onError: (Object _) => finish(false)),
    );
    final ok = await done.future.timeout(
      _connectTimeout,
      onTimeout: () => false,
    );
    if (!ok) throw const BillingUnavailable();
    _connected = true;
  }

  Never _map(PlatformException e) {
    if (e.code == 'PURCHASE_CANCELLED') throw const BillingCancelled();
    throw const BillingFailed();
  }

  BillingItem _item(PurchaseInfo p) => BillingItem(
    productId: p.productId,
    token: p.purchaseToken,
    payload: p.payload,
    receiptJson: p.originalJson,
    signature: p.dataSignature,
    refunded: p.purchaseState == PurchaseState.REFUNDED,
  );

  @override
  Future<BillingItem> purchase(String productId, String payload) async {
    await connect();
    try {
      return _item(await FlutterPoolakey.purchase(productId, payload: payload));
    } on PlatformException catch (e) {
      _map(e);
    }
  }

  @override
  Future<BillingItem> subscribe(String productId, String payload) async {
    await connect();
    try {
      return _item(
        await FlutterPoolakey.subscribe(productId, payload: payload),
      );
    } on PlatformException catch (e) {
      _map(e);
    }
  }

  @override
  Future<void> consume(String token) async {
    await connect();
    try {
      await FlutterPoolakey.consume(token);
    } on PlatformException {
      throw const BillingFailed();
    }
  }

  @override
  Future<List<BillingItem>> ownedProducts() async {
    await connect();
    try {
      return (await FlutterPoolakey.getAllPurchasedProducts())
          .map(_item)
          .toList();
    } on PlatformException {
      throw const BillingFailed();
    }
  }

  @override
  Future<List<BillingItem>> ownedSubscriptions() async {
    await connect();
    try {
      return (await FlutterPoolakey.getAllSubscribedProducts())
          .map(_item)
          .toList();
    } on PlatformException {
      throw const BillingFailed();
    }
  }
}
