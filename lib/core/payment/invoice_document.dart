import '../branding/app_branding.dart';
import '../subscription/card_scheme.dart';
import '../utils/app_money.dart';
import 'invoice_copy.dart';

/// عرض فاتورة رسمي فوق صف [billing_transactions] — بدون أرقام تقنية للمستخدم.
class InvoiceDocument {
  InvoiceDocument({
    required this.row,
    required this.isAr,
    this.subscription,
  });

  final Map<String, dynamic> row;
  final bool isAr;
  final Map<String, dynamic>? subscription;

  factory InvoiceDocument.fromRow(
    Map<String, dynamic> row, {
    required bool isAr,
    Map<String, dynamic>? subscription,
  }) {
    return InvoiceDocument(row: row, isAr: isAr, subscription: subscription);
  }

  static final RegExp _uuidLike = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  );

  static bool looksLikeUuid(String raw) => _uuidLike.hasMatch(raw.trim());

  static bool isOfficialInvoiceNumber(String raw) {
    final s = raw.trim();
    if (RegExp(r'^[1-9]\d{0,8}$').hasMatch(s)) return true;
    return RegExp(r'^INV-\d{8}-\d{6}$').hasMatch(s);
  }

  int? get userInvoiceSeq {
    final raw = row['user_invoice_seq'];
    if (raw is int) return raw;
    return int.tryParse('${raw ?? ''}');
  }

  String get invoiceNumber {
    final seq = userInvoiceSeq;
    if (seq != null && seq > 0) return '$seq';
    final official = '${row['invoice_number'] ?? ''}'.trim();
    if (RegExp(r'^[1-9]\d{0,8}$').hasMatch(official)) return official;
    return '';
  }

  bool get hasInvoiceNumber => invoiceNumber.isNotEmpty;

  String get displayInvoiceNumber {
    if (hasInvoiceNumber) return invoiceNumber;
    return isAr ? 'غير متوفر' : 'Unavailable';
  }

  String get documentTitle =>
      InvoiceCopy.documentTitleForPurpose(purposeRaw, isAr: isAr);

  String get title {
    final t = AppBranding.billingTitleFromRow(row, isAr: isAr).trim();
    if (t.isEmpty || t == '—') {
      return isAr ? 'عملية دفع' : 'Payment';
    }
    return t;
  }

  String get statementLabel => InvoiceCopy.statementForPlan(title, isAr: isAr);

  String get currency {
    final c = '${row['currency'] ?? 'SAR'}'.trim().toUpperCase();
    return c.isEmpty ? 'SAR' : c;
  }

  double money(String key) {
    final raw = row[key];
    if (raw is num) return raw.toDouble();
    return double.tryParse('${raw ?? ''}') ?? 0;
  }

  double get amount => money('amount');
  double get subtotal => money('subtotal_sar');
  double get discount => money('discount_sar');
  double get vat => money('vat_sar');
  double get fees => money('fees_sar');
  double get refundAmount => money('refund_amount');

  bool get vatIncluded {
    final v = row['vat_included'];
    if (v is bool) return v;
    final s = '$v'.toLowerCase().trim();
    if (s == 'false' || s == '0') return false;
    return true;
  }

  Map<String, dynamic> get _gateway {
    final g = row['gateway_response'];
    if (g is Map) {
      return Map<String, dynamic>.from(
        g.map((k, v) => MapEntry(k.toString(), v)),
      );
    }
    return const {};
  }

  String get appliedDiscountKind {
    final k = '${_gateway['applied_discount_kind'] ?? ''}'.trim();
    if (k.isNotEmpty) return k;
    final offer = _gateway['offer'];
    if (offer is Map) {
      return '${offer['applied_discount_kind'] ?? ''}'.trim();
    }
    return '';
  }

  String? get promoCode {
    final c = '${_gateway['promo_code'] ?? ''}'.trim();
    if (c.isNotEmpty && !looksLikeUuid(c)) return c;
    final offer = _gateway['offer'];
    if (offer is Map) {
      final o = '${offer['promo_code'] ?? ''}'.trim();
      if (o.isNotEmpty && !looksLikeUuid(o)) return o;
    }
    return null;
  }

  static double _jsonMoney(dynamic v) {
    if (v is num) return v.toDouble();
    return double.tryParse('${v ?? ''}') ?? 0;
  }

  double get autoPayDiscountSar {
    final direct = _jsonMoney(_gateway['auto_pay_discount_sar']);
    if (direct > 0) return direct;
    final offer = _gateway['offer'];
    if (offer is Map) return _jsonMoney(offer['auto_pay_discount_sar']);
    return 0;
  }

  double get autoPayDiscountPct {
    final direct = _jsonMoney(_gateway['auto_pay_discount_pct']);
    if (direct > 0) return direct;
    final offer = _gateway['offer'];
    if (offer is Map) return _jsonMoney(offer['auto_pay_discount_pct']);
    return 0;
  }

  double get promoDiscountSar {
    final direct = _jsonMoney(_gateway['promo_discount_sar']);
    if (direct > 0) return direct;
    final offer = _gateway['offer'];
    if (offer is Map) return _jsonMoney(offer['promo_discount_sar']);
    return 0;
  }

  String discountLabel({required bool isAr}) {
    if (showAutoPayDiscount && !showPromoDiscount) {
      return InvoiceCopy.autoRenewDiscountLabel(isAr: isAr);
    }
    if (showPromoDiscount && !showAutoPayDiscount) {
      return InvoiceCopy.promoCodeDiscountLabel(isAr: isAr);
    }
    final ar = '${_gateway['discount_label_ar'] ?? ''}'.trim();
    final en = '${_gateway['discount_label_en'] ?? ''}'.trim();
    if (isAr && ar.isNotEmpty) return ar;
    if (!isAr && en.isNotEmpty) return en;
    if (showPromoDiscount) {
      return InvoiceCopy.promoCodeDiscountLabel(isAr: isAr);
    }
    if (showAutoPayDiscount) {
      return InvoiceCopy.autoRenewDiscountLabel(isAr: isAr);
    }
    return isAr ? 'الخصم' : 'Discount';
  }

  bool get showAutoPayDiscount => autoPayDiscountSar > 0.009;
  bool get showPromoDiscount =>
      promoDiscountSar > 0.009 && (promoCode ?? '').isNotEmpty;

  String autoPayDiscountLabel({required bool isAr}) =>
      InvoiceCopy.autoRenewDiscountLabel(isAr: isAr);

  String promoDiscountLabel({required bool isAr}) =>
      InvoiceCopy.promoCodeDiscountLabel(isAr: isAr);

  /// سطر مجمّع فقط إذا وُجد خصم مالي دون تفصيل تلقائي/كود (فواتير قديمة).
  bool get showCombinedDiscount =>
      showDiscount && !showAutoPayDiscount && !showPromoDiscount;

  bool get showSubtotal =>
      showDiscount && subtotal > 0 && (subtotal - amount).abs() > 0.009;
  bool get showDiscount => discount > 0.009;
  bool get showVat => vat > 0.009;
  bool get showFees => fees > 0.009;
  bool get showRefund => refundAmount > 0.009;

  String get purposeRaw => InvoiceCopy.purposeFromRow(row);
  String get purposeLabel => InvoiceCopy.purposeLabel(purposeRaw, isAr: isAr);

  String get periodKindLabel {
    final billing = '${row['billing_period'] ?? ''}'.trim();
    if (billing.isNotEmpty) {
      return InvoiceCopy.periodLabel(billing, isAr: isAr);
    }
    return InvoiceCopy.periodFromRow(row, isAr: isAr);
  }

  DateTime? get _periodStartAt {
    final s = subscription;
    if (s == null) return null;
    return DateTime.tryParse('${s['starts_at'] ?? s['start_date'] ?? ''}');
  }

  DateTime? get _periodEndAt {
    final s = subscription;
    if (s == null) return null;
    return DateTime.tryParse('${s['ends_at'] ?? s['end_date'] ?? ''}');
  }

  String get periodLabel {
    final kind = periodKindLabel;
    final start = _periodStartAt;
    final end = _periodEndAt;
    if (start == null && end == null) return kind;
    final from = start != null ? InvoiceCopy.slashDate(start) : '—';
    final to = end != null ? InvoiceCopy.slashDate(end) : '—';
    return isAr ? '$kind  من $from إلى $to' : '$kind  from $from to $to';
  }

  String get methodLabel {
    final brand = _cardBrandFromGateway();
    if (brand.isNotEmpty) {
      return InvoiceCopy.methodLabel(brand, isAr: isAr);
    }
    final raw = '${row['payment_method'] ?? ''}'.trim();
    if (raw.isEmpty) return isAr ? 'غير متوفر' : 'Unavailable';
    return InvoiceCopy.methodLabel(raw, isAr: isAr);
  }

  String _cardBrandFromGateway() {
    final source = _gateway['source'];
    Map<String, dynamic>? src;
    if (source is Map) {
      src = Map<String, dynamic>.from(
        source.map((k, v) => MapEntry(k.toString(), v)),
      );
    }
    final company = '${src?['company'] ?? src?['scheme'] ?? src?['brand'] ?? _gateway['card_brand'] ?? ''}'
        .trim()
        .toLowerCase();
    if (company.contains('mada')) return 'mada';
    if (company.contains('visa')) return 'visa';
    if (company.contains('master')) return 'mastercard';
    final type = '${src?['type'] ?? row['payment_method'] ?? ''}'.toLowerCase();
    if (type.contains('mada')) return 'mada';
    if (type.contains('saved') || type == 'token') return 'saved';
    final pan = '${src?['number'] ?? src?['last_four'] ?? ''}';
    final scheme = detectCardSchemeFromPan(pan);
    if (scheme == 'mada' || scheme == 'visa' || scheme == 'mastercard') {
      return scheme;
    }
    return '';
  }

  String get statusCode {
    final raw = '${row['status'] ?? ''}'.toLowerCase().trim();
    if (raw == 'success' ||
        raw == 'paid' ||
        raw == 'completed' ||
        raw == 'succeeded' ||
        raw == 'captured') {
      return 'success';
    }
    if (raw == 'refunded' || raw == 'refund') return 'refunded';
    if (raw == 'partially_refunded' || raw == 'partial_refund') {
      return 'partially_refunded';
    }
    if (raw == 'authorized') return 'authorized';
    if (raw == 'pending' || raw == 'processing' || raw == 'initiated') {
      return 'pending';
    }
    if (raw == 'voided') return 'voided';
    if (raw == 'expired') return 'expired';
    if (raw == 'abandoned') return 'abandoned';
    if (raw == 'canceled' || raw == 'cancelled') return 'cancelled';
    if (raw == 'failed' || raw == 'error' || raw == 'declined') return 'failed';
    return raw.isEmpty ? 'pending' : raw;
  }

  String get statusLabel => InvoiceCopy.statusLabel(statusCode, isAr: isAr);

  DateTime? get occurredAt {
    final raw = row['paid_at'] ?? row['completed_at'] ?? row['created_at'];
    return DateTime.tryParse('$raw');
  }

  String get dateLine {
    final dt = occurredAt;
    if (dt == null) return '';
    return InvoiceCopy.dualCalendar(dt, isAr: isAr);
  }

  String get latinDateLine {
    final dt = occurredAt;
    if (dt == null) return '';
    return InvoiceCopy.latinDateTime(dt);
  }

  String? get paymentReference {
    final g = '${row['gateway_transaction_id'] ?? ''}'.trim();
    if (g.isEmpty) return null;
    if (looksLikeUuid(g) && g == '${row['id'] ?? ''}'.trim()) return null;
    return g;
  }

  String? get subscriptionStart {
    final dt = _periodStartAt;
    if (dt == null) return null;
    return InvoiceCopy.slashDate(dt);
  }

  String? get subscriptionEnd {
    final dt = _periodEndAt;
    if (dt == null) return null;
    return InvoiceCopy.slashDate(dt);
  }

  String amountUi() => AppMoney.formatWithCurrencyCode(
        amount,
        isAr: isAr,
        currencyCode: currency,
      );

  String amountPdf() => AppMoney.formatForPdf(
        amount,
        isAr: isAr,
        currencyCode: currency,
      );

  String amountExport() => AppMoney.formatForExport(
        amount,
        isAr: isAr,
        currencyCode: currency,
      );

  String get pdfFileName {
    if (hasInvoiceNumber) return 'Invoice_$invoiceNumber.pdf';
    return 'Invoice_pending.pdf';
  }

  String get excelFileName {
    if (hasInvoiceNumber) return 'Invoice_$invoiceNumber.xlsx';
    final y = DateTime.now().toUtc();
    return 'Invoices_${y.year}-${y.month.toString().padLeft(2, '0')}.xlsx';
  }

  /// QR تحقق تجاري: رقم الفاتورة الرسمي فقط — بلا UUID أو بيانات بطاقة.
  String get qrPayload {
    final b = StringBuffer();
    b.writeln(AppBranding.invoiceLetterheadBrandName(isAr: isAr));
    b.writeln(isAr ? 'فاتورة' : 'INVOICE');
    if (hasInvoiceNumber) {
      b.writeln(invoiceNumber);
    }
    b.writeln(amountPdf());
    b.writeln(statusLabel);
    if (dateLine.isNotEmpty) b.writeln(dateLine);
    return b.toString().trim();
  }

  bool isEligibleRevenue() => statusCode == 'success';

  bool isRefundedTab() =>
      statusCode == 'refunded' || statusCode == 'partially_refunded';
}
