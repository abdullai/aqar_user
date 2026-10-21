import '../../models/property.dart';

/// تحليل محلي (دون إرسال النص لأي خدمة خارجية) لصياغة بحث عربية طبيعية مثل
/// «شقة للإيجار بميزانية 50 ألف 3 غرف الرياض» إلى معايير منظمة.
class ArabicSearchIntent {
  const ArabicSearchIntent({
    this.type,
    this.purpose,
    this.priceMin,
    this.priceMax,
    this.bedroomsMin,
    this.nearWork = false,
    this.workRadiusKm,
    this.keywords = const <String>[],
    this.rawQuery = '',
  });

  final PropertyType? type;

  /// sale | rent | auction | investment
  final String? purpose;
  final double? priceMin;
  final double? priceMax;
  final int? bedroomsMin;

  /// «قريب من عملي» — يُطبَّق محلياً على موقع العمل المحفوظ في جهاز المستخدم فقط.
  final bool nearWork;
  final double? workRadiusKm;

  /// كلمات متبقية (مدينة/حي/وصف) يجب أن تُطابَق نصياً.
  final List<String> keywords;
  final String rawQuery;

  bool get isStructured =>
      type != null ||
      purpose != null ||
      priceMin != null ||
      priceMax != null ||
      bedroomsMin != null ||
      nearWork;

  static const ArabicSearchIntent empty = ArabicSearchIntent();

  static const _digitsAr = '٠١٢٣٤٥٦٧٨٩';
  static const _digitsFa = '۰۱۲۳۴۵۶۷۸۹';

  static String normalize(String input) {
    var s = input.trim().toLowerCase();
    for (var i = 0; i < 10; i++) {
      s = s.replaceAll(_digitsAr[i], '$i').replaceAll(_digitsFa[i], '$i');
    }
    s = s
        .replaceAll(RegExp('[\u064B-\u065F\u0640]'), '')
        .replaceAll('أ', 'ا')
        .replaceAll('إ', 'ا')
        .replaceAll('آ', 'ا')
        .replaceAll('ة', 'ه')
        .replaceAll('ى', 'ي')
        .replaceAll('،', ' ')
        .replaceAll(RegExp(r'(?<=\d)[,٬](?=\d{3})'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return s;
  }

  static const _units = r'(?:\s*(الف|الاف|آلاف|مليون|ملايين|k))?';
  static const _num = r'(\d+(?:\.\d+)?)';

  static double? _amount(String num, String? unit) {
    final n = double.tryParse(num);
    if (n == null) return null;
    final u = (unit ?? '').toLowerCase();
    if (u == 'الف' || u == 'الاف' || u == 'k') return n * 1000;
    if (u == 'مليون' || u == 'ملايين') return n * 1000000;
    return n;
  }

  static const _stopWords = <String>{
    'ابي',
    'ابغي',
    'ابغى',
    'اريد',
    'ابحث',
    'عن',
    'لي',
    'في',
    'من',
    'الي',
    'قريب',
    'قريبه',
    'عملي',
    'بميزانيه',
    'ميزانيه',
    'ميزانيتي',
    'بسعر',
    'حدود',
    'تقريبا',
    'و',
    'ب',
    'ريال',
    'ر.س',
    'sar',
    'مطلوب',
    'عندي',
    'يكون',
    'تكون',
    'فيها',
    'فيه',
    'مع',
    'بحد',
    'اقصي',
    'اقصى',
    'حد',
  };

  static const _bedWords = <String, int>{
    'غرفه': 1,
    'غرفتين': 2,
    'غرفتان': 2,
    'ثلاث': 3,
    'ثلاثه': 3,
    'اربع': 4,
    'اربعه': 4,
    'خمس': 5,
    'خمسه': 5,
    'ست': 6,
    'سته': 6,
  };

  static ArabicSearchIntent parse(String query) {
    var q = normalize(query);
    if (q.isEmpty) return ArabicSearchIntent(rawQuery: query);

    PropertyType? type;
    String? purpose;
    double? pMin;
    double? pMax;
    int? beds;
    var nearWork = false;
    double? radius;

    String eat(RegExp re) {
      return q = q.replaceAll(re, ' ');
    }

    final workRe = RegExp(
      r'(?<![\u0600-\u06FF])(?:قريبه?|قرب|بجانب|جنب|بالقرب)\s*(?:من)?\s*(?:مقر\s*)?(?:عملي|شغلي|دوامي)(?![\u0600-\u06FF])',
    );
    if (workRe.hasMatch(q)) {
      nearWork = true;
      eat(workRe);
      final km = RegExp(
        r'(?:خلال|ضمن|في حدود|حدود)?\s*(\d{1,3})\s*(?:كم|كيلو)(?![\u0600-\u06FF])',
      ).firstMatch(q);
      if (km != null) {
        final v = double.tryParse(km.group(1)!);
        if (v != null && v >= 1 && v <= 100) radius = v;
        q = q.replaceFirst(km.group(0)!, ' ');
      }
    }

    // نوع العقار
    final typeRe = RegExp(
        r'(?<![\u0600-\u06FF])(فيلا|فلل|فله|شقه|شقق|ارض|اراضي)(?![\u0600-\u06FF])');
    final typeMatch = typeRe.firstMatch(q);
    if (typeMatch != null) {
      final t = typeMatch.group(1)!;
      type = switch (t) {
        'فيلا' || 'فلل' || 'فله' => PropertyType.villa,
        'شقه' || 'شقق' => PropertyType.apartment,
        _ => PropertyType.land,
      };
      eat(typeRe);
    }

    // الغرض
    final purposeRe = RegExp(
      r'(?<![\u0600-\u06FF])(للايجار|ايجار|استئجار|اجار|للبيع|بيع|شراء|تمليك|اشتري|مزاد|استثمار|استثماري|للاستثمار)(?![\u0600-\u06FF])',
    );
    final purposeMatch = purposeRe.firstMatch(q);
    if (purposeMatch != null) {
      final p = purposeMatch.group(1)!;
      purpose = switch (p) {
        'للايجار' || 'ايجار' || 'استئجار' || 'اجار' => 'rent',
        'مزاد' => 'auction',
        'استثمار' || 'استثماري' || 'للاستثمار' => 'investment',
        _ => 'sale',
      };
      eat(purposeRe);
    }

    // غرف النوم
    final bedDigits =
        RegExp(r'(\d{1,2})\s*(?:غرف|غرفه|غرفة|نوم)(?![\u0600-\u06FF])');
    final bedDigitMatch = bedDigits.firstMatch(q);
    if (bedDigitMatch != null) {
      beds = int.tryParse(bedDigitMatch.group(1)!);
      eat(bedDigits);
    } else {
      final bedWord = RegExp(
        r'(?<![\u0600-\u06FF])(غرفتين|غرفتان|ثلاثه|ثلاث|اربعه|اربع|خمسه|خمس|سته|ست)\s*(?:غرف|غرفه)?(?![\u0600-\u06FF])',
      );
      final m = bedWord.firstMatch(q);
      if (m != null &&
          (m.group(0)!.contains('غرف') ||
              m.group(1) == 'غرفتين' ||
              m.group(1) == 'غرفتان')) {
        beds = _bedWords[m.group(1)!];
        eat(bedWord);
      }
    }
    if (beds != null && (beds < 1 || beds > 20)) beds = null;

    // نطاق: من X الى Y
    final rangeRe =
        RegExp('(?:من)\\s*$_num$_units\\s*(?:الي|حتي|-)\\s*$_num$_units');
    final range = rangeRe.firstMatch(q);
    if (range != null) {
      final a = _amount(range.group(1)!, range.group(2));
      final b = _amount(range.group(3)!, range.group(4) ?? range.group(2));
      if (a != null && b != null) {
        pMin = a < b ? a : b;
        pMax = a < b ? b : a;
        eat(rangeRe);
      }
    }

    if (pMax == null) {
      final maxRe = RegExp(
        '(?<![\\u0600-\\u06FF])(?:حتي|اقل من|اقل|لا يزيد عن|لا تزيد عن|بحد اقصي|بحد اقصى|ميزانيتي|بميزانيه|ميزانيه|بسعر|في حدود|حدود|تحت|دون|ب)\\s*$_num$_units',
      );
      final m = maxRe.firstMatch(q);
      if (m != null) {
        final v = _amount(m.group(1)!, m.group(2));
        if (v != null && v > 0) {
          pMax = v;
          eat(maxRe);
        }
      }
    }
    if (pMax == null && pMin == null && (type != null || purpose != null)) {
      final bare = RegExp('(?<![\\d.])$_num$_units(?![\\d\\u0600-\\u06FF])');
      for (final m in bare.allMatches(q)) {
        final v = _amount(m.group(1)!, m.group(2));
        if (v != null && v >= 1000) {
          pMax = v;
          eat(RegExp(RegExp.escape(m.group(0)!)));
          break;
        }
      }
    }
    if (pMin == null) {
      final minRe = RegExp(
        '(?:اكثر من|فوق|لا يقل عن|ابتداء من|يبدا من)\\s*$_num$_units',
      );
      final m = minRe.firstMatch(q);
      if (m != null) {
        final v = _amount(m.group(1)!, m.group(2));
        if (v != null && v > 0) {
          pMin = v;
          eat(minRe);
        }
      }
    }

    final keywords = <String>[];
    for (final t in q.split(' ')) {
      final w = t.trim();
      if (w.isEmpty || _stopWords.contains(w)) continue;
      if (w.length < 2) continue;
      keywords.add(w);
      if (keywords.length >= 6) break;
    }

    return ArabicSearchIntent(
      type: type,
      purpose: purpose,
      priceMin: pMin,
      priceMax: pMax,
      bedroomsMin: beds,
      nearWork: nearWork,
      workRadiusKm: radius,
      keywords: List.unmodifiable(keywords),
      rawQuery: query.trim(),
    );
  }

  static String _fmtMoney(double v) {
    final n = v.round().toString();
    final b = StringBuffer();
    for (var i = 0; i < n.length; i++) {
      if (i > 0 && (n.length - i) % 3 == 0) b.write(',');
      b.write(n[i]);
    }
    return b.toString();
  }

  /// أجزاء مقروءة تشرح للمستخدم كيف فُهم بحثه.
  List<String> describe({required bool arabic}) {
    final out = <String>[];
    if (type != null) {
      out.add(switch (type!) {
        PropertyType.villa => arabic ? 'فيلا' : 'Villa',
        PropertyType.apartment => arabic ? 'شقة' : 'Apartment',
        PropertyType.land => arabic ? 'أرض' : 'Land',
      });
    }
    if (purpose != null) {
      out.add(switch (purpose!) {
        'rent' => arabic ? 'للإيجار' : 'For rent',
        'auction' => arabic ? 'مزاد' : 'Auction',
        'investment' => arabic ? 'استثمار' : 'Investment',
        _ => arabic ? 'للبيع' : 'For sale',
      });
    }
    if (priceMin != null && priceMax != null) {
      out.add(arabic
          ? 'من ${_fmtMoney(priceMin!)} إلى ${_fmtMoney(priceMax!)} ر.س'
          : '${_fmtMoney(priceMin!)}–${_fmtMoney(priceMax!)} SAR');
    } else if (priceMax != null) {
      out.add(arabic
          ? 'حتى ${_fmtMoney(priceMax!)} ر.س'
          : 'Up to ${_fmtMoney(priceMax!)} SAR');
    } else if (priceMin != null) {
      out.add(arabic
          ? 'من ${_fmtMoney(priceMin!)} ر.س'
          : 'From ${_fmtMoney(priceMin!)} SAR');
    }
    if (bedroomsMin != null) {
      out.add(arabic ? '$bedroomsMin+ غرف' : '$bedroomsMin+ bedrooms');
    }
    if (nearWork) {
      out.add(arabic
          ? 'قريب من عملك${workRadiusKm != null ? ' (${workRadiusKm!.round()} كم)' : ''}'
          : 'Near your work');
    }
    for (final k in keywords) {
      out.add(k);
    }
    return out;
  }
}
