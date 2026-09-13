import 'package:flutter_test/flutter_test.dart';

import 'package:aqar_user/core/payment/invoice_copy.dart';
import 'package:aqar_user/core/payment/invoice_document.dart';
import 'package:aqar_user/core/utils/app_money.dart';
import 'package:aqar_user/services/billing_transaction_repository.dart';
import 'package:aqar_user/services/payment_service.dart';

void main() {
  group('InvoiceDocument official number', () {
    test('uses per-user sequence and never falls back to UUID', () {
      const uuid = 'a1b2c3d4-e5f6-7890-abcd-ef1234567890';
      final doc = InvoiceDocument.fromRow({
        'id': uuid,
        'user_invoice_seq': 1,
        'invoice_number': 'INV-20260910-000123',
        'amount': 199.5,
        'currency': 'SAR',
        'status': 'success',
        'payment_method': 'mada',
        'paid_at': '2026-09-10T10:00:00Z',
      }, isAr: true);

      expect(doc.invoiceNumber, '1');
      expect(doc.displayInvoiceNumber, '1');
      expect(doc.pdfFileName, 'Invoice_1.pdf');
      expect(doc.qrPayload.contains('1'), isTrue);
      expect(doc.qrPayload.contains('INV-20260910-000123'), isFalse);
      expect(doc.qrPayload.contains(uuid), isFalse);
      expect(doc.amount, 199.5);
    });

    test('old row without invoice_number does not invent a serial or UUID', () {
      const uuid = 'a1b2c3d4-e5f6-7890-abcd-ef1234567890';
      final ar = InvoiceDocument.fromRow({
        'id': uuid,
        'amount': 10,
        'status': 'success',
      }, isAr: true);
      final en = InvoiceDocument.fromRow({
        'id': uuid,
        'amount': 10,
        'status': 'success',
      }, isAr: false);

      expect(ar.invoiceNumber, isEmpty);
      expect(ar.displayInvoiceNumber, 'غير متوفر');
      expect(en.displayInvoiceNumber, 'Unavailable');
      expect(ar.pdfFileName, 'Invoice_pending.pdf');
      expect(ar.qrPayload.contains(uuid), isFalse);
    });

    test('hides zero discount and does not add VAT', () {
      final doc = InvoiceDocument.fromRow({
        'user_invoice_seq': 1,
        'amount': 100,
        'subtotal_sar': 100,
        'discount_sar': 0,
        'vat_sar': 0,
        'fees_sar': 0,
        'vat_included': true,
        'status': 'success',
      }, isAr: true);

      expect(doc.showDiscount, isFalse);
      expect(doc.showVat, isFalse);
      expect(doc.showFees, isFalse);
      expect(doc.showSubtotal, isFalse);
      expect(doc.vatIncluded, isTrue);
      expect(doc.amount, 100);
    });

    test('shows discount when present and keeps server amount', () {
      final doc = InvoiceDocument.fromRow({
        'user_invoice_seq': 2,
        'amount': 80,
        'subtotal_sar': 100,
        'discount_sar': 20,
        'status': 'success',
      }, isAr: false);

      expect(doc.showDiscount, isTrue);
      expect(doc.showSubtotal, isTrue);
      expect(doc.amount, 80);
      expect(doc.discount, 20);
    });

    test('refunded amount is separate from paid total', () {
      final doc = InvoiceDocument.fromRow({
        'user_invoice_seq': 3,
        'amount': 150,
        'refund_amount': 150,
        'status': 'refunded',
      }, isAr: true);

      expect(doc.statusCode, 'refunded');
      expect(doc.statusLabel, 'مسترجعة');
      expect(doc.isEligibleRevenue(), isFalse);
      expect(doc.showRefund, isTrue);
    });

    test('QR payload never includes card secrets', () {
      final doc = InvoiceDocument.fromRow({
        'id': 'a1b2c3d4-e5f6-7890-abcd-ef1234567890',
        'user_invoice_seq': 123,
        'amount': 50,
        'status': 'success',
        'payment_method': 'card',
        'gateway_transaction_id': 'moyasar_abc',
      }, isAr: true);
      expect(doc.qrPayload.toLowerCase().contains('cvv'), isFalse);
      expect(doc.qrPayload.contains('a1b2c3d4'), isFalse);
    });
  });

  group('InvoiceCopy status and method', () {
    test('maps technical statuses to user labels', () {
      expect(InvoiceCopy.statusLabel('success', isAr: true), 'مدفوعة');
      expect(InvoiceCopy.statusLabel('paid', isAr: false), 'Paid');
      expect(InvoiceCopy.statusLabel('expired', isAr: true), 'منتهية');
      expect(InvoiceCopy.statusLabel('voided', isAr: false), 'Voided');
      expect(InvoiceCopy.statusLabel('abandoned', isAr: true), 'غير مكتملة');
    });

    test('empty payment method is unavailable not guessed', () {
      expect(InvoiceCopy.methodLabel('', isAr: true), 'غير متوفر');
      expect(InvoiceCopy.methodLabel('', isAr: false), 'Unavailable');
    });

    test('purpose, statement and period do not duplicate', () {
      expect(InvoiceCopy.purposeLabel('renew', isAr: true), 'تجديد اشتراك');
      expect(InvoiceCopy.purposeLabel('upgrade', isAr: true), 'ترقية الباقة');
      expect(InvoiceCopy.purposeLabel('subscribe_new', isAr: true), 'اشتراك جديد');
      final statement = InvoiceCopy.statementForPlan('ذهبي', isAr: true);
      expect(statement.contains('ذهبي'), isTrue);
      expect(statement.contains('من '), isFalse);
      final period = InvoiceCopy.periodWithRange(
        periodRaw: 'monthly',
        start: DateTime(2026, 9, 1),
        end: DateTime(2026, 10, 1),
        isAr: true,
      );
      expect(period.startsWith('شهري'), isTrue);
      expect(period.contains('2026/09/01'), isTrue);
      expect(period.contains('2026/10/01'), isTrue);
      expect(InvoiceCopy.stripBidi('\u20671/10\u2069'), '1/10');
    });

    test('visa mastercard mada and saved card labels', () {
      expect(InvoiceCopy.methodLabel('visa', isAr: true), 'فيزا');
      expect(InvoiceCopy.methodLabel('mastercard', isAr: true), 'ماستركارد');
      expect(InvoiceCopy.methodLabel('mada', isAr: true), 'مدى');
      expect(InvoiceCopy.methodLabel('saved', isAr: true), 'بطاقة محفوظة');
    });
  });

  group('AppMoney PDF and export', () {
    test('PDF uses the language-aware currency format', () {
      final ar = AppMoney.formatForPdf(12.5, isAr: true);
      final en = AppMoney.formatForPdf(12.5, isAr: false);
      expect(ar.contains('ر.س'), isFalse);
      expect(ar.contains('SAR'), isFalse);
      expect(ar.contains(AppMoney.saudiRiyalSignCompat), isTrue);
      expect(ar.contains('12.5'), isTrue);
      expect(en.contains('SAR'), isTrue);
      expect(en.contains('ر.س'), isFalse);
      expect(en.contains(AppMoney.saudiRiyalSignCompat), isFalse);
    });

    test('export Arabic uses the compatible riyal mark', () {
      final s = AppMoney.formatForExport(12.5, isAr: true);
      expect(s.contains(AppMoney.saudiRiyalSignUnicode), isFalse);
      expect(s.contains(AppMoney.saudiRiyalSignCompat), isTrue);
      expect(s.contains('ريال'), isFalse);
    });
  });

  group('BillingTransactionRepository tabs', () {
    test('expired stays in failed tab group', () {
      expect(
        BillingTransactionRepository.normalizedStatus({'status': 'expired'}),
        'failed',
      );
    });
  });

  group('PaymentService.buildInvoicePdf', () {
    TestWidgetsFlutterBinding.ensureInitialized();

    test('Arabic PDF bytes include per-user invoice number not UUID', () async {
      final uuid = 'a1b2c3d4-e5f6-7890-abcd-ef1234567890';
      final bytes = await PaymentService.buildInvoicePdf(
        title: 'فاتورة اشتراك جديد',
        txnId: '1',
        amountLine: AppMoney.formatForPdf(199, isAr: true),
        statusLine: 'مدفوعة',
        isAr: true,
        descriptionLabel: InvoiceCopy.statementForPlan('Premium', isAr: true),
        periodLabel: InvoiceCopy.periodWithRange(
          periodRaw: 'monthly',
          start: DateTime(2026, 9, 1),
          end: DateTime(2026, 10, 1),
          isAr: true,
        ),
        qrPayload: InvoiceDocument.fromRow({
          'user_invoice_seq': 1,
          'amount': 199,
          'status': 'success',
          'id': uuid,
        }, isAr: true).qrPayload,
      );
      expect(bytes.length, greaterThan(2000));
      final asText = String.fromCharCodes(bytes);
      expect(asText.contains(uuid), isFalse);
    });

    test('English PDF generates with riyal mark', () async {
      final bytes = await PaymentService.buildInvoicePdf(
        title: 'New subscription invoice',
        txnId: '1',
        amountLine: AppMoney.formatForPdf(199, isAr: false),
        statusLine: 'Paid',
        isAr: false,
      );
      expect(bytes.length, greaterThan(2000));
    });
  });
}
