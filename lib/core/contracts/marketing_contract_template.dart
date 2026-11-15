import '../utils/date_helper.dart';
import '../utils/app_money.dart';

/// نص اتفاقية التسويق المعروض للمعلن قبل التوقيع الإلكتروني (مع التاريخ).
class MarketingContractTemplate {
  MarketingContractTemplate._();

  static String build({
    required bool isAr,
    String? contractId,
    required String requestId,
    required String listingTitle,
    required String city,
    required double marketingFee,
    required String currency,
    String? ownerName,
    String? marketerName,
    String? marketerEntityType,
    String? marketerLicenseNo,
    String? offerNotes,
    String? signatureDateIso,

    // -- بيانات فاتورة الإعلان (اختيارية: تُضاف للعقد إذا توفّرت) -----------
    //
    // عند تمريرها يُضاف للعقد قسم «ثانياً: قيمة العقار والفوترة» الذي يعرض
    // السعر الأساسي والضريبة (محتسبة/مضافة) وعمولة التسويق (نسبة/مقطوعة)،
    // مطابقاً تماماً للأسئلة في صفحة «إضافة الإعلان» وتفصيل الفاتورة.
    double? listingEnteredPrice,
    bool? listingPriceIncludesVat,
    double? listingVatRate, // مثال 0.05
    String? listingCommissionKind, // none | percent | fixed
    double? listingCommissionRate, // مثال 0.025
    double? listingCommissionAmount, // عند fixed
  }) {
    final parsed = DateHelper.tryParse(signatureDateIso)?.toLocal() ??
        DateTime.now().toLocal();
    final date = DateHelper.civilDigits(parsed);
    final notes = (offerNotes ?? '').trim();
    final cId = (contractId ?? '').trim();
    final owner = (ownerName ?? '').trim();
    final marketer = (marketerName ?? '').trim();
    final marketerType = (marketerEntityType ?? '').trim();
    final license = (marketerLicenseNo ?? '').trim();
    final fee = _formatMoney(marketingFee, isAr: isAr, currency: currency);

    final invoiceBlock = _buildInvoiceBlock(
      isAr: isAr,
      enteredPrice: listingEnteredPrice,
      priceIncludesVat: listingPriceIncludesVat,
      vatRate: listingVatRate,
      commissionKind: listingCommissionKind,
      commissionRate: listingCommissionRate,
      commissionAmount: listingCommissionAmount,
      currency: currency,
    );

    if (isAr) {
      return '''
عقد تسويق عقاري إلكتروني
${cId.isNotEmpty ? 'رقم العقد: $cId\n' : ''}تاريخ العقد: $date

رقم الطلب: $requestId
عنوان الإعلان: $listingTitle
المدينة: $city
أتعاب التسويق المتفق عليها: $fee
${invoiceBlock.isNotEmpty ? '\n$invoiceBlock\n' : ''}
أولاً: أطراف العقد
الطرف الأول: مالك / معلن العقار${owner.isNotEmpty ? ' ($owner)' : ''}، ويُعرَف بهوية حسابه وسجلاته في المنصة.
الطرف الثاني: المسوق العقاري المعتمد${marketer.isNotEmpty ? ' ($marketer)' : ''}${marketerType.isNotEmpty ? ' بصفته: $marketerType' : ''}${license.isNotEmpty ? '، رقم رخصته: $license' : ''}.

ثانياً: موضوع العقد
يفوّض الطرف الأول الطرف الثاني بتسويق العقار محل الطلب داخل المنصة، ومتابعة إجراءات عرض الإعلان وتجهيز المتطلبات النظامية اللازمة لاستخراج تصاريح الإعلان العقاري من منصة عقار/الجهات المختصة خلال مدة لا تتجاوز 72 ساعة من اكتمال التوقيع وتوفر البيانات والمستندات الصحيحة.

ثالثاً: الالتزامات
1. يقر الطرف الأول بصحة بيانات العقار والملكية أو التفويض، ويلتزم بتقديم أي بيانات أو مستندات تطلبها المنصة أو الجهة المختصة.
2. يلتزم الطرف الثاني ببذل العناية المهنية في التسويق، وعدم نشر الإعلان إلا بعد اكتمال التصاريح والمطابقة النظامية.
3. لا يجوز للطرف الثاني تمثيل بيانات غير صحيحة أو مخالفة لبيانات الترخيص أو رخصة فال أو ما يعادلها.
4. في حال عدم اكتمال التصريح خلال 72 ساعة لأسباب راجعة لعدم توفر البيانات أو رفض الجهة المختصة، يعاد الطلب للمراجعة أو يعرض على مسوقين آخرين وفق سير العمل داخل المنصة.
5. تكون أتعاب التسويق وفق العرض المقبول، ولا تستحق إلا بحسب ما توضحه الأنظمة والاتفاق داخل المنصة.

رابعاً: الإثبات الإلكتروني
يقر الطرفان بأن التوقيع الإلكتروني، وسجل التدقيق، ورمز الاستجابة السريع للتحقق، ورقم العقد، تعد قرائن إثبات معتبرة داخل المنصة، ويُرجع إليها عند أي مراجعة أو نزاع.

${notes.isNotEmpty ? 'ملاحظات العرض:\n$notes\n\n' : ''}خامساً: التوقيع
توقيع الطرف الأول (المعلن/المالك): وُقِع إلكترونياً بتاريخ $date
توقيع الطرف الثاني (المسوق العقاري/المنشأة): يكتمل من داخل التطبيق.
''';
    }

    return '''
Electronic Real Estate Marketing Agreement
${cId.isNotEmpty ? 'Contract no.: $cId\n' : ''}Contract date: $date

Request ID: $requestId
Listing title: $listingTitle
City: $city
Agreed marketing fee: $fee
${invoiceBlock.isNotEmpty ? '\n$invoiceBlock\n' : ''}
1. Parties
Party A: Property owner/advertiser${owner.isNotEmpty ? ' ($owner)' : ''}, identified by the platform account and records.
Party B: Licensed real estate marketer${marketer.isNotEmpty ? ' ($marketer)' : ''}${marketerType.isNotEmpty ? ', capacity: $marketerType' : ''}${license.isNotEmpty ? ', license no.: $license' : ''}.

2. Scope
Party A authorizes Party B to market the listed property through the platform and prepare the statutory requirements for issuing the real estate advertisement permits through Aqar/competent authorities within 72 hours after signatures and complete valid data.

3. Obligations
Party A confirms the accuracy of property and ownership/authorization data. Party B shall market professionally and shall not publish the listing before permit and compliance completion. Any mismatch with permit, FAL, or authority data may return the request for correction or redistribution according to platform workflow.

4. Electronic Evidence
The electronic signatures, audit trail, verification QR, and contract number are platform evidence for review and verification.

${notes.isNotEmpty ? 'Offer notes:\n$notes\n\n' : ''}5. Signatures
Party A (owner/advertiser): electronically signed on $date
Party B (marketer/entity): completed inside the app.
''';
  }

  static String _formatNumber(double v) {
    final s =
        v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2);
    final parts = s.split('.');
    final whole = parts.first.replaceAllMapped(
      RegExp(r'\B(?=(\d{3})+(?!\d))'),
      (_) => ',',
    );
    return parts.length == 1 ? whole : '$whole.${parts.last}';
  }

  static String _formatMoney(
    double value, {
    required bool isAr,
    required String currency,
  }) {
    final number = _formatNumber(value);
    final code =
        currency.trim().isEmpty ? 'SAR' : currency.trim().toUpperCase();
    return code == 'SAR'
        ? AppMoney.sarPhrase(number, isAr: isAr)
        : '$number $code';
  }

  /// يبني قسم «قيمة العقار والفوترة» داخل نص العقد.
  /// — يعكس الإجابات في صفحة «إضافة الإعلان» حرفياً:
  ///   * الضريبة: «محتسبة من السعر الإجمالي» أو «تُضاف على السعر الأساسي».
  ///   * العمولة: «نسبة 2.5% من السعر الأساسي» أو «مبلغ مقطوع متفق عليه».
  /// — إن لم تكن بيانات الفوترة متاحة يُرجع نصاً فارغاً لإبقاء العقد متوافقاً.
  static String _buildInvoiceBlock({
    required bool isAr,
    double? enteredPrice,
    bool? priceIncludesVat,
    double? vatRate,
    String? commissionKind,
    double? commissionRate,
    double? commissionAmount,
    required String currency,
  }) {
    if (enteredPrice == null || enteredPrice <= 0) return '';
    final inclVat = priceIncludesVat ?? true;
    final vRate = vatRate ?? 0.05;
    final basePrice = inclVat ? (enteredPrice / (1.0 + vRate)) : enteredPrice;
    final vatAmount = basePrice * vRate;
    final totalWithVat = basePrice + vatAmount;
    final kind = (commissionKind ?? 'none').trim().toLowerCase();
    final commRate = commissionRate ?? 0.025;
    double commVal;
    switch (kind) {
      case 'percent':
        commVal = basePrice * commRate;
        break;
      case 'fixed':
        commVal = commissionAmount ?? 0;
        break;
      default:
        commVal = 0;
    }
    final finalTotal = totalWithVat + commVal;

    final vatPct = vRate * 100;
    final vatPctStr = vatPct == vatPct.roundToDouble()
        ? vatPct.toInt().toString()
        : vatPct.toStringAsFixed(1);
    final commPct = commRate * 100;
    final commPctStr = commPct == commPct.roundToDouble()
        ? commPct.toInt().toString()
        : commPct.toStringAsFixed(1);

    if (isAr) {
      final buf = StringBuffer();
      buf.writeln('ثانياً: قيمة العقار والفوترة (مطابقة لـ ZATCA و REGA)');
      buf.writeln(
          '• السعر الذي أدخله المعلن: ${_formatMoney(enteredPrice, isAr: isAr, currency: currency)} '
          '(${inclVat ? 'شامل ضريبة القيمة المضافة' : 'غير شامل الضريبة'}).');
      buf.writeln(
          '• السعر الأساسي قبل الضريبة: ${_formatMoney(basePrice, isAr: isAr, currency: currency)}.');
      buf.writeln(
          '• ضريبة القيمة المضافة ($vatPctStr%): ${_formatMoney(vatAmount, isAr: isAr, currency: currency)} '
          '— ${inclVat ? 'محتسبة من السعر الإجمالي' : 'تُضاف على السعر الأساسي'}.');
      buf.writeln(
          '• الإجمالي مع الضريبة: ${_formatMoney(totalWithVat, isAr: isAr, currency: currency)}.');
      switch (kind) {
        case 'percent':
          buf.writeln(
              '• عمولة التسويق العقاري: نسبة $commPctStr% من السعر الأساسي '
              '= ${_formatMoney(commVal, isAr: isAr, currency: currency)}.');
          break;
        case 'fixed':
          buf.writeln('• عمولة التسويق العقاري: مبلغ مقطوع متفق عليه = '
              '${_formatMoney(commVal, isAr: isAr, currency: currency)}.');
          break;
        default:
          buf.writeln(
              '• عمولة التسويق العقاري: لا توجد عمولة على هذا الإعلان.');
      }
      buf.write(
          '• المجموع النهائي للفاتورة: ${_formatMoney(finalTotal, isAr: isAr, currency: currency)} '
          '(الأساسي + الضريبة + العمولة).');
      return buf.toString();
    }

    final buf = StringBuffer();
    buf.writeln('2. Property value & invoice (ZATCA & REGA aligned)');
    buf.writeln(
        '- Advertiser-entered total: ${_formatMoney(enteredPrice, isAr: isAr, currency: currency)} '
        '(${inclVat ? 'VAT included' : 'VAT excluded'}).');
    buf.writeln(
        '- Base price before VAT: ${_formatMoney(basePrice, isAr: isAr, currency: currency)}.');
    buf.writeln(
        '- VAT ($vatPctStr%): ${_formatMoney(vatAmount, isAr: isAr, currency: currency)} — '
        '${inclVat ? 'included in entered total' : 'added on top of base price'}.');
    buf.writeln(
        '- Total with VAT: ${_formatMoney(totalWithVat, isAr: isAr, currency: currency)}.');
    switch (kind) {
      case 'percent':
        buf.writeln('- Marketing commission: $commPctStr% of base price '
            '= ${_formatMoney(commVal, isAr: isAr, currency: currency)}.');
        break;
      case 'fixed':
        buf.writeln('- Marketing commission: agreed fixed amount '
            '= ${_formatMoney(commVal, isAr: isAr, currency: currency)}.');
        break;
      default:
        buf.writeln('- Marketing commission: none on this listing.');
    }
    buf.write(
        '- Final invoice total: ${_formatMoney(finalTotal, isAr: isAr, currency: currency)} '
        '(base + VAT + commission).');
    return buf.toString();
  }
}
