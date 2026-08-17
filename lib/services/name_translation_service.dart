import 'package:flutter/foundation.dart';
import 'package:translator/translator.dart';

/// ترجمة الاسم العربي إلى إنجليزي عند التسجيل (بدون مفتاح API).
/// قد تفشل على الويب بسبب CORS أو الشبكة — عندها تُرجع `null`.
class NameTranslationService {
  static Future<String?> arabicFullNameToEnglish(String fullAr) async {
    final s = fullAr.trim();
    if (s.isEmpty) return null;
    try {
      final translated = await GoogleTranslator()
          .translate(s, from: 'ar', to: 'en')
          .timeout(const Duration(seconds: 18));
      final out = translated.text.trim();
      if (out.isEmpty) return null;
      return out;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('NameTranslationService: $e');
      }
      return null;
    }
  }
}
