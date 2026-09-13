/// التقسيم الإداري الرسمي: 13 منطقة ومحافظاتها (المصدر: التقسيم المعتمد للمملكة).
/// المدن والأحياء تُربَط فقط إذا كانت المحافظة ضمن هذه القائمة للمنطقة المختارة.
abstract final class SaudiOfficialAdmin {
  static const Map<String, List<(String ar, String en)>> byRegionId = {
    'riyadh': [
      ('الرياض', 'Riyadh'),
      ('الدرعية', 'Diriyah'),
      ('الخرج', 'Al Kharj'),
      ('الدوادمي', 'Al Duwadimi'),
      ('المجمعة', 'Al Majmaah'),
      ('القويعية', 'Al Quwayiyah'),
      ('وادي الدواسر', 'Wadi Al Dawasir'),
      ('الأفلاج', 'Aflaj'),
      ('الزلفي', 'Az Zulfi'),
      ('شقراء', 'Shaqra'),
      ('حوطة بني تميم', 'Hawtat Bani Tamim'),
      ('عفيف', 'Afif'),
      ('السليل', 'As Sulayyil'),
      ('ضرما', 'Duruma'),
      ('المزاحمية', 'Al Muzahimiyah'),
      ('رماح', 'Rumah'),
      ('ثادق', 'Thadiq'),
      ('حريملاء', 'Huraymila'),
      ('الحريق', 'Al Hariq'),
      ('الغاط', 'Al Ghat'),
      ('مرات', 'Marat'),
    ],
    'makkah': [
      ('مكة المكرمة', 'Makkah'),
      ('جدة', 'Jeddah'),
      ('الطائف', 'Taif'),
      ('القنفذة', 'Al Qunfudhah'),
      ('الليث', 'Al Lith'),
      ('رابغ', 'Rabigh'),
      ('خليص', 'Khulais'),
      ('الكامل', 'Al Kamil'),
      ('أضم', 'Adham'),
      ('رنية', 'Ranyah'),
      ('تربة', 'Turbah'),
      ('الخرمة', 'Al Khurmah'),
      ('المويه', 'Al Muwayh'),
      ('ميسان', 'Maysan'),
      ('بحرة', 'Bahrah'),
    ],
    'madinah': [
      ('المدينة المنورة', 'Madinah'),
      ('ينبع', 'Yanbu'),
      ('العلا', 'Al Ula'),
      ('مهد الذهب', 'Mahd Al Dhahab'),
      ('الحناكية', 'Al Hinakiyah'),
      ('بدر', 'Badr'),
      ('خيبر', 'Khaybar'),
      ('العيص', 'Al Iss'),
      ('وادي الفرع', 'Wadi Al Fara'),
    ],
    'qassim': [
      ('بريدة', 'Buraydah'),
      ('عنيزة', 'Unayzah'),
      ('الرس', 'Ar Rass'),
      ('المذنب', 'Al Mithnab'),
      ('البكيرية', 'Al Bukayriyah'),
      ('البدائع', 'Al Badai'),
      ('الأسياح', 'Al Asyah'),
      ('النبهانية', 'Al Nabbhaniyah'),
      ('عيون الجواء', 'Uyun Al Jawa'),
      ('رياض الخبراء', 'Riyad Al Khabra'),
      ('عقلة الصقور', 'Uqlat Al Suqur'),
      ('ضرية', 'Dariyah'),
    ],
    'eastern': [
      ('الدمام', 'Dammam'),
      ('الأحساء', 'Al Ahsa'),
      ('حفر الباطن', 'Hafar Al Batin'),
      ('الجبيل', 'Jubail'),
      ('القطيف', 'Qatif'),
      ('الخبر', 'Khobar'),
      ('الخفجي', 'Khafji'),
      ('رأس تنورة', 'Ras Tanura'),
      ('بقيق', 'Buqayq'),
      ('النعيرية', 'Nairyah'),
      ('قرية العليا', 'Qaryat Al Ulya'),
      ('العديد', 'Al Udayd'),
    ],
    'asir': [
      ('أبها', 'Abha'),
      ('خميس مشيط', 'Khamis Mushait'),
      ('بيشة', 'Bisha'),
      ('النماص', 'Al Namas'),
      ('محايل', 'Muhayil'),
      ('سراة عبيدة', 'Sarat Abidah'),
      ('تثليث', 'Tathlith'),
      ('رجال ألمع', 'Rijal Alma'),
      ('أحد رفيدة', 'Ahad Rifaydah'),
      ('ظهران الجنوب', 'Dhahran Al Janub'),
      ('بلقرن', 'Balqarn'),
      ('المجاردة', 'Al Majardah'),
      ('بارق', 'Bariq'),
      ('تنومة', 'Tanumah'),
      ('طريب', 'Tarib'),
    ],
    'tabuk': [
      ('تبوك', 'Tabuk'),
      ('الوجه', 'Al Wajh'),
      ('ضباء', 'Duba'),
      ('تيماء', 'Tayma'),
      ('أملج', 'Umluj'),
      ('حقل', 'Haql'),
      ('البدع', 'Al Bad'),
    ],
    'hail': [
      ('حائل', 'Hail'),
      ('بقعاء', 'Baqaa'),
      ('الغزالة', 'Al Ghazalah'),
      ('الشنان', 'Al Shinan'),
      ('الحائط', 'Al Hait'),
      ('السليمي', 'Al Sulaimi'),
      ('الشملي', 'Al Shamli'),
      ('موقق', 'Mawqaq'),
      ('سميراء', 'Sumaira'),
    ],
    'northern': [
      ('عرعر', 'Arar'),
      ('رفحاء', 'Rafha'),
      ('طريف', 'Turaif'),
      ('العويقيلة', 'Al Uwayqilah'),
    ],
    'jazan': [
      ('جازان', 'Jazan'),
      ('صبيا', 'Sabya'),
      ('أبو عريش', 'Abu Arish'),
      ('صامطة', 'Samtah'),
      ('الحرث', 'Al Harth'),
      ('ضمد', 'Damad'),
      ('الريث', 'Al Reeth'),
      ('فرسان', 'Farasan'),
      ('الدائر', 'Al Dair'),
      ('أحد المسارحة', 'Ahad Al Masarihah'),
      ('العارضة', 'Al Aridah'),
      ('العيدابي', 'Al Aydabi'),
      ('فيفاء', 'Fayfa'),
      ('هروب', 'Harub'),
      ('بيش', 'Baysh'),
    ],
    'najran': [
      ('نجران', 'Najran'),
      ('شرورة', 'Sharurah'),
      ('حبونا', 'Hubuna'),
      ('بدر الجنوب', 'Badr Al Janub'),
      ('يدمة', 'Yadamah'),
      ('ثار', 'Thar'),
      ('خباش', 'Khubash'),
      ('الخرخير', 'Al Kharkhir'),
    ],
    'bahah': [
      ('الباحة', 'Al Bahah'),
      ('بلجرشي', 'Baljurashi'),
      ('المندق', 'Al Mandag'),
      ('المخواة', 'Al Mikhwah'),
      ('العقيق', 'Al Aqiq'),
      ('قلوة', 'Qilwah'),
      ('بني حسن', 'Bani Hassan'),
      ('غامد الزناد', 'Ghamid Al Zinad'),
      ('الحجرة', 'Al Hajrah'),
    ],
    'jawf': [
      ('سكاكا', 'Sakaka'),
      ('القريات', 'Al Qurayyat'),
      ('دومة الجندل', 'Dumat Al Jandal'),
      ('طبرجل', 'Tabarjal'),
    ],
  };

  /// أسماء المناطق كما في `saudi_locations.json` (13 منطقة).
  static const List<(String ar, String en)> regionLabels = [
    ('منطقة الرياض', 'Riyadh'),
    ('منطقة مكة المكرمة', 'Makkah'),
    ('منطقة المدينة المنورة', 'Madinah'),
    ('منطقة القصيم', 'Qassim'),
    ('المنطقة الشرقية', 'Eastern Province'),
    ('منطقة عسير', 'Asir'),
    ('منطقة تبوك', 'Tabuk'),
    ('منطقة حائل', 'Hail'),
    ('منطقة الحدود الشمالية', 'Northern Borders'),
    ('منطقة جازان', 'Jazan'),
    ('منطقة نجران', 'Najran'),
    ('منطقة الباحة', 'Bahah'),
    ('منطقة الجوف', 'Jawf'),
  ];

  static List<String> officialRegionNames({required bool isAr}) => [
        for (final r in regionLabels) isAr ? r.$1 : r.$2,
      ];

  static String? canonicalRegionName(String raw, {required bool isAr}) {
    final id = regionIdOf(raw);
    if (id == null) return null;
    for (final r in regionLabels) {
      if (regionIdOf(r.$1) == id) return isAr ? r.$1 : r.$2;
    }
    return null;
  }

  static bool sameRegion(String a, String b) {
    final ia = regionIdOf(a);
    final ib = regionIdOf(b);
    if (ia != null && ib != null) return ia == ib;
    return a.trim() == b.trim();
  }

  /// تهجئات المناطق من بيانات الهيئة المفتوحة (region_mapping.csv).
  static const Map<String, String> _openDataRegionAliases = {
    'riyadh': 'riyadh',
    'makkah': 'makkah',
    'mecca': 'makkah',
    'madinah': 'madinah',
    'medina': 'madinah',
    'qassim': 'qassim',
    'qasim': 'qassim',
    'eastern': 'eastern',
    'eastern province': 'eastern',
    'ash sharqiyah': 'eastern',
    'asir': 'asir',
    'aseer': 'asir',
    'tabuk': 'tabuk',
    'hail': 'hail',
    "ha'il": 'hail',
    'northern': 'northern',
    'northern borders': 'northern',
    'jazan': 'jazan',
    'jizan': 'jazan',
    'najran': 'najran',
    'bahah': 'bahah',
    'baha': 'bahah',
    'al baha': 'bahah',
    'jawf': 'jawf',
    'al jawf': 'jawf',
    'al jouf': 'jawf',
    'jouf': 'jawf',
    'الرياض': 'riyadh',
    'منطقة الرياض': 'riyadh',
    'مكة المكرمة': 'makkah',
    'مكة المكرمه': 'makkah',
    'منطقة مكة المكرمة': 'makkah',
    'منطقة مكة المكرمه': 'makkah',
    'الشرقية': 'eastern',
    'المنطقة الشرقية': 'eastern',
    'منطقة الشرقية': 'eastern',
    'القصيم': 'qassim',
    'منطقة القصيم': 'qassim',
    'المدينة المنورة': 'madinah',
    'المدينة المنوره': 'madinah',
    'منطقة المدينة المنورة': 'madinah',
    'منطقة المدينة المنوره': 'madinah',
    'عسير': 'asir',
    'منطقة عسير': 'asir',
    'حائل': 'hail',
    'منطقة حائل': 'hail',
    'تبوك': 'tabuk',
    'منطقة تبوك': 'tabuk',
    'جازان': 'jazan',
    'منطقة جازان': 'jazan',
    'الجوف': 'jawf',
    'منطقة الجوف': 'jawf',
    'نجران': 'najran',
    'منطقة نجران': 'najran',
    'الحدود الشمالية': 'northern',
    'الحدود الشماليه': 'northern',
    'منطقة الحدود الشمالية': 'northern',
    'منطقة الحدود الشماليه': 'northern',
    'الباحة': 'bahah',
    'منطقة الباحة': 'bahah',
  };

  static String? regionIdOf(String raw) {
    final original = raw.trim();
    if (original.isEmpty) return null;
    final exact = _openDataRegionAliases[original] ??
        _openDataRegionAliases[original.toLowerCase()];
    if (exact != null) return exact;
    final s = original.toLowerCase();
    bool has(String a, String b) => s.contains(a) || s.contains(b);
    if (has('رياض', 'riyadh')) return 'riyadh';
    if (has('مكة', 'makkah') || has('mecca', 'makkah')) return 'makkah';
    if (has('مدينة', 'madinah') || has('medina', 'madinah')) return 'madinah';
    if (has('قصيم', 'qassim') || has('qasim', 'qassim')) return 'qassim';
    if (has('الشرقية', 'eastern') ||
        has('eastern province', 'ash sharqiyah') ||
        s == 'eastern') {
      return 'eastern';
    }
    if (has('عسير', 'asir') || has('aseer', 'asir')) return 'asir';
    if (has('تبوك', 'tabuk')) return 'tabuk';
    if (has('حائل', 'hail') || has('ha\'il', 'hail')) return 'hail';
    if (has('حدود', 'northern') || has('عرعر', 'northern')) return 'northern';
    if (has('جازان', 'jazan') || has('jizan', 'jazan')) return 'jazan';
    if (has('نجران', 'najran')) return 'najran';
    if (has('باحة', 'bahah') || has('baha', 'bahah')) return 'bahah';
    if (has('جوف', 'jawf') || has('al jawf', 'jawf') || has('jouf', 'jawf')) {
      return 'jawf';
    }
    return null;
  }

  static List<String> governorates({
    required String region,
    required bool isAr,
  }) {
    final id = regionIdOf(region);
    if (id == null) return const [];
    final rows = byRegionId[id] ?? const [];
    return [for (final r in rows) isAr ? r.$1 : r.$2];
  }

  static bool isOfficialGovernorate({
    required String region,
    required String governorate,
  }) {
    final g = governorate.trim();
    if (g.isEmpty) return false;
    final id = regionIdOf(region);
    if (id == null) return false;
    final rows = byRegionId[id] ?? const [];
    final n = _norm(g);
    for (final r in rows) {
      if (_norm(r.$1) == n || _norm(r.$2) == n) return true;
    }
    return false;
  }

  static String _norm(String s) =>
      s.trim().replaceAll('ة', 'ه').replaceAll('أ', 'ا').replaceAll('إ', 'ا').replaceAll('آ', 'ا');

  /// اسم إنجليزي رسمي إن وُجدت مطابقة لمنطقة أو محافظة.
  static String? englishOf(String raw) {
    var t = raw.trim();
    if (t.isEmpty) return null;
    for (final prefix in ['محافظة ', 'منطقة ', 'مدينة ']) {
      if (t.startsWith(prefix)) {
        final stripped = t.substring(prefix.length).trim();
        if (stripped.isNotEmpty) t = stripped;
        break;
      }
    }
    final n = _norm(t);
    if (n.isEmpty) return null;
    for (final r in regionLabels) {
      if (_norm(r.$1) == n || _norm(r.$2) == n) return r.$2;
    }
    for (final list in byRegionId.values) {
      for (final r in list) {
        if (_norm(r.$1) == n || _norm(r.$2) == n) return r.$2;
      }
    }
    return null;
  }

  static String localized(String raw, {required bool isAr}) {
    final t = raw.trim();
    if (t.isEmpty || isAr) return t;
    return englishOf(t) ?? t;
  }
}
