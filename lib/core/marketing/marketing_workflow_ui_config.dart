/// إعدادات واجهة مسار التسويق في «صفحتي».
///
/// عطّل توقيع العقود مؤقتاً: الأزرار الذكية تنتقل من قبول العرض مباشرةً
/// إلى الدردشة + إصدار/نشر التصريح دون إنشاء/إرسال/توقيع عقد أو PDF.
class MarketingWorkflowUiConfig {
  MarketingWorkflowUiConfig._();

  /// `false` = إخفاء مسار توقيع العقود من الواجهة.
  static const bool contractsSigningEnabled = false;
}
