import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';
import 'package:logger/logger.dart';
import 'package:wordchain/core/network/api_endpoints.dart';
import 'package:wordchain/core/services/billing_gateway.dart';
import 'package:wordchain/core/utils/error_messages.dart';

enum StorePurchaseStatus { success, cancelled, failed }

class StorePurchaseResult {
  final StorePurchaseStatus status;

  /// Persian text to show (success or failure).
  final String message;

  /// New server balance after a coin pack; null otherwise.
  final int? coins;

  const StorePurchaseResult(this.status, this.message, {this.coins});
}

/// What the store sells. Ids must match the Cafe Bazaar panel and
/// `config.StoreProducts` on the server. «Remove ads» is intentionally absent:
/// the app has no ad-free state, so it is not for sale.
abstract final class StoreProducts {
  static const coins100 = 'coins_100';
  static const coins350 = 'coins_350';
  static const coins1500 = 'coins_1500';
  static const premiumMonthly = 'premium_monthly';

  static const consumables = {coins100, coins350, coins1500};
  static const subscriptions = {premiumMonthly};
}

/// Real-money purchases through Cafe Bazaar.
///
/// Flow: Bazaar's purchase screen → our server verifies the purchase token
/// with Bazaar and delivers the coins/premium (idempotent per token) → only
/// then the purchase is consumed, so the player can buy the pack again. If the
/// app dies between payment and delivery, [restore] finishes the job next time.
class StorePurchaseService with WidgetsBindingObserver {
  final BillingGateway _gateway;
  final Dio _dio;
  final String? Function() _userId;
  final void Function(int coins) _onCoins;
  final Logger _log;

  /// Minimum gap between automatic restores (resume is frequent; each one
  /// opens a connection to the Bazaar app).
  static const restoreGap = Duration(minutes: 5);

  bool _restoring = false;
  DateTime? _lastRestore;

  StorePurchaseService({
    required BillingGateway gateway,
    required Dio dio,
    required String? Function() userId,
    required void Function(int coins) onCoins,
    Logger? logger,
  }) : _gateway = gateway,
       _dio = dio,
       _userId = userId,
       _onCoins = onCoins,
       _log = logger ?? Logger();

  /// Restores on sign-in (and at launch when already signed in) and on every
  /// app resume. [userChanges] emits the signed-in user id, or null.
  void start(Stream<String?> userChanges) {
    WidgetsBinding.instance.addObserver(this);
    String? last;
    userChanges.listen((id) {
      if (id != null && id != last) unawaited(restore(force: true));
      last = id;
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(restore());
  }

  Future<StorePurchaseResult> buy(String productId) async {
    final userId = _userId();
    if (userId == null) return _failed('login_required');
    BillingItem item;
    try {
      item =
          StoreProducts.subscriptions.contains(productId)
              ? await _gateway.subscribe(productId, userId)
              : await _gateway.purchase(productId, userId);
    } on BillingCancelled {
      return const StorePurchaseResult(
        StorePurchaseStatus.cancelled,
        purchaseCancelledMessage,
      );
    } on BillingUnavailable {
      return _failed('store_missing');
    } catch (e) {
      _log.w('purchase failed', error: e);
      return _failed('purchase_failed');
    }
    // Money has moved from here on: a failure must say so.
    try {
      return await _deliver(item);
    } on DioException catch (e) {
      final code = apiErrorCode(e);
      _log.w('verify failed: $code');
      // A refusal is final; anything else is retried by restore().
      final final_ = const {
        'purchase_invalid',
        'purchase_already_claimed',
        'unknown_product',
      }.contains(code);
      return _failed(final_ ? code : 'purchase_not_delivered');
    } catch (e) {
      _log.w('deliver failed', error: e);
      return _failed('purchase_not_delivered');
    }
  }

  /// Sends the token to the server; on success consumes a coin pack.
  Future<StorePurchaseResult> _deliver(BillingItem item) async {
    final res = await _dio.post(
      ApiEndpoints.bazaarVerify,
      data: {'product_id': item.productId, 'purchase_token': item.token},
    );
    final data = (res.data as Map)['data'] as Map;
    final awarded = (data['coins_awarded'] as num?)?.toInt() ?? 0;
    final balance = (data['coins'] as num?)?.toInt();
    if (balance != null) _onCoins(balance);
    if (StoreProducts.consumables.contains(item.productId)) {
      try {
        await _gateway.consume(item.token);
      } catch (e) {
        // Already credited server-side; restore() consumes it later.
        _log.w('consume failed', error: e);
      }
    }
    final message =
        StoreProducts.subscriptions.contains(item.productId)
            ? premiumActivatedMessage
            : coinsAwardedMessage(awarded);
    return StorePurchaseResult(
      StorePurchaseStatus.success,
      message,
      coins: balance,
    );
  }

  /// Finishes purchases the app died in the middle of: unconsumed coin packs
  /// are verified (a repeat pays nothing) and consumed; active subscriptions
  /// are re-verified so a renewal extends premium. Silent, never throws.
  Future<void> restore({bool force = false}) async {
    if (_restoring || _userId() == null) return;
    final last = _lastRestore;
    if (!force &&
        last != null &&
        DateTime.now().difference(last) < restoreGap) {
      return;
    }
    _restoring = true;
    _lastRestore = DateTime.now();
    try {
      final owned = [
        ...await _gateway.ownedProducts(),
        ...await _gateway.ownedSubscriptions(),
      ];
      for (final item in owned) {
        if (item.refunded) continue;
        if (!StoreProducts.consumables.contains(item.productId) &&
            !StoreProducts.subscriptions.contains(item.productId)) {
          continue;
        }
        try {
          await _deliver(item);
        } catch (e) {
          // Someone else's token, a lapsed subscription, or no network: leave
          // it for the next resume.
          _log.d('restore skipped ${item.productId}: $e');
        }
      }
    } catch (e) {
      // Bazaar missing / unreachable: nothing to restore.
      _log.d('restore unavailable: $e');
    } finally {
      _restoring = false;
    }
  }

  StorePurchaseResult _failed(String code) =>
      StorePurchaseResult(StorePurchaseStatus.failed, errorMessageFor(code));
}
