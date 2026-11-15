import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:aqar_user/core/branding/app_branding.dart';
import 'package:aqar_user/core/payment/invoice_copy.dart';
import 'package:aqar_user/core/payment/invoice_document.dart';
import 'package:aqar_user/core/utils/app_money.dart';
import 'package:aqar_user/services/billing_transaction_repository.dart';
import 'package:aqar_user/services/invoice_service.dart';
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

    test('uses a valid official invoice number when no sequence is available',
        () {
      final doc = InvoiceDocument.fromRow({
        'invoice_number': 'INV-20260910-000123',
        'amount': 10,
        'status': 'success',
      }, isAr: true);

      expect(doc.invoiceNumber, 'INV-20260910-000123');
      expect(doc.displayInvoiceNumber, 'INV-20260910-000123');
      expect(doc.invoiceNumberRegistrationLabel, 'رقم رسمي مسجّل');
    });

    test('clearly marks when a row has no registered official number', () {
      final doc = InvoiceDocument.fromRow({
        'id': 'a1b2c3d4-e5f6-7890-abcd-ef1234567890',
        'amount': 10,
        'status': 'success',
      }, isAr: true);

      expect(doc.hasInvoiceNumber, isFalse);
      expect(
        doc.invoiceNumberRegistrationLabel,
        'لا يوجد رقم رسمي مسجّل لهذه العملية',
      );
      expect(doc.displayInvoiceNumber, 'غير متوفر');
    });

    test('includes actual subscription dates in its period label', () {
      final doc = InvoiceDocument.fromRow(
          {
            'billing_period': 'monthly',
            'amount': 10,
            'status': 'success',
          },
          isAr: true,
          subscription: {
            'starts_at': '2026-09-01',
            'ends_at': '2026-10-01',
          });

      expect(doc.periodKindLabel, 'شهري');
      expect(doc.periodLabel, contains('من 2026/09/01 إلى 2026/10/01'));
    });

    test('payment reference is numeric and never exposes gateway UUIDs', () {
      final doc = InvoiceDocument.fromRow({
        'id': 'a1b2c3d4-e5f6-7890-abcd-ef1234567890',
        'user_invoice_seq': 42,
        'gateway_transaction_id': '95f8b3a-a425-4f21-9c0f-ef1234567890',
      }, isAr: true);
      final numericReference = InvoiceDocument.fromRow({
        'user_invoice_seq': 43,
        'gateway_transaction_id': '7645123098',
      }, isAr: true);

      expect(doc.paymentReference, '42');
      expect(numericReference.paymentReference, '7645123098');
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
      expect(
          InvoiceCopy.purposeLabel('subscribe_new', isAr: true), 'اشتراك جديد');
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
      expect(ar, contains('12.5 ${AppMoney.saudiRiyalSignCompat}'));
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

  group('InvoiceService exports', () {
    late SupabaseClient supabase;
    late InvoiceService invoices;

    setUp(() {
      supabase = SupabaseClient('https://example.supabase.co', 'test-key');
      invoices = InvoiceService(
        repository: BillingTransactionRepository(supabase),
        isAr: true,
        supabase: supabase,
      );
    });

    tearDown(() => supabase.dispose());

    final row = <String, dynamic>{
      'id': 'billing-id',
      'user_invoice_seq': 25,
      'amount': 10,
      'currency': 'SAR',
      'status': 'success',
      'payment_method': 'mada',
      'created_at': '2026-11-06T10:00:00Z',
    };

    test('Excel export has branded heading and number registration status',
        () async {
      final bytes = await invoices.exportAllExcel([row]);
      final workbook = Excel.decodeBytes(bytes);
      final sheet = workbook.tables['فواتير']!;

      expect(
        sheet
            .cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 0))
            .value
            .toString(),
        contains('بسم الله الرحمن الرحيم'),
      );
      expect(
        sheet
            .cell(CellIndex.indexByColumnRow(columnIndex: 22, rowIndex: 8))
            .value
            .toString(),
        contains('رقم رسمي مسجّل'),
      );
    });

    test('CSV export includes the letterhead and explicit invoice number state',
        () async {
      final csv = await invoices.exportAllCsv([row]);

      expect(csv, contains('بسم الله الرحمن الرحيم'));
      expect(
        csv,
        contains(AppBranding.invoiceLetterheadBrandName(isAr: true)),
      );
      expect(csv, contains('أرقام رسمية مسجّلة'));
      expect(csv, contains('رقم رسمي مسجّل'));
    });
  });

  group('PaymentService.buildInvoicePdf', () {
    TestWidgetsFlutterBinding.ensureInitialized();

    test('Arabic PDF bytes include per-user invoice number not UUID', () async {
      const uuid = 'a1b2c3d4-e5f6-7890-abcd-ef1234567890';
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
        }, isAr: true)
            .qrPayload,
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
