import 'compound_display_name.dart';

/// تنسيق اسم العرض لبطاقات الترحيب: «شريكنا العقاري» + الاسم بعد تطبيع المركّبات.
String partnerRealtorLine({
  required bool isArabic,
  required String rawFullName,
}) {
  const brandAr = 'شريكنا العقاري';
  const brandEn = 'Our realtor partner';

  final normalized = CompoundDisplayName.normalize(rawFullName);
  if (normalized.isEmpty) {
    return isArabic ? brandAr : brandEn;
  }
  return isArabic ? '$brandAr $normalized' : '$brandEn $normalized';
}
