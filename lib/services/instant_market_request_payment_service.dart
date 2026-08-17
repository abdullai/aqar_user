import 'package:supabase_flutter/supabase_flutter.dart';

/// دفع «طلب فوري» — 30 ر.س لكل طلب.
class InstantMarketRequestPaymentService {
  InstantMarketRequestPaymentService(this._sb);

  final SupabaseClient _sb;

  static const double priceSar = 30.0;

  Future<Map<String, dynamic>> createCheckout() async {
    try {
      final res = await _sb.rpc('create_instant_market_request_checkout');
      if (res is Map) {
        return Map<String, dynamic>.from(
          res.map((k, v) => MapEntry(k.toString(), v)),
        );
      }
      return {'ok': false, 'error': 'unexpected_response'};
    } catch (e) {
      return {'ok': false, 'error': e.toString()};
    }
  }

  Future<Map<String, dynamic>> getAvailableCredit() async {
    try {
      final res = await _sb.rpc('get_available_instant_market_request_credit');
      if (res is Map) {
        return Map<String, dynamic>.from(
          res.map((k, v) => MapEntry(k.toString(), v)),
        );
      }
      return {'ok': false, 'error': 'unexpected_response'};
    } catch (e) {
      return {'ok': false, 'error': e.toString()};
    }
  }

  Future<List<Map<String, dynamic>>> listMyCredits({int limit = 30}) async {
    try {
      final rows = await _sb
          .from('market_request_instant_credits')
          .select(
            'id, amount_sar, status, created_at, activated_at, consumed_at, refunded_at, market_request_id',
          )
          .order('created_at', ascending: false)
          .limit(limit);
      return (rows as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Future<Map<String, dynamic>> activateCredit(String billingTransactionId) async {
    try {
      final res = await _sb.rpc(
        'activate_instant_market_request_credit',
        params: {'p_billing_transaction_id': billingTransactionId},
      );
      if (res is Map) {
        return Map<String, dynamic>.from(
          res.map((k, v) => MapEntry(k.toString(), v)),
        );
      }
      return {'ok': false, 'error': 'unexpected_response'};
    } catch (e) {
      return {'ok': false, 'error': e.toString()};
    }
  }

  Future<Map<String, dynamic>> consumeCredit({
    required String creditId,
    required String marketRequestId,
  }) async {
    try {
      final res = await _sb.rpc(
        'consume_instant_market_request_credit',
        params: {
          'p_credit_id': creditId,
          'p_market_request_id': marketRequestId,
        },
      );
      if (res is Map) {
        return Map<String, dynamic>.from(
          res.map((k, v) => MapEntry(k.toString(), v)),
        );
      }
      return {'ok': false, 'error': 'unexpected_response'};
    } catch (e) {
      return {'ok': false, 'error': e.toString()};
    }
  }

  Future<Map<String, dynamic>> refundUnusedCredit(String creditId) async {
    try {
      final res = await _sb.rpc(
        'refund_unused_instant_market_request_credit',
        params: {'p_credit_id': creditId},
      );
      if (res is Map) {
        return Map<String, dynamic>.from(
          res.map((k, v) => MapEntry(k.toString(), v)),
        );
      }
      return {'ok': false, 'error': 'unexpected_response'};
    } catch (e) {
      return {'ok': false, 'error': e.toString()};
    }
  }
}

/// نتيجة الدفع لمرة واحدة — تُمرَّر للشاشة السابقة.
class OneTimePaymentResult {
  const OneTimePaymentResult({
    required this.ok,
    this.billingTransactionId,
    this.creditId,
    this.amountSar,
    this.error,
  });

  final bool ok;
  final String? billingTransactionId;
  final String? creditId;
  final double? amountSar;
  final String? error;

  factory OneTimePaymentResult.fromMap(Map<String, dynamic> m) {
    return OneTimePaymentResult(
      ok: m['ok'] == true,
      billingTransactionId: m['billing_transaction_id']?.toString(),
      creditId: m['credit_id']?.toString(),
      amountSar: m['amount_sar'] is num
          ? (m['amount_sar'] as num).toDouble()
          : double.tryParse('${m['amount_sar'] ?? ''}'),
      error: m['error']?.toString(),
    );
  }
}
