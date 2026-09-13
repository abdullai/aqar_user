import '../../services/saudi_locations_service.dart';
import '../geo/saudi_official_admin.dart';
import '../listing/property_type_catalog.dart';
import 'arabic_romanize.dart';

/// اختيار حقل ثنائي اللغة + قاموس للمنصة (أنواع، مناطق، عبارات إعلان).
///
/// لا يوجد مترجم سحابي: النص الحر غير المعروف يبقى عربياً.
/// أي شاشة أو بطاقة تعرض بيانات من القاعدة تمرّ من [forUi] عندما تكون الواجهة إنجليزية.
abstract final class LocaleContent {
  static final _arLetters = RegExp(r'[\u0600-\u06FF]');
  static final _splitKeep = RegExp(r'(\s+|·|,|،|/|-|–|—)');

  static Map<String, String>? _exact;
  static Map<String, String>? _folded;
  static final _placesArEn = <String, String>{};
  static final _placesEnAr = <String, String>{};
  static final _displayToStored = <String, String>{};

  static bool looksArabic(String raw) => _arLetters.hasMatch(raw);

  static String pick({
    required bool isAr,
    String? ar,
    String? en,
    String? fallback,
  }) {
    final a = (ar ?? '').trim();
    final e = (en ?? '').trim();
    final f = (fallback ?? '').trim();
    if (isAr) {
      if (a.isNotEmpty) return a;
      if (f.isNotEmpty) return f;
      return e;
    }
    if (e.isNotEmpty) return e;
    if (f.isNotEmpty && !looksArabic(f)) return f;
    if (a.isNotEmpty) {
      final g = forUi(a, isAr: false);
      if (g != a) return g;
    }
    if (f.isNotEmpty) return forUi(f, isAr: false);
    return a;
  }

  static String fromMap(
    Map<String, dynamic>? row, {
    required bool isAr,
    required List<String> arKeys,
    required List<String> enKeys,
    String? fallback,
  }) {
    if (row == null) return pick(isAr: isAr, fallback: fallback);
    String first(List<String> keys) {
      for (final k in keys) {
        final v = (row[k] ?? '').toString().trim();
        if (v.isNotEmpty) return v;
      }
      return '';
    }

    return pick(
      isAr: isAr,
      ar: first(arKeys),
      en: first(enKeys),
      fallback: fallback,
    );
  }

  /// أجزاء موقع/عنوان: تُترجم كل قطعة عند الواجهة الإنجليزية.
  static List<String> parts(Iterable<String> raw, {required bool isAr}) => [
        for (final p in raw)
          if (p.trim().isNotEmpty) forUi(p.trim(), isAr: isAr),
      ];

  /// يحمّل مدن/مناطق/محافظات المملكة (عربي↔إنجليزي) من ملفات الأصول.
  static Future<void> hydratePlaces() async {
    try {
      final all =
          await SaudiLocationsService.instance.loadAll(includeExtra: true);
      void add(String ar, String en) {
        final a = ar.trim();
        final e = en.trim();
        if (a.isEmpty || e.isEmpty) return;
        _placesArEn[a] = e;
        _placesEnAr[e] = a;
        _placesEnAr[e.toLowerCase()] = a;
      }

      for (final loc in all) {
        add(loc.cityAr, loc.cityEn);
        add(loc.regionAr, loc.regionEn);
        add(loc.governorateAr ?? '', loc.governorateEn ?? '');
      }
      _exact = null;
      _folded = null;
    } catch (_) {}
  }

  /// القيمة المخزَّنة (عربي للمكان إن وُجدت مطابقة) بعد اختيار من قائمة إنجليزية.
  static String toStored(String display) {
    final t = display.trim();
    if (t.isEmpty) return t;
    if (looksArabic(t)) return t;
    return _displayToStored[t] ??
        _placesEnAr[t] ??
        _placesEnAr[t.toLowerCase()] ??
        t;
  }

  /// إن كانت الواجهة إنجليزية والنص عربي معروف — يُترجم؛ وإلا رَوْمَنة حرفية.
  /// إن كانت الواجهة عربية والنص إنجليزي معروف — يُعاد العربي الرسمي.
  static String forUi(String raw, {required bool isAr}) {
    final s = raw.trim();
    if (s.isEmpty) return s;
    if (isAr) {
      if (!looksArabic(s)) {
        final fromPlaces = _placesEnAr[s] ?? _placesEnAr[s.toLowerCase()];
        if (fromPlaces != null) return fromPlaces;
        for (final e in _displayToStored.entries) {
          if (e.key.toLowerCase() == s.toLowerCase()) return e.value;
        }
        return s;
      }
      return s;
    }
    if (!looksArabic(s)) return s;
    final hit = _lookup(s);
    if (hit != null) {
      _displayToStored[hit] = s;
      return hit;
    }
    final place = SaudiOfficialAdmin.englishOf(s);
    if (place != null) {
      _displayToStored[place] = s;
      return place;
    }
    final tokened = s.splitMapJoin(
      _splitKeep,
      onMatch: (m) => m[0] ?? '',
      onNonMatch: (tok) {
        if (tok.isEmpty || !looksArabic(tok)) return tok;
        final t = _lookup(tok) ?? SaudiOfficialAdmin.englishOf(tok);
        if (t != null) {
          _displayToStored[t] = tok;
          return t;
        }
        final rom = ArabicRomanize.of(tok);
        _displayToStored[rom] = tok;
        return rom;
      },
    );
    if (tokened != s) {
      _displayToStored[tokened] = s;
      return tokened;
    }
    final rom = ArabicRomanize.of(s);
    _displayToStored[rom] = s;
    return rom;
  }

  static String glossary(String raw) => _lookup(raw) ?? raw.trim();

  static String? _lookup(String raw) {
    final t = raw.trim();
    if (t.isEmpty) return null;
    final exact = _glossary[t];
    if (exact != null) return exact;
    return _foldedGlossary[_fold(t)];
  }

  static String _fold(String s) => s
      .trim()
      .replaceAll('ة', 'ه')
      .replaceAll('أ', 'ا')
      .replaceAll('إ', 'ا')
      .replaceAll('آ', 'ا')
      .replaceAll('ى', 'ي')
      .replaceAll('ؤ', 'و')
      .replaceAll('ئ', 'ي');

  static Map<String, String> get _glossary {
    if (_exact != null) return _exact!;
    final m = <String, String>{..._phrases, ..._placesArEn};
    for (final e in PropertyTypeCatalog.entries) {
      final ar = (e['ar'] ?? '').trim();
      final en = (e['en'] ?? '').trim();
      if (ar.isNotEmpty && en.isNotEmpty) m[ar] = en;
    }
    for (final g in PropertyTypeCatalog.typeGroups) {
      m[g.ar] = g.en;
    }
    for (final r in SaudiOfficialAdmin.regionLabels) {
      m[r.$1] = r.$2;
    }
    for (final list in SaudiOfficialAdmin.byRegionId.values) {
      for (final r in list) {
        m[r.$1] = r.$2;
      }
    }
    _exact = m;
    return m;
  }

  static Map<String, String> get _foldedGlossary {
    if (_folded != null) return _folded!;
    final m = <String, String>{};
    for (final e in _glossary.entries) {
      m[_fold(e.key)] = e.value;
    }
    _folded = m;
    return m;
  }

  static const _phrases = <String, String>{
    'مسبح': 'Pool',
    'نادي': 'Gym',
    'نادي رياضي': 'Gym',
    'مصعد': 'Elevator',
    'أمن': 'Security',
    'حراسة': 'Security',
    'حديقة': 'Garden',
    'شرفة': 'Balcony',
    'تكييف': 'A/C',
    'موقف': 'Parking',
    'مواقف': 'Parking',
    'واي فاي': 'Wi-Fi',
    'غرفة خادمة': 'Maid room',
    'غرفة سائق': 'Driver room',
    'مستودع': 'Storage',
    'سطح': 'Roof',
    'مطبخ': 'Kitchen',
    'مجلس': 'Majlis',
    'حوش': 'Yard',
    'مفتوح': 'Open',
    'مفروش': 'Furnished',
    'غير مفروش': 'Unfurnished',
    'تم الحل': 'Resolved',
    'مُصعَّد': 'Escalated',
    'للبيع': 'for sale',
    'للإيجار': 'for rent',
    'للمزاد': 'for auction',
    'للاستثمار': 'for investment',
    'مزاد': 'Auction',
    'إيجار يومي': 'Daily rent',
    'إيجار شهري': 'Monthly rent',
    'إيجار سنوي': 'Yearly rent',
    'استثمار': 'Investment',
    'مطلوب': 'Wanted',
    'عاجل': 'Urgent',
    'عادي': 'Normal',
    'فوري': 'Instant',
    'إعلان': 'Listing',
    'طلب': 'Request',
    'مسوق': 'Marketer',
    'مالك': 'Owner',
    'مؤسسة': 'Organization',
    'فردي': 'Individual',
    'سكني': 'Residential',
    'تجاري': 'Commercial',
    'إداري': 'Office',
    'غرف': 'rooms',
    'غرفة': 'room',
    'غرف نوم': 'bedrooms',
    'حمام': 'bath',
    'حمامات': 'baths',
    'دور': 'floor',
    'واجهة': 'facade',
    'شمال': 'North',
    'جنوب': 'South',
    'شرق': 'East',
    'غرب': 'West',
    'شمال شرقي': 'Northeast',
    'شمال غربي': 'Northwest',
    'جنوب شرقي': 'Southeast',
    'جنوب غربي': 'Southwest',
    'متر مربع': 'm²',
    'مترا مربعا': 'm²',
    'مترًا مربعًا': 'm²',
    'م²': 'm²',
    'حي': 'District',
    'مدينة': 'City',
    'محافظة': 'Governorate',
    'منطقة': 'Region',
    'صك': 'Deed',
    'رخصة': 'License',
    'رخصة فال': 'FAL license',
    'رخصة إعلان': 'Ad license',
    'منشور': 'Published',
    'محجوز': 'Reserved',
    'ملغى': 'Cancelled',
    'مؤرشف': 'Archived',
    'بانتظار المسوقين': 'Waiting for marketers',
    'مسوق محدد': 'Marketer selected',
    'بانتظار العقد': 'Contract pending',
    'عقد موقّع': 'Contract signed',
    'بانتظار التصريح': 'Permit pending',
    'تصريح صادر': 'Permit issued',
    'طالب': 'Requester',
    'معلن': 'Publisher',
  };
}
