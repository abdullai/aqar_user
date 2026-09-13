import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/branding/app_branding.dart';
import '../../core/branding/branding_pdf.dart';
import '../../core/config/app_config.dart';
import '../../core/payment/invoice_copy.dart';
import '../../core/payment/invoice_document.dart';
import '../../core/payment/payment_plain_explain.dart';
import '../../core/utils/app_money.dart';
import '../../l10n/app_localizations.dart';
import '../../services/payment_service.dart';
import '../../widgets/app_page_close_button.dart';
import '../../widgets/app_readable_qr.dart';

/// إيصال الدفع الناجح — يظهر تلقائياً بعد العملية الناجحة.
///
/// • يعرض كل بيانات الدفع بنصوص عربية واضحة.
/// • يحتوي رمز استجابة QR للتحقق من صحة المعاملة.
/// • يُغلق بـ true ليعيد المستخدم إلى الصفحة التي أتى منها.
class PaymentReceiptScreen extends StatelessWidget {
  const PaymentReceiptScreen({
    super.key,
    required this.lang,
    required this.planName,
    required this.period,
    required this.amountSar,
    required this.paymentMethodLabel,
    required this.transactionId,
    required this.completedAt,
    this.subscriptionId,
    this.cardLast4,
    this.payerName,
    this.purpose,
    this.verifyUrl,
    this.billingRow,
    this.invoiceNumber,
    this.paymentReference,
  });

  final String lang;
  final String planName;
  final String period;
  final double amountSar;
  final String paymentMethodLabel;
  final String transactionId;
  final DateTime completedAt;
  final String? subscriptionId;
  final String? cardLast4;
  final String? payerName;
  final String? purpose;

  /// رابط تحقق خارجي اختياري. عند عدم تمريره نوّلد payload من رقم الفاتورة.
  final String? verifyUrl;

  /// صف billing_transactions المعتمد من الخادم إن وُجد.
  final Map<String, dynamic>? billingRow;
  final String? invoiceNumber;
  final String? paymentReference;

  bool get _isAr => lang.toLowerCase() != 'en';

  InvoiceDocument? get _doc {
    final row = billingRow;
    if (row == null || row.isEmpty) return null;
    return InvoiceDocument.fromRow(row, isAr: _isAr);
  }

  String get _officialInvoiceNo {
    final fromDoc = _doc?.invoiceNumber ?? '';
    if (fromDoc.isNotEmpty) return fromDoc;
    final passed = (invoiceNumber ?? '').trim();
    if (InvoiceDocument.isOfficialInvoiceNumber(passed)) return passed;
    return '';
  }

  double get _amount {
    final d = _doc;
    if (d != null) return d.amount;
    return amountSar;
  }

  String get _qrPayload {
    if ((verifyUrl ?? '').trim().isNotEmpty) return verifyUrl!.trim();
    final d = _doc;
    if (d != null) return d.qrPayload;
    return documentQrPlainText(
      isAr: _isAr,
      kind: _isAr ? 'إيصال دفع' : 'Payment receipt',
      invoiceNo: _officialInvoiceNo,
      description: planName,
      period: _periodLabel(),
      amountLine: _amountText,
      status: _isAr ? 'مدفوعة' : 'Paid',
      paidAt: _formattedDate,
      method: paymentMethodLabel,
    );
  }

  String get _formattedDate =>
      InvoiceCopy.dualCalendar(completedAt, isAr: _isAr);

  String _periodLabel() => InvoiceCopy.periodLabel(period, isAr: _isAr);

  Widget _amountValue(BuildContext context) {
    return AppMoneyLine(
      amount: _amount,
      currencyCode: 'SAR',
      isAr: _isAr,
      maxFractionDigits: 2,
      style: TextStyle(
        fontWeight: FontWeight.w900,
        fontSize: 20,
        color: Theme.of(context).colorScheme.primary,
      ),
    );
  }

  String get _amountText => AppMoney.formatWithCurrencyCode(
        _amount,
        isAr: _isAr,
        currencyCode: 'SAR',
        maxFractionDigits: 2,
      );

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;

    final close = _isAr ? 'إغلاق' : 'Close';
    final share = _isAr ? 'مشاركة' : 'Share';
    final printLabel = _isAr ? 'طباعة' : 'Print';

    return Directionality(
      textDirection: _isAr ? ui.TextDirection.rtl : ui.TextDirection.ltr,
      child: WillPopScope(
      onWillPop: () async {
        Navigator.of(context).pop(true);
        return false;
      },
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,
          leading: AppPageCloseButton(
            isArabic: _isAr,
            tooltip: close,
            onPressed: () => Navigator.of(context).pop(true),
          ),
          title: Text(_doc?.documentTitle ?? (_isAr ? 'إيصال دفع' : 'Payment receipt')),
        ),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: AppConfig.maxContentWidth,
            ),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: cs.primaryContainer.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Column(
                      children: [
                        Icon(Icons.verified_outlined,
                            color: cs.primary, size: 56),
                        const SizedBox(height: 8),
                        Text(
                          _isAr ? 'تم الدفع بنجاح' : 'Payment successful',
                          style: Theme.of(context)
                              .textTheme
                              .titleLarge
                              ?.copyWith(
                                color: cs.onPrimaryContainer,
                                fontWeight: FontWeight.w900,
                              ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          PaymentPlainExplain.receiptSubtitle(
                            isAr: _isAr,
                            period: period,
                            purpose: purpose,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _isAr ? 'تفاصيل المعاملة' : 'Transaction details',
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(fontWeight: FontWeight.w900),
                          ),
                          const SizedBox(height: 10),
                          _row(_isAr ? 'الباقة' : 'Plan', planName),
                          _row(
                            _isAr ? 'البيان' : 'Description',
                            _doc?.statementLabel ??
                                InvoiceCopy.statementForPlan(planName, isAr: _isAr),
                          ),
                          _row(
                            _isAr ? 'الفترة' : 'Period',
                            _doc?.periodLabel ?? _periodLabel(),
                          ),
                          if (_doc != null && _doc!.showSubtotal)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 6),
                              child: Row(
                                children: [
                                  SizedBox(
                                    width: 130,
                                    child: Text(
                                      _isAr ? 'قبل الخصم' : 'Before discount',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ),
                                  Expanded(child: _moneyWidget(_doc!.subtotal)),
                                ],
                              ),
                            ),
                          if (_doc != null && _doc!.showAutoPayDiscount)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 6),
                              child: Row(
                                children: [
                                  SizedBox(
                                    width: 130,
                                    child: Text(
                                      _doc!.autoPayDiscountLabel(isAr: _isAr),
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ),
                                  Expanded(
                                    child: _moneyWidget(_doc!.autoPayDiscountSar),
                                  ),
                                ],
                              ),
                            ),
                          if (_doc != null && _doc!.showPromoDiscount)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 6),
                              child: Row(
                                children: [
                                  SizedBox(
                                    width: 130,
                                    child: Text(
                                      _doc!.promoDiscountLabel(isAr: _isAr),
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ),
                                  Expanded(
                                    child: _moneyWidget(_doc!.promoDiscountSar),
                                  ),
                                ],
                              ),
                            ),
                          if (_doc != null && _doc!.showCombinedDiscount)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 6),
                              child: Row(
                                children: [
                                  SizedBox(
                                    width: 130,
                                    child: Text(
                                      _doc!.discountLabel(isAr: _isAr),
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ),
                                  Expanded(child: _moneyWidget(_doc!.discount)),
                                ],
                              ),
                            ),
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                SizedBox(
                                  width: 130,
                                  child: Text(
                                    _isAr ? 'المبلغ' : 'Amount',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                                Expanded(child: _amountValue(context)),
                              ],
                            ),
                          ),
                          _row(
                            _isAr ? 'طريقة الدفع' : 'Method',
                            _doc?.methodLabel ?? paymentMethodLabel,
                          ),
                          if ((cardLast4 ?? '').isNotEmpty)
                            _row(
                              _isAr ? 'البطاقة' : 'Card',
                              '•••• ${cardLast4!.trim()}',
                            ),
                          if ((payerName ?? '').isNotEmpty)
                            _row(_isAr ? 'الدافع' : 'Payer', payerName!),
                          _row(
                            _isAr ? 'تاريخ الدفع' : 'Paid at',
                            _formattedDate,
                          ),
                          if (_officialInvoiceNo.isNotEmpty)
                            _row(
                              _isAr ? 'رقم الفاتورة' : 'Invoice number',
                              _officialInvoiceNo,
                              valueSelectable: true,
                            ),
                          if ((_doc?.paymentReference ?? paymentReference ?? '')
                              .trim()
                              .isNotEmpty)
                            _row(
                              _isAr ? 'مرجع الدفع' : 'Payment reference',
                              (_doc?.paymentReference ?? paymentReference)!,
                              valueSelectable: true,
                            ),
                          _row(
                            _isAr ? 'نوع العملية' : 'Purpose',
                            _doc?.purposeLabel ?? _purposeLabel(),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  AppReadableQr(
                    data: _qrPayload,
                    isAr: _isAr,
                    size: 188,
                    caption: _officialInvoiceNo.isNotEmpty
                        ? _officialInvoiceNo
                        : null,
                    title: _isAr ? 'رمز التحقق' : 'Verification code',
                    hint: _isAr
                        ? 'امسح الرمز للتحقق من رقم الفاتورة.'
                        : 'Scan to verify the invoice number.',
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _isAr
                        ? 'ختم المطابقة: ${_matchSeal()} — يطابق المبلغ ورقم العملية على الفاتورة المطبوعة.'
                        : 'Match seal: ${_matchSeal()} — must match amount and transaction on the printed invoice.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.4,
                      fontWeight: FontWeight.w700,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    alignment: WrapAlignment.spaceBetween,
                    children: [
                      SizedBox(
                        width: 170,
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.ios_share_outlined),
                          label: Text(share),
                          onPressed: () => unawaited(_sharePdf()),
                        ),
                      ),
                      SizedBox(
                        width: 170,
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.print_outlined),
                          label: Text(printLabel),
                          onPressed: () => unawaited(_printPdf()),
                        ),
                      ),
                      SizedBox(
                        width: 170,
                        child: FilledButton.icon(
                          icon: const Icon(Icons.check_circle_outline),
                          label: Text(
                            t?.subscriptionsPaywallCloseLabel ?? close,
                          ),
                          onPressed: () => Navigator.of(context).pop(true),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
    );
  }

  Widget _moneyWidget(double amount) {
    return AppMoneyLine(
      amount: amount,
      currencyCode: _doc?.currency ?? 'SAR',
      isAr: _isAr,
      maxFractionDigits: 2,
      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
    );
  }

  String _moneyLine(double amount) => AppMoney.formatWithCurrencyCode(
        amount,
        isAr: _isAr,
        currencyCode: _doc?.currency ?? 'SAR',
        maxFractionDigits: 2,
      );

  String _matchSeal() {
    final id = _officialInvoiceNo.replaceAll('-', '');
    final tail =
        id.length >= 6 ? id.substring(id.length - 6) : _amount.toStringAsFixed(0);
    return '${tail.toUpperCase()}-${_amount.toStringAsFixed(2)}';
  }

  String _purposeLabel() =>
      InvoiceCopy.purposeLabel(purpose ?? '', isAr: _isAr);

  Widget _row(
    String label,
    String value, {
    bool valueBold = false,
    Color? valueColor,
    bool valueSelectable = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          Expanded(
            child: valueSelectable
                ? SelectableText(
                    value,
                    style: TextStyle(
                      fontWeight:
                          valueBold ? FontWeight.w900 : FontWeight.w500,
                      color: valueColor,
                    ),
                  )
                : Text(
                    value,
                    style: TextStyle(
                      fontWeight:
                          valueBold ? FontWeight.w900 : FontWeight.w500,
                      color: valueColor,
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  String _buildShareText() {
    final amt = _amountText;
    final d = _doc;
    final promo = d != null && d.showPromoDiscount
        ? (_isAr
            ? '\n${d.promoDiscountLabel(isAr: true)}: ${_moneyLine(d.promoDiscountSar)}'
            : '\n${d.promoDiscountLabel(isAr: false)}: ${_moneyLine(d.promoDiscountSar)}')
        : '';
    final auto = d != null && d.showAutoPayDiscount
        ? (_isAr
            ? '\n${d.autoPayDiscountLabel(isAr: true)}: ${_moneyLine(d.autoPayDiscountSar)}'
            : '\n${d.autoPayDiscountLabel(isAr: false)}: ${_moneyLine(d.autoPayDiscountSar)}')
        : '';
    if (_isAr) {
      return '''
إيصال دفع — ${AppBranding.invoiceLetterheadBrandName(isAr: true)}
الباقة: $planName
الفترة: ${_periodLabel()}$auto$promo
المبلغ: $amt
طريقة الدفع: $paymentMethodLabel
تاريخ الدفع: $_formattedDate
رقم الفاتورة: ${_officialInvoiceNo.isEmpty ? '—' : _officialInvoiceNo}${(paymentReference ?? _doc?.paymentReference ?? '').toString().trim().isNotEmpty ? '\nمرجع الدفع: ${_doc?.paymentReference ?? paymentReference}' : ''}
''';
    }
    return '''
${AppBranding.invoiceLetterheadBrandName(isAr: false)} — Payment receipt
Plan: $planName
Period: ${_periodLabel()}$auto$promo
Amount: $amt
Method: $paymentMethodLabel
Paid at: $_formattedDate
Invoice: ${_officialInvoiceNo.isEmpty ? '—' : _officialInvoiceNo}${(paymentReference ?? _doc?.paymentReference ?? '').toString().trim().isNotEmpty ? '\nPayment reference: ${_doc?.paymentReference ?? paymentReference}' : ''}
''';
  }

  /// يبني PDF عربي/إنجليزي عبر [PaymentService.buildInvoicePdf].
  Future<Uint8List> _buildInvoiceBytes() {
    final d = _doc;
    final period = d?.periodLabel ?? _periodLabel();
    final statement = d?.statementLabel ??
        InvoiceCopy.statementForPlan(planName, isAr: _isAr);
    return PaymentService.buildInvoicePdf(
      title: d?.documentTitle ?? (_isAr ? 'إيصال دفع' : 'Payment receipt'),
      txnId: _officialInvoiceNo,
      amountLine: AppMoney.formatForPdf(_amount, isAr: _isAr),
      statusLine: d?.statusLabel ?? (_isAr ? 'مدفوعة' : 'Paid'),
      footer: null,
      planName: planName,
      descriptionLabel: statement,
      periodLabel: period,
      paymentMethod: d?.methodLabel ?? paymentMethodLabel,
      paidAtFormatted: InvoiceCopy.latinDateTime(completedAt),
      calendarLine: InvoiceCopy.latinDateTime(completedAt),
      payerName: payerName,
      purposeLabel: d?.purposeLabel ??
          ((purpose ?? '').isEmpty ? null : _purposeLabel()),
      paymentReference: _doc?.paymentReference ?? paymentReference,
      qrPayload: _qrPayload,
      isAr: _isAr,
      subtotalLine: d != null && d.showSubtotal
          ? AppMoney.formatForPdf(d.subtotal, isAr: _isAr)
          : null,
      autoPayDiscountLine: d != null && d.showAutoPayDiscount
          ? AppMoney.formatForPdf(d.autoPayDiscountSar, isAr: _isAr)
          : null,
      autoPayDiscountLabel:
          d != null && d.showAutoPayDiscount ? d.autoPayDiscountLabel(isAr: _isAr) : null,
      promoDiscountLine: d != null && d.showPromoDiscount
          ? AppMoney.formatForPdf(d.promoDiscountSar, isAr: _isAr)
          : null,
      promoDiscountLabel:
          d != null && d.showPromoDiscount ? d.promoDiscountLabel(isAr: _isAr) : null,
      discountLine: d != null && d.showCombinedDiscount
          ? AppMoney.formatForPdf(d.discount, isAr: _isAr)
          : null,
      discountLabel:
          d != null && d.showCombinedDiscount ? d.discountLabel(isAr: _isAr) : null,
    );
  }

  String _safeFileName() {
    if (_officialInvoiceNo.isNotEmpty) {
      return 'Invoice_$_officialInvoiceNo';
    }
    return 'receipt';
  }

  Future<void> _sharePdf() async {
    Uint8List bytes;
    try {
      bytes = await _buildInvoiceBytes();
    } catch (e) {
      // لو فشل بناء الـ PDF لأي سبب نرجع لنص فقط (تحويلة آمنة).
      await Share.share(_buildShareText());
      return;
    }
    final fileName = '${_safeFileName()}.pdf';
    if (kIsWeb) {
      await Share.shareXFiles([
        XFile.fromData(bytes, mimeType: 'application/pdf', name: fileName),
      ]);
      return;
    }
    try {
      final dir = await getTemporaryDirectory();
      final f = File('${dir.path}/$fileName');
      await f.writeAsBytes(bytes, flush: true);
      await Share.shareXFiles([XFile(f.path)]);
    } catch (_) {
      await Share.share(_buildShareText());
    }
  }

  Future<void> _printPdf() async {
    try {
      await Printing.layoutPdf(
        name: _safeFileName(),
        onLayout: (_) async => _buildInvoiceBytes(),
      );
    } catch (_) {
      // فشل فتح حوار الطباعة (مثلاً ويب بدون دعم): نرجع للمشاركة.
      await _sharePdf();
    }
  }
}
