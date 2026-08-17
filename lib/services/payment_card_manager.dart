import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/payment/payment_security.dart';
import 'payment_service.dart';
import 'subscription_service.dart';

/// إدارة البطاقات المحفوظة مع RLS وتدقيق وتشفير محلي.
/// Saved card manager with RLS enforcement, audit, and local encryption.
class PaymentCardManager {
  PaymentCardManager([SupabaseClient? sb])
      : _sb = sb ?? Supabase.instance.client,
        _pay = PaymentService(sb ?? Supabase.instance.client);

  final SupabaseClient _sb;
  final PaymentService _pay;

  String? get _uid => _sb.auth.currentUser?.id;

  /// alias — جلب بطاقات المستخدم (RLS عبر user_id).
  Future<List<Map<String, dynamic>>> getSavedCards() => listCards();

  Future<List<Map<String, dynamic>>> listCards() async {
    if (_uid == null) return [];
    final cards = await _pay.getSavedCards();
    return cards
        .where((c) => !PaymentService.isMockCardToken(c['card_token']))
        .map(_sanitizeForUi)
        .toList();
  }

  Map<String, dynamic> _sanitizeForUi(Map<String, dynamic> row) {
    final copy = Map<String, dynamic>.from(row);
    final token = '${copy['card_token'] ?? ''}';
    copy['card_token_masked'] = PaymentSecurity.maskToken(token);
    copy.remove('card_token');
    copy['is_expired'] = PaymentService.isCardExpired(row);
    copy['can_charge'] = PaymentService.canChargeSavedCard(row);
    copy['needs_reverify'] =
        PaymentService.isMockCardToken(row['card_token']) ||
        !PaymentService.isMoyasarReadyCardToken(row['card_token']);
    return copy;
  }

  Future<Map<String, dynamic>> updateCardLabel(
    String cardId,
    String label,
  ) =>
      updateLabel(cardId: cardId, label: label);

  Future<Map<String, dynamic>> setDefaultCard(String cardId) =>
      setDefault(cardId);

  Future<Map<String, dynamic>> updateLabel({
    required String cardId,
    String? label,
  }) async {
    final r = await _pay.updateCardLabel(cardId: cardId, label: label);
    if (r['ok'] == true) {
      await PaymentSecurity.auditCardEvent(
        sb: _sb,
        event: 'card_label_updated',
        cardId: cardId,
        payload: {'label': label},
      );
    }
    return r;
  }

  Future<Map<String, dynamic>> setDefault(String cardId) async {
    final r = await _pay.setDefaultCard(cardId);
    if (r['ok'] == true) {
      await PaymentSecurity.auditCardEvent(
        sb: _sb,
        event: 'card_set_default',
        cardId: cardId,
      );
    }
    return r;
  }

  Future<Map<String, dynamic>> deleteCard(String cardId) async {
    final r = await _pay.deleteCard(cardId);
    if (r['ok'] == true) {
      await PaymentSecurity.auditCardEvent(
        sb: _sb,
        event: 'card_deleted',
        cardId: cardId,
      );
    }
    return r;
  }

  /// إعادة التحقق — يوجّه المستخدم لإتمام دفع ببطاقة جديدة عبر ميسّر.
  Future<Map<String, dynamic>> reverifyCard(String cardId) async {
    await SubscriptionService(_sb).recordPaymentOutcome(
      event: 'card_reverify_requested',
      payload: {'card_id': cardId},
    );
    return markNeedsReverify(cardId);
  }

  /// يُعلِم أن البطاقة تحتاج إعادة تحقق (منتهية أو رمز وهمي).
  Future<Map<String, dynamic>> markNeedsReverify(String cardId) async {
    await SubscriptionService(_sb).recordPaymentOutcome(
      event: 'card_reverify_requested',
      payload: {'card_id': cardId},
    );
    return {'ok': true, 'action': 'checkout_new_card'};
  }

  /// يخزّن نسخة مشفّرة محلياً من معرّف البطاقة الافتراضية (اختياري).
  Future<void> cacheDefaultCardIdLocally(String cardId) async {
    if (cardId.trim().isEmpty) return;
    try {
      await PaymentSecurity.encryptForLocalCache(cardId);
    } catch (e) {
      if (kDebugMode) debugPrint('[PaymentCardManager] cache failed: $e');
    }
  }

  /// يُنظّف البطاقات الوهمية قبل عرض القائمة.
  Future<void> purgeMockCards() async {
    if (PaymentService.useMoyasarLiveFlow) {
      await _pay.purgeMockSavedCards();
    }
  }
}
