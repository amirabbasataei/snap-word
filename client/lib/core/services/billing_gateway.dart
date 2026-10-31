import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/services.dart';
import 'package:flutter_poolakey/flutter_poolakey.dart';

/// One purchase held by the store.
class BillingItem {
  final String productId;
  final String token;
  final String payload;

  /// Bazaar reports refunded purchases too; they must not be redeemed.
  final bool refunded;

  const BillingItem({
    required this.productId,
    required this.token,
    this.payload = '',
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

/// Cafe Bazaar through Poolakey. The local RSA signature check is switched off
/// (key `null`): every purchase is verified by our server against Bazaar's
/// developer API instead, which is the authoritative check.
class PoolakeyGateway implements BillingGateway {
  static const _connectTimeout = Duration(seconds: 8);
  bool _connected = false;

  @override
  Future<void> connect() async {
    if (_connected) return;
    if (!Platform.isAndroid) throw const BillingUnavailable();
    final done = Completer<bool>();
    try {
      await FlutterPoolakey.connect(
        null,
        onSucceed: () {
          if (!done.isCompleted) done.complete(true);
        },
        onFailed: () {
          if (!done.isCompleted) done.complete(false);
        },
        onDisconnected: () => _connected = false,
      );
    } on PlatformException {
      throw const BillingUnavailable();
    }
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
