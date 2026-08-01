import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/branding/app_branding.dart';
import '../../core/config/app_config.dart';
import '../../core/utils/app_money.dart';
import '../../l10n/app_localizations.dart';
import '../../services/payment_service.dart';
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

  /// رابط تحقق خارجي اختياري. عند عدم تمريره نوّلد payload محلي.
  final String? verifyUrl;

  bool get _isAr => lang.toLowerCase() != 'en';

  String get _qrPayload {
    if ((verifyUrl ?? '').trim().isNotEmpty) return verifyUrl!.trim();
    final buf = StringBuffer('aqar-receipt|')
      ..write('tx=$transactionId|')
      ..write('amt=${amountSar.toStringAsFixed(2)}|')
      ..write('plan=$planName|')
      ..write('period=$period|')
      ..write('at=${completedAt.toIso8601String()}');
    if ((subscriptionId ?? '').isNotEmpty) buf.write('|sub=$subscriptionId');
    return buf.toString();
  }

  String get _formattedDate => DateFormat(
        'EEEE d MMM yyyy — HH:mm',
        _isAr ? 'ar' : 'en',
      ).format(completedAt.toLocal());

  String _periodLabel() {
    switch (period.toLowerCase()) {
      case 'yearly':
        return _isAr ? 'سنوي' : 'Yearly';
      case 'monthly':
        return _isAr ? 'شهري' : 'Monthly';
      case 'trial':
        return _isAr ? 'تجربة' : 'Trial';
      default:
        return period;
    }
  }

  String get _amountText => AppMoney.formatWithCurrencyCode(
        amountSar,
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
    final title = _isAr ? 'إيصال دفع' : 'Payment receipt';

    return Directionality(
      textDirection: _isAr ? ui.TextDirection.rtl : ui.TextDirection.ltr,
      child: WillPopScope(
      onWillPop: () async {
        Navigator.of(context).pop(true);
        return false;
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(title),
          leading: IconButton(
            tooltip: close,
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.of(context).pop(true),
          ),
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
                          _isAr
                              ? 'تم تفعيل اشتراكك مباشرة — يعكس الحالة فوراً.'
                              : 'Your subscription is active — instantly reflected.',
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
                          _row(_isAr ? 'الفترة' : 'Period', _periodLabel()),
                          _row(
                            _isAr ? 'المبلغ' : 'Amount',
                            _amountText,
                            valueBold: true,
                            valueColor: cs.primary,
                          ),
                          _row(
                            _isAr ? 'طريقة الدفع' : 'Method',
                            paymentMethodLabel,
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
                          _row(
                            _isAr ? 'رقم المعاملة' : 'Transaction ID',
                            transactionId,
                            valueSelectable: true,
                          ),
                          if ((subscriptionId ?? '').isNotEmpty)
                            _row(
                              _isAr ? 'رقم الاشتراك' : 'Subscription ID',
                              subscriptionId!,
                              valueSelectable: true,
                            ),
                          if ((purpose ?? '').isNotEmpty)
                            _row(
                              _isAr ? 'نوع العملية' : 'Purpose',
                              _purposeLabel(),
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
                    caption: transactionId,
                    title: _isAr ? 'رمز التحقق' : 'Verification code',
                    hint: _isAr
                        ? 'امسح الرمز للتحقق من بيانات المعاملة.'
                        : 'Scan to verify transaction details.',
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

  String _purposeLabel() {
    switch ((purpose ?? '').toLowerCase()) {
      case 'subscribe_new':
        return _isAr ? 'اشتراك جديد' : 'New subscription';
      case 'renew':
        return _isAr ? 'تجديد' : 'Renewal';
      case 'upgrade':
        return _isAr ? 'ترقية باقة' : 'Plan upgrade';
      case 'period_switch':
        return _isAr ? 'تحويل إلى سنوي' : 'Switch to yearly';
      default:
        return purpose!;
    }
  }

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
    if (_isAr) {
      return '''
إيصال دفع — ${AppBranding.legalName(isAr: true)}
الباقة: $planName
الفترة: ${_periodLabel()}
المبلغ: $amt
طريقة الدفع: $paymentMethodLabel
تاريخ الدفع: $_formattedDate
رقم المعاملة: $transactionId${(subscriptionId ?? '').isNotEmpty ? '\nرقم الاشتراك: $subscriptionId' : ''}
''';
    }
    return '''
${AppBranding.legalName(isAr: false)} — Payment receipt
Plan: $planName
Period: ${_periodLabel()}
Amount: $amt
Method: $paymentMethodLabel
Paid at: $_formattedDate
Transaction ID: $transactionId${(subscriptionId ?? '').isNotEmpty ? '\nSubscription ID: $subscriptionId' : ''}
''';
  }

  /// يبني PDF عربي/إنجليزي عبر [PaymentService.buildInvoicePdf].
  Future<Uint8List> _buildInvoiceBytes() {
    return PaymentService.buildInvoicePdf(
      title: _isAr ? 'إيصال دفع' : 'Payment receipt',
      txnId: transactionId,
      amountLine: _amountText,
      statusLine: _isAr ? 'مكتمل / Success' : 'Success',
      footer: _isAr
          ? 'هذه الفاتورة لأغراض الإثبات داخل المنصة فقط ولا تُستخدم لأغراض ضريبية '
              'حتى تفعيل البوابة المعتمدة.'
          : 'For platform proof only. Not valid for tax until a licensed '
              'gateway is enabled.',
      planName: planName,
      periodLabel: _periodLabel(),
      paymentMethod: paymentMethodLabel,
      paidAtFormatted: _formattedDate,
      subscriptionId: subscriptionId,
      payerName: payerName,
      purposeLabel: (purpose ?? '').isEmpty ? null : _purposeLabel(),
      isAr: _isAr,
    );
  }

  String _safeFileName() {
    final raw = transactionId.trim().isEmpty ? 'receipt' : transactionId.trim();
    return raw.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
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
