import 'package:flutter/material.dart';

import '../core/utils/app_money.dart';

/// نموذج تفصيلي للفاتورة (مستقل عن مصدر البيانات: عقار مخزّن أو معاينة حيّة).
///
/// — `enteredPrice`: المبلغ الذي وضعه المعلن في حقل «السعر الإجمالي».
/// — `priceIncludesVat`: هل المبلغ شامل ضريبة القيمة المضافة؟
/// — `vatRate`: نسبة الضريبة (مثلاً 0.05 = 5%).
/// — `commissionKind`: `none` | `percent` | `fixed`.
/// — `commissionRate` و`commissionAmount`: قيم العمولة حسب النوع.
class ListingInvoiceModel {
  final double enteredPrice;
  final bool priceIncludesVat;
  final double vatRate;
  final String commissionKind;
  final double commissionRate;
  final double commissionAmount;
  final String currencyCode;

  const ListingInvoiceModel({
    required this.enteredPrice,
    required this.priceIncludesVat,
    required this.vatRate,
    required this.commissionKind,
    required this.commissionRate,
    required this.commissionAmount,
    this.currencyCode = 'SAR',
  });

  static double _round2(double v) {
    if (v.isNaN || v.isInfinite) return 0;
    return (v * 100).round() / 100.0;
  }

  /// السعر الأساسي قبل الضريبة (المبلغ الذي يستحقّه البائع فعلياً).
  double get basePrice {
    if (priceIncludesVat) {
      return _round2(enteredPrice / (1.0 + vatRate));
    }
    return _round2(enteredPrice);
  }

  /// قيمة الضريبة المضافة (موجبة دائماً).
  double get vatAmount => _round2(basePrice * vatRate);

  /// الإجمالي بعد الضريبة (= السعر المدخل إن كان شامل، وإلا = السعر + الضريبة).
  double get totalWithVat => _round2(basePrice + vatAmount);

  /// قيمة عمولة التسويق.
  double get commissionTotal {
    switch (commissionKind) {
      case 'percent':
        return _round2(basePrice * commissionRate);
      case 'fixed':
        return _round2(commissionAmount);
      default:
        return 0.0;
    }
  }

  /// المجموع النهائي للفاتورة (الأساسي + الضريبة + العمولة).
  double get finalTotal => _round2(totalWithVat + commissionTotal);

  /// `true` إن كانت توجد ضريبة محسوبة أو عمولة فعلية تُعرض في الفاتورة.
  bool get hasAnyExtras => vatAmount > 0 || commissionTotal > 0;
}

/// بطاقة «تفصيل الفاتورة» المستخدمة في تفاصيل الإعلان وفي معاينة الإضافة/التعديل.
///
/// تَعرض ترتيب الأسطر بالشكل التالي (مطابق لمتطلبات ZATCA و REGA من حيث الشفافية):
///
///   1) السعر الأساسي (قبل الضريبة).
///   2) ضريبة القيمة المضافة 5% — مع توضيح إن كانت «محتسبة ضمن المبلغ» أو «مضافة».
///   3) الإجمالي بعد الضريبة (= السعر إن كان شامل، وإلا السعر + الضريبة).
///   4) عمولة التسويق (نسبة أو مبلغ مقطوع) — إن وُجدت.
///   5) المجموع النهائي (الأساسي + الضريبة + العمولة).
class ListingPricingBreakdown extends StatelessWidget {
  final ListingInvoiceModel invoice;
  final bool isAr;

  /// عرض عنوان البطاقة من عدمه (عند الاستخدام داخل قسم سابق نضبطه `false`).
  final bool showTitle;

  /// عنوان مخصّص اختياري (الافتراضي «تفصيل الفاتورة»).
  final String? title;

  const ListingPricingBreakdown({
    super.key,
    required this.invoice,
    required this.isAr,
    this.showTitle = true,
    this.title,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    // — نص الضريبة يتكيّف مع إجابة السؤال الأول.
    final vatPct = (invoice.vatRate * 100);
    final vatPctStr =
        vatPct == vatPct.roundToDouble() ? vatPct.toInt().toString() : vatPct.toStringAsFixed(1);
    final vatLabel = isAr
        ? (invoice.priceIncludesVat
            ? 'ضريبة القيمة المضافة ($vatPctStr%) — محتسبة من السعر الإجمالي'
            : 'ضريبة القيمة المضافة ($vatPctStr%) — تُضاف على السعر الأساسي')
        : (invoice.priceIncludesVat
            ? 'VAT ($vatPctStr%) — included in entered total'
            : 'VAT ($vatPctStr%) — added on top of base price');

    // — نص العمولة يتكيّف مع نوع الخيار في «إضافة الإعلان».
    final commissionPct = (invoice.commissionRate * 100);
    final commissionPctStr = commissionPct == commissionPct.roundToDouble()
        ? commissionPct.toInt().toString()
        : commissionPct.toStringAsFixed(1);
    final commissionLabel = switch (invoice.commissionKind) {
      'percent' => isAr
          ? 'عمولة التسويق العقاري — نسبة $commissionPctStr% من السعر الأساسي'
          : 'Marketing commission — $commissionPctStr% of base price',
      'fixed' => isAr
          ? 'عمولة التسويق العقاري — مبلغ مقطوع متفق عليه'
          : 'Marketing commission — agreed fixed amount',
      _ => isAr ? 'عمولة التسويق العقاري' : 'Marketing commission',
    };

    final lines = <Widget>[
      _InvoiceLine(
        label: isAr ? 'السعر الأساسي (قبل الضريبة)' : 'Base price (pre-VAT)',
        value: invoice.basePrice,
        currencyCode: invoice.currencyCode,
        isAr: isAr,
        emphasize: true,
      ),
      const SizedBox(height: 4),
      _InvoiceLine(
        label: vatLabel,
        value: invoice.vatAmount,
        currencyCode: invoice.currencyCode,
        isAr: isAr,
        deemphasize: invoice.priceIncludesVat,
        signPrefix: invoice.priceIncludesVat ? '' : '+ ',
      ),
      // عند السعر الشامل للضريبة: «الإجمالي مع الضريبة» = السعر المدخل
      // فيُكرّر قيمة العقار — نتخطّاه ونبقي الأساسي + الضريبة + العمولة + النهائي.
      if (!invoice.priceIncludesVat) ...[
        const SizedBox(height: 4),
        _InvoiceLine(
          label: isAr
              ? 'الإجمالي مع الضريبة (السعر + 5%)'
              : 'Total with VAT (price + 5%)',
          value: invoice.totalWithVat,
          currencyCode: invoice.currencyCode,
          isAr: isAr,
          emphasize: true,
        ),
      ],
      if (invoice.commissionTotal > 0) ...[
        const Divider(height: 18),
        _InvoiceLine(
          label: commissionLabel,
          value: invoice.commissionTotal,
          currencyCode: invoice.currencyCode,
          isAr: isAr,
          signPrefix: '+ ',
        ),
      ],
      const Divider(height: 22),
      _InvoiceLine(
        label: isAr
            ? 'المجموع النهائي (الأساسي + الضريبة + العمولة)'
            : 'Final total (base + VAT + commission)',
        value: invoice.finalTotal,
        currencyCode: invoice.currencyCode,
        isAr: isAr,
        big: true,
        emphasize: true,
        highlight: true,
      ),
    ];

    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: cs.primary.withValues(alpha: 0.18),
        ),
        boxShadow: [
          BoxShadow(
            color: cs.primary.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (showTitle) ...[
            Row(
              children: [
                Icon(Icons.receipt_long_outlined,
                    color: cs.primary, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title ?? (isAr ? 'تفصيل الفاتورة' : 'Invoice breakdown'),
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 14.5,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
          ],
          ...lines,
        ],
      ),
    );
  }
}

class _InvoiceLine extends StatelessWidget {
  final String label;
  final double value;
  final String currencyCode;
  final bool isAr;
  final bool emphasize;
  final bool deemphasize;
  final bool big;
  final bool highlight;
  final String signPrefix;

  const _InvoiceLine({
    required this.label,
    required this.value,
    required this.currencyCode,
    required this.isAr,
    this.emphasize = false,
    this.deemphasize = false,
    this.big = false,
    this.highlight = false,
    this.signPrefix = '',
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final color = highlight
        ? const Color(0xFF0F766E)
        : (deemphasize ? cs.onSurfaceVariant : cs.onSurface);
    final labelStyle = TextStyle(
      color: cs.onSurfaceVariant,
      fontWeight: emphasize ? FontWeight.w800 : FontWeight.w600,
      fontSize: big ? 13.5 : 12.5,
      height: 1.35,
    );
    final valueStyle = TextStyle(
      color: color,
      fontWeight: emphasize || big ? FontWeight.w900 : FontWeight.w800,
      fontSize: big ? 18 : 14,
    );

    // قيمة المبلغ (نضع الإشارة + رمز الريال + الرقم في FittedBox حتى
    // لا يلتفّ على شاشات ضيّقة جداً ولا تنقطع الأرقام الطويلة).
    final valueWidget = FittedBox(
      fit: BoxFit.scaleDown,
      alignment: isAr ? Alignment.centerLeft : Alignment.centerRight,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (signPrefix.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Text(signPrefix, style: valueStyle),
            ),
          AppMoneyLine(
            amount: value,
            currencyCode: currencyCode,
            isAr: isAr,
            style: valueStyle,
            maxFractionDigits: big ? 0 : 2,
          ),
        ],
      ),
    );

    final container = Container(
      padding: EdgeInsets.symmetric(
        vertical: big ? 8 : 4,
        horizontal: highlight ? 10 : 0,
      ),
      decoration: highlight
          ? BoxDecoration(
              color: const Color(0xFF0F766E).withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(10),
            )
          : null,
      child: LayoutBuilder(
        builder: (ctx, c) {
          // — في الشاشات الضيّقة (< 280) نضع التسمية فوق المبلغ في عمودَين
          //   منفصلين بدل صف واحد، حتى لا تُلَفّ السطور الطويلة عرضياً.
          final narrow = c.maxWidth.isFinite && c.maxWidth < 280;
          if (narrow) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: labelStyle,
                  softWrap: true,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Align(
                  alignment:
                      isAr ? Alignment.centerLeft : Alignment.centerRight,
                  child: valueWidget,
                ),
              ],
            );
          }
          // — في الشاشات الأوسع نُبقي صفّاً واحداً، مع جعل التسمية مرنة
          //   والمبلغ ضمن `FittedBox` فلا يلتفّ ولا يقتطع.
          return Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Text(
                  label,
                  style: labelStyle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 10),
              ConstrainedBox(
                constraints:
                    const BoxConstraints(minWidth: 0, maxWidth: 240),
                child: valueWidget,
              ),
            ],
          );
        },
      ),
    );
    return container;
  }
}
