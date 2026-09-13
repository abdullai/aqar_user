import 'package:flutter_test/flutter_test.dart';

import 'package:aqar_user/core/payment/checkout_offer.dart';
import 'package:aqar_user/core/payment/invoice_document.dart';
import 'package:aqar_user/core/payment/plan_price_resolver.dart';

void main() {
  group('CheckoutOffer', () {
    test('auto-pay 10% on 1000 becomes 900 and shows only applied rows', () {
      final offer = CheckoutOffer.fromRpc({
        'ok': true,
        'base_price': 1000,
        'final_amount': 900,
        'auto_pay_discount_pct': 10,
        'auto_pay_discount_sar': 100,
        'show_auto_pay': true,
        'applied_discount_kind': 'auto_pay',
        'discount_sar': 100,
        'promo_discount_sar': 0,
        'has_eligible_promos': false,
        'eligible_codes': [],
      });

      expect(offer.ok, isTrue);
      expect(offer.basePrice, 1000);
      expect(offer.finalAmount, 900);
      expect(offer.showAutoPayRow, isTrue);
      expect(offer.showPromoRow, isFalse);
      expect(offer.discountSar, 100);
      expect(offer.showBeforeDiscount, isTrue);
      expect(offer.discountLabel(isAr: true), 'خصم تفعيل التجديد التلقائي');
    });

    test('promo 5% with auto-pay 10% does not stack when kind is auto_pay', () {
      final offer = CheckoutOffer.fromRpc({
        'ok': true,
        'base_price': 1000,
        'final_amount': 900,
        'auto_pay_discount_pct': 10,
        'auto_pay_discount_sar': 100,
        'show_auto_pay': true,
        'applied_discount_kind': 'auto_pay',
        'promo_skipped': 'auto_pay_better',
        'promo_discount_sar': 0,
        'discount_sar': 100,
        'eligible_codes': [
          {'code': 'WELCOME5', 'percent': 5, 'kind': 'percent_off'},
        ],
      });

      expect(offer.finalAmount, 900);
      expect(offer.showPromoRow, isFalse);
      expect(offer.hasEligiblePromos, isTrue);
      expect(offer.eligibleCodes.first.code, 'WELCOME5');
    });

    test('promo 15% hides auto-pay and uses coupon amount', () {
      final offer = CheckoutOffer.fromRpc({
        'ok': true,
        'base_price': 1000,
        'final_amount': 850,
        'auto_pay_discount_sar': 0,
        'show_auto_pay': false,
        'applied_discount_kind': 'promo',
        'promo_code': 'SAVE15',
        'promo_discount_sar': 150,
        'promo_percent': 15,
        'discount_sar': 150,
      });

      expect(offer.showAutoPay, isFalse);
      expect(offer.showAutoPayRow, isFalse);
      expect(offer.showPromoRow, isTrue);
      expect(offer.finalAmount, 850);
      expect(offer.showBeforeDiscount, isTrue);
      expect(offer.discountLabel(isAr: true), 'خصم كود الخصم');
    });

    test('promo field hides when auto-pay percent is better and not yet applied', () {
      final offer = CheckoutOffer.fromRpc({
        'ok': true,
        'base_price': 1000,
        'final_amount': 900,
        'auto_pay_discount_pct': 10,
        'applied_discount_kind': 'auto_pay',
        'has_eligible_promos': true,
        'eligible_codes': [
          {'code': 'WELCOME5', 'percent': 5, 'kind': 'percent_off'},
        ],
      });
      expect(
        offer.shouldShowPromoField(
          autoRenewOn: true,
          autoPayPercent: 10,
          promoAlreadyApplied: false,
        ),
        isFalse,
      );
      expect(
        offer.shouldShowPromoField(
          autoRenewOn: false,
          autoPayPercent: 10,
          promoAlreadyApplied: false,
        ),
        isTrue,
      );
      expect(offer.isBetterThanAutoPay(10), isFalse);
    });

    test('turning auto-renew off restores promo field without waiting for a new quote', () {
      const offer = CheckoutOffer(
        ok: true,
        basePrice: 1000,
        finalAmount: 900,
        autoPayPct: 10,
        hasEligiblePromos: true,
        eligibleCodes: [
          CheckoutPromoOption(code: 'WELCOME5', percent: 5),
        ],
      );
      var autoRenewOn = true;
      expect(
        offer.shouldShowPromoField(
          autoRenewOn: autoRenewOn,
          autoPayPercent: 10,
          promoAlreadyApplied: false,
        ),
        isFalse,
      );
      autoRenewOn = false;
      expect(
        offer.shouldShowPromoField(
          autoRenewOn: autoRenewOn,
          autoPayPercent: 10,
          promoAlreadyApplied: false,
        ),
        isTrue,
      );
    });

    test('better promo than auto-pay is flagged while auto-renew is on', () {
      final offer = CheckoutOffer.fromRpc({
        'ok': true,
        'base_price': 1000,
        'final_amount': 850,
        'auto_pay_discount_pct': 10,
        'applied_discount_kind': 'auto_pay',
        'has_eligible_promos': true,
        'eligible_codes': [
          {'code': 'SAVE15', 'percent': 15, 'kind': 'percent_off'},
        ],
      });
      expect(offer.isBetterThanAutoPay(10), isTrue);
      expect(
        offer.shouldShowPromoField(
          autoRenewOn: true,
          autoPayPercent: 10,
          promoAlreadyApplied: false,
        ),
        isTrue,
      );
    });

    test('promo field stays when a better code is already applied', () {
      final offer = CheckoutOffer.fromRpc({
        'ok': true,
        'base_price': 1000,
        'final_amount': 850,
        'applied_discount_kind': 'promo',
        'promo_code': 'SAVE15',
        'promo_discount_sar': 150,
        'has_eligible_promos': true,
        'eligible_codes': [
          {'code': 'SAVE15', 'percent': 15, 'kind': 'percent_off'},
        ],
      });
      expect(
        offer.shouldShowPromoField(
          autoRenewOn: true,
          autoPayPercent: 10,
          promoAlreadyApplied: true,
        ),
        isTrue,
      );
    });

    test('filters uuid-like catalog ids from eligible codes', () {
      final codes = CheckoutPromoOption.listFrom([
        {'code': 'WELCOME5', 'percent': 5},
        {'code': 'a1b2c3d4-e5f6-7890-abcd-ef1234567890', 'percent': 20},
      ]);
      expect(codes.map((e) => e.code), contains('WELCOME5'));
      expect(
        codes.any((e) => e.code.contains('-') && e.code.length > 30),
        isFalse,
      );
    });
  });

  group('PlanPriceResolver does not replace server', () {
    test('local auto-pay math exists but checkout must prefer server final', () {
      final r = PlanPriceResolver({
        'price_monthly': 1000,
        'price_yearly': 10000,
        'auto_pay_discount_percent': 10,
      });
      expect(r.chargeAmount(period: 'monthly', withAutoPay: true), 900);
      expect(r.chargeAmount(period: 'yearly', withAutoPay: true), 10000);
      expect(r.chargeAmount(period: 'one_time', withAutoPay: true), 1000);
    });
  });

  group('InvoiceDocument discount labels from gateway_response', () {
    test('reads auto-pay and promo from stored offer without recalculating', () {
      final doc = InvoiceDocument.fromRow({
        'invoice_number': 'INV-20260910-000010',
        'amount': 900,
        'subtotal_sar': 1000,
        'discount_sar': 100,
        'status': 'success',
        'gateway_response': {
          'applied_discount_kind': 'auto_pay',
          'auto_pay_discount_sar': 100,
          'auto_pay_discount_pct': 10,
          'discount_label_ar': 'خصم الدفع التلقائي',
          'discount_label_en': 'Auto-pay discount',
        },
      }, isAr: true);

      expect(doc.amount, 900);
      expect(doc.discount, 100);
      expect(doc.showDiscount, isTrue);
      expect(doc.showAutoPayDiscount, isTrue);
      expect(doc.showCombinedDiscount, isFalse);
      expect(doc.autoPayDiscountSar, 100);
      expect(doc.discountLabel(isAr: true), 'خصم تفعيل التجديد التلقائي');
      expect(doc.discountLabel(isAr: false), 'Auto-renew activation discount');
      expect(
        doc.autoPayDiscountLabel(isAr: true),
        'خصم تفعيل التجديد التلقائي',
      );
    });

    test('promo invoice shows code not UUID', () {
      final doc = InvoiceDocument.fromRow({
        'invoice_number': 'INV-20260910-000011',
        'amount': 850,
        'subtotal_sar': 1000,
        'discount_sar': 150,
        'status': 'success',
        'gateway_response': {
          'applied_discount_kind': 'promo',
          'promo_code': 'SAVE15',
          'promo_discount_sar': 150,
          'discount_label_ar': 'خصم كود: SAVE15',
          'discount_label_en': 'Discount code: SAVE15',
        },
      }, isAr: false);

      expect(doc.promoCode, 'SAVE15');
      expect(doc.promoDiscountSar, 150);
      expect(doc.discountLabel(isAr: false), 'Promo code discount');
    });
  });
}
