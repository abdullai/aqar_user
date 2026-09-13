/// رَوْمَنة عربية → لاتينية للأسماء والأماكن عندما لا يوجد `*_en` رسمي.
/// ليست ترجمة معنى؛ للنطق الحرفي (حي النرجس، أسماء الأشخاص).
abstract final class ArabicRomanize {
  static final _ar = RegExp(r'[\u0600-\u06FF]');

  static bool looksArabic(String s) => _ar.hasMatch(s);

  static String of(String raw) {
    var s = raw.trim();
    if (s.isEmpty || !looksArabic(s)) return s;
    final named = _names[s];
    if (named != null) return named;
    final parts = s.split(RegExp(r'\s+'));
    if (parts.length > 1) {
      return parts.map((p) => of(p)).join(' ');
    }
    s = s.replaceAll('ـ', '');
    if (s.startsWith('ال')) {
      final rest = of(s.substring(2));
      if (rest.isEmpty) return 'Al';
      return 'Al-$rest';
    }
    final buf = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      buf.write(_letters[s[i]] ?? s[i]);
    }
    var out = buf.toString();
    if (out.isEmpty) return s;
    return out[0].toUpperCase() + out.substring(1);
  }

  static const _names = <String, String>{
    'بن': 'bin',
    'ابن': 'bin',
    'إبن': 'bin',
    'آل': 'Al',
    'عبد': 'Abdul',
    'محمد': 'Muhammad',
    'محمّد': 'Muhammad',
    'أحمد': 'Ahmad',
    'احمد': 'Ahmad',
    'عبدالله': 'Abdullah',
    'عبد الله': 'Abdullah',
    'عبدالرحمن': 'Abdulrahman',
    'عبدالعزيز': 'Abdulaziz',
    'خالد': 'Khalid',
    'سعد': 'Saad',
    'فهد': 'Fahd',
    'سلطان': 'Sultan',
    'فيصل': 'Faisal',
    'عمر': 'Omar',
    'علي': 'Ali',
    'يوسف': 'Yusuf',
    'إبراهيم': 'Ibrahim',
    'ابراهيم': 'Ibrahim',
    'حسن': 'Hassan',
    'حسين': 'Hussein',
    'صالح': 'Saleh',
    'ناصر': 'Nasser',
    'تركي': 'Turki',
    'ماجد': 'Majed',
    'بندر': 'Bandar',
    'فاطمة': 'Fatimah',
    'نورة': 'Noura',
    'سارة': 'Sarah',
    'مريم': 'Maryam',
    'هند': 'Hind',
    'لينا': 'Lina',
    'منى': 'Mona',
    'عائشة': 'Aisha',
  };

  static const _letters = <String, String>{
    'ا': 'a',
    'أ': 'a',
    'إ': 'i',
    'آ': 'a',
    'ء': '',
    'ؤ': 'u',
    'ئ': 'i',
    'ب': 'b',
    'ت': 't',
    'ث': 'th',
    'ج': 'j',
    'ح': 'h',
    'خ': 'kh',
    'د': 'd',
    'ذ': 'dh',
    'ر': 'r',
    'ز': 'z',
    'س': 's',
    'ش': 'sh',
    'ص': 's',
    'ض': 'd',
    'ط': 't',
    'ظ': 'z',
    'ع': 'a',
    'غ': 'gh',
    'ف': 'f',
    'ق': 'q',
    'ك': 'k',
    'ل': 'l',
    'م': 'm',
    'ن': 'n',
    'ه': 'h',
    'ة': 'ah',
    'و': 'w',
    'ى': 'a',
    'ي': 'y',
    'ً': '',
    'ٌ': '',
    'ٍ': '',
    'َ': 'a',
    'ُ': 'u',
    'ِ': 'i',
    'ّ': '',
    'ْ': '',
  };
}
