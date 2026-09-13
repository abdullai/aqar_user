import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:aqar_user/core/gestures/app_keyboard_popups.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/payment/invoice_document.dart';
import '../../core/utils/app_money.dart';
import '../../l10n/app_localizations.dart';
import '../../services/invoice_service.dart';
import '../../widgets/app_page_close_button.dart';
import '../../widgets/app_readable_qr.dart';

/// تفاصيل فاتورة رسمية من billing_transactions — ليست إيصالاً.
class InvoiceDetailScreen extends StatefulWidget {
  const InvoiceDetailScreen({
    super.key,
    required this.row,
    required this.lang,
    required this.invoices,
    this.onDeleted,
  });

  final Map<String, dynamic> row;
  final String lang;
  final InvoiceService invoices;
  final Future<void> Function()? onDeleted;

  @override
  State<InvoiceDetailScreen> createState() => _InvoiceDetailScreenState();
}

class _InvoiceDetailScreenState extends State<InvoiceDetailScreen> {
  bool _busy = false;
  late Map<String, dynamic> _row;
  InvoiceDocument? _doc;

  bool get _isAr => widget.lang.toLowerCase() != 'en';

  @override
  void initState() {
    super.initState();
    _row = Map<String, dynamic>.from(widget.row);
    unawaited(_hydrate());
  }

  Future<void> _hydrate() async {
    final id = '${_row['id'] ?? ''}'.trim();
    if (id.isNotEmpty) {
      final live = await widget.invoices.repository.getOwn(id);
      if (live != null && mounted) {
        _row = live;
      }
    }
    final doc = await widget.invoices.documentFor(_row);
    if (!mounted) return;
    setState(() => _doc = doc);
  }

  InvoiceDocument get _d =>
      _doc ?? InvoiceDocument.fromRow(_row, isAr: _isAr);

  Future<void> _run(Future<void> Function() job, String ok, String fail) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await job();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ok)));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(fail)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final d = _d;
    return Directionality(
      textDirection: _isAr ? ui.TextDirection.rtl : ui.TextDirection.ltr,
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,
          leading: AppPageCloseButton(isArabic: _isAr),
          title: Text(d.documentTitle),
        ),
        body: ListView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
          children: [
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: cs.primaryContainer.withValues(alpha: 0.55),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      d.statusLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        color: cs.onPrimaryContainer,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: cs.secondaryContainer.withValues(alpha: 0.55),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      d.methodLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        color: cs.onSecondaryContainer,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Text(
              d.hasInvoiceNumber ? d.invoiceNumber : t.invoiceUnavailable,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textDirection: ui.TextDirection.ltr,
              style: const TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 22,
                letterSpacing: 0.2,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              d.statementLabel,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 16,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 18),
            _amountBlock(d),
            if (d.showSubtotal)
              _kvMoney(t.invoiceBreakdownSubtotal, d.subtotal, d),
            if (d.showAutoPayDiscount)
              _kvMoney(d.autoPayDiscountLabel(isAr: _isAr), d.autoPayDiscountSar, d),
            if (d.showPromoDiscount)
              _kvMoney(d.promoDiscountLabel(isAr: _isAr), d.promoDiscountSar, d),
            if (d.showCombinedDiscount)
              _kvMoney(d.discountLabel(isAr: _isAr), d.discount, d),
            if (d.showVat) _kvMoney(t.invoiceVatLine, d.vat, d),
            if (d.showFees) _kvMoney(t.invoiceFeesLine, d.fees, d),
            if (d.showRefund)
              _kvMoney(_isAr ? 'المسترجع' : 'Refunded', d.refundAmount, d),
            _kv(_isAr ? 'نوع العملية' : 'Purpose', d.purposeLabel),
            _kv(_isAr ? 'الفترة' : 'Period', d.periodLabel),
            _kv(_isAr ? 'طريقة الدفع' : 'Payment method', d.methodLabel),
            if (d.dateLine.isNotEmpty)
              _kv(_isAr ? 'تاريخ العملية' : 'Transaction date', d.dateLine),
            if ((d.paymentReference ?? '').isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                t.invoiceTechnicalSection,
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  color: cs.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 6),
              _kv(t.invoicePaymentReference, d.paymentReference!, latin: true),
            ],
            const SizedBox(height: 20),
            AppReadableQr(
              data: d.qrPayload,
              isAr: _isAr,
              size: 168,
              caption: d.hasInvoiceNumber ? d.invoiceNumber : null,
              title: _isAr ? 'رمز التحقق من الفاتورة' : 'Invoice verification QR',
              hint: t.invoiceQrHint,
            ),
            const SizedBox(height: 24),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                FilledButton.icon(
                  onPressed: _busy
                      ? null
                      : () => _run(
                            () => widget.invoices.printInvoice(_row),
                            _isAr ? 'تم فتح الطباعة' : 'Print opened',
                            _isAr ? 'تعذرت الطباعة' : 'Print failed',
                          ),
                  icon: const Icon(Icons.print_outlined),
                  label: Text(_isAr ? 'طباعة' : 'Print'),
                ),
                FilledButton.tonalIcon(
                  onPressed: _busy
                      ? null
                      : () => _run(
                            () => widget.invoices.downloadOrShare(_row),
                            _isAr ? 'تم تجهيز الملف' : 'File ready',
                            _isAr ? 'تعذر التحميل' : 'Download failed',
                          ),
                  icon: const Icon(Icons.picture_as_pdf_outlined),
                  label: const Text('PDF'),
                ),
                OutlinedButton.icon(
                  onPressed: _busy
                      ? null
                      : () => _run(
                            () async {
                              final bytes = await widget.invoices.exportAllExcel(
                                [_row],
                                sectionTitle: d.title,
                              );
                              await Share.shareXFiles([
                                XFile.fromData(
                                  bytes,
                                  mimeType:
                                      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
                                  name: d.excelFileName,
                                ),
                              ]);
                            },
                            _isAr ? 'تم التصدير' : 'Exported',
                            _isAr ? 'فشل التصدير' : 'Export failed',
                          ),
                  icon: const Icon(Icons.table_chart_outlined),
                  label: const Text('Excel'),
                ),
                TextButton.icon(
                  onPressed: _busy
                      ? null
                      : () async {
                          final ok = await showAppDialog<bool>(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              title: Text(t.invoiceHideConfirmTitle),
                              content: Text(t.invoiceHideConfirmBody),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(ctx, false),
                                  child: Text(_isAr ? 'إلغاء' : 'Cancel'),
                                ),
                                FilledButton(
                                  onPressed: () => Navigator.pop(ctx, true),
                                  child: Text(t.invoiceHideFromLedger),
                                ),
                              ],
                            ),
                          );
                          if (ok != true) return;
                          await widget.onDeleted?.call();
                          if (!context.mounted) return;
                          Navigator.of(context).maybePop();
                        },
                  icon: Icon(Icons.visibility_off_outlined, color: cs.error),
                  label: Text(
                    t.invoiceHideFromLedger,
                    style: TextStyle(color: cs.error),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _kvMoney(String label, double amount, InvoiceDocument d) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontWeight: FontWeight.w800,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: AppMoneyLine(
              amount: amount,
              currencyCode: d.currency,
              isAr: _isAr,
              maxFractionDigits: 2,
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
            ),
          ),
        ],
      ),
    );
  }

  Widget _amountBlock(InvoiceDocument d) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          SizedBox(
            width: 120,
            child: Text(
              _isAr ? 'الإجمالي' : 'Total',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontWeight: FontWeight.w800,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: AppMoneyLine(
              amount: d.amount,
              currencyCode: d.currency,
              isAr: _isAr,
              maxFractionDigits: 2,
              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
            ),
          ),
        ],
      ),
    );
  }

  Widget _kv(String label, String value, {bool latin = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontWeight: FontWeight.w800,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textDirection: latin ? ui.TextDirection.ltr : null,
              style: const TextStyle(fontWeight: FontWeight.w700, height: 1.35),
            ),
          ),
        ],
      ),
    );
  }
}
