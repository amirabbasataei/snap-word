import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wordchain/core/services/billing_gateway.dart';
import 'package:wordchain/core/services/store_purchase_service.dart';
import 'package:wordchain/core/utils/error_messages.dart';

class _Gateway implements BillingGateway {
  BillingItem? next;
  Object? purchaseError;
  List<BillingItem> owned = [];
  List<BillingItem> subs = [];
  final consumed = <String>[];
  bool consumeFails = false;
  String? boughtPayload;

  @override
  Future<void> connect() async {}

  @override
  Future<BillingItem> purchase(String productId, String payload) async {
    boughtPayload = payload;
    if (purchaseError != null) throw purchaseError!;
    return next!;
  }

  @override
  Future<BillingItem> subscribe(String productId, String payload) =>
      purchase(productId, payload);

  @override
  Future<void> consume(String token) async {
    if (consumeFails) throw const BillingFailed();
    consumed.add(token);
  }

  @override
  Future<List<BillingItem>> ownedProducts() async => owned;

  @override
  Future<List<BillingItem>> ownedSubscriptions() async => subs;
}

/// Answers `POST /payments/bazaar/verify` from a queue of (status, body).
class _Server implements HttpClientAdapter {
  final replies = <(int, Map<String, dynamic>)>[];
  final sent = <Map<String, dynamic>>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    sent.add(Map<String, dynamic>.from(options.data as Map));
    final (status, body) = replies.removeAt(0);
    if (status == 0) {
      throw DioException(
        requestOptions: options,
        type: DioExceptionType.connectionError,
      );
    }
    return ResponseBody.fromString(
      jsonEncode(body),
      status,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

(int, Map<String, dynamic>) _ok({
  int awarded = 0,
  int? coins,
  bool already = false,
}) => (
  200,
  {
    'data': {
      'coins_awarded': awarded,
      'already_processed': already,
      if (coins != null) 'coins': coins,
    },
  },
);

(int, Map<String, dynamic>) _err(int status, String code) => (
  status,
  {
    'error': {'code': code, 'message': 'x'},
  },
);

void main() {
  late _Gateway gateway;
  late _Server server;
  late List<int> balances;
  String? user;
  late StorePurchaseService service;

  setUp(() {
    gateway = _Gateway();
    server = _Server();
    balances = [];
    user = 'user-1';
    final dio = Dio(BaseOptions(baseUrl: 'http://test'))
      ..httpClientAdapter = server;
    service = StorePurchaseService(
      gateway: gateway,
      dio: dio,
      userId: () => user,
      onCoins: balances.add,
    );
  });

  test(
    'buys, verifies on the server, updates the balance, then consumes',
    () async {
      gateway.next = const BillingItem(
        productId: 'coins_350',
        token: 'tok',
        receiptJson: '{"purchaseToken":"tok"}',
        signature: 'sig-tok',
      );
      server.replies.add(_ok(awarded: 350, coins: 410));

      final r = await service.buy('coins_350');

      expect(r.status, StorePurchaseStatus.success);
      expect(r.message, coinsAwardedMessage(350));
      expect(balances, [410]);
      expect(gateway.consumed, ['tok']);
      expect(gateway.boughtPayload, 'user-1');
      expect(server.sent.single, {
        'product_id': 'coins_350',
        'purchase_data': '{"purchaseToken":"tok"}',
        'signature': 'sig-tok',
      });
    },
  );

  test('a subscription is verified but never consumed', () async {
    gateway.next = const BillingItem(productId: 'premium_monthly', token: 's');
    server.replies.add(_ok());

    final r = await service.buy('premium_monthly');

    expect(r.status, StorePurchaseStatus.success);
    expect(r.message, premiumActivatedMessage);
    expect(gateway.consumed, isEmpty);
  });

  test('guest cannot buy; nothing reaches the store', () async {
    user = null;
    final r = await service.buy('coins_100');
    expect(r.status, StorePurchaseStatus.failed);
    expect(r.message, errorMessageFor('login_required'));
    expect(gateway.boughtPayload, isNull);
  });

  test(
    'cancel and a missing Bazaar app are distinct, and nothing is verified',
    () async {
      gateway.purchaseError = const BillingCancelled();
      expect(
        (await service.buy('coins_100')).status,
        StorePurchaseStatus.cancelled,
      );

      gateway.purchaseError = const BillingUnavailable();
      final r = await service.buy('coins_100');
      expect(r.status, StorePurchaseStatus.failed);
      expect(r.message, errorMessageFor('store_missing'));
      expect(server.sent, isEmpty);
    },
  );

  test('a refused purchase is final and is not consumed', () async {
    gateway.next = const BillingItem(productId: 'coins_100', token: 't');
    server.replies.add(_err(400, 'purchase_invalid'));
    final r = await service.buy('coins_100');
    expect(r.message, errorMessageFor('purchase_invalid'));
    expect(gateway.consumed, isEmpty);
  });

  test(
    'paid but offline: says the payment is pending, keeps the purchase',
    () async {
      gateway.next = const BillingItem(productId: 'coins_100', token: 't');
      server.replies.add((0, {}));
      final r = await service.buy('coins_100');
      expect(r.status, StorePurchaseStatus.failed);
      expect(r.message, errorMessageFor('purchase_not_delivered'));
      expect(gateway.consumed, isEmpty);
      expect(balances, isEmpty);
    },
  );

  test('consume failing after delivery still reports success', () async {
    gateway
      ..next = const BillingItem(productId: 'coins_100', token: 't')
      ..consumeFails = true;
    server.replies.add(_ok(awarded: 100, coins: 110));
    expect(
      (await service.buy('coins_100')).status,
      StorePurchaseStatus.success,
    );
  });

  group('restore', () {
    test(
      'verifies and consumes a pack left unconsumed; skips refunds and unknown ids',
      () async {
        gateway.owned = const [
          BillingItem(
            productId: 'coins_350',
            token: 'left',
            signature: 'sig-left',
          ),
          BillingItem(
            productId: 'coins_100',
            token: 'refunded',
            refunded: true,
          ),
          BillingItem(productId: 'remove_ads', token: 'other'),
        ];
        server.replies.add(_ok(already: true, coins: 500));

        await service.restore(force: true);

        expect(server.sent.map((m) => m['signature']), ['sig-left']);
        expect(gateway.consumed, ['left']);
        expect(balances, [500]);
      },
    );

    test(
      'an active subscription is re-verified so renewals extend premium',
      () async {
        gateway.subs = const [
          BillingItem(productId: 'premium_monthly', token: 'sub'),
        ];
        server.replies.add(_ok());
        await service.restore(force: true);
        expect(server.sent.single['product_id'], 'premium_monthly');
        expect(gateway.consumed, isEmpty);
      },
    );

    test(
      'a token the server rejects is not consumed and does not stop the rest',
      () async {
        gateway.owned = const [
          BillingItem(productId: 'coins_100', token: 'theirs'),
          BillingItem(productId: 'coins_350', token: 'mine'),
        ];
        server.replies
          ..add(_err(409, 'purchase_already_claimed'))
          ..add(_ok(already: true, coins: 7));
        await service.restore(force: true);
        expect(gateway.consumed, ['mine']);
      },
    );

    test('is throttled between automatic runs and silent for guests', () async {
      await service.restore(force: true);
      gateway.owned = const [BillingItem(productId: 'coins_100', token: 'x')];
      await service.restore(); // within restoreGap → skipped
      expect(server.sent, isEmpty);

      user = null;
      await service.restore(force: true);
      expect(server.sent, isEmpty);
    });
  });
}
