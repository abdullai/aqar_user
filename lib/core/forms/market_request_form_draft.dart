/// تسلسل/استرجاع مسودة «طلب عقاري» — بدون صورة الغلاف (تُعاد اختيارها).
class MarketRequestFormDraft {
  MarketRequestFormDraft._();

  static Map<String, dynamic> serialize({
    required int step,
    required String title,
    required String desc,
    required String budgetMin,
    required String budgetMax,
    required String areaMin,
    required String publicName,
    required String districts,
    required bool purchase,
    required String requestPriority,
    required String typeKey,
    required String typeGroupId,
    required String cityKey,
    required String? selectedRegion,
    required String? selectedGovernorate,
    required double? selectedLat,
    required double? selectedLng,
    required String rentTerm,
    required int? bedrooms,
    required int? bathrooms,
    required Map<String, bool> amenityToggles,
    required bool preferNew,
  }) {
    return {
      'step': step,
      'title': title,
      'desc': desc,
      'budget_min': budgetMin,
      'budget_max': budgetMax,
      'area_min': areaMin,
      'public_name': publicName,
      'districts': districts,
      'purchase': purchase,
      'request_priority': requestPriority,
      'type_key': typeKey,
      'type_group_id': typeGroupId,
      'city_key': cityKey,
      'selected_region': selectedRegion,
      'selected_governorate': selectedGovernorate,
      'selected_lat': selectedLat,
      'selected_lng': selectedLng,
      'rent_term': rentTerm,
      'bedrooms': bedrooms,
      'bathrooms': bathrooms,
      'amenities': amenityToggles,
      'prefer_new': preferNew,
    };
  }
}
