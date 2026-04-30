class SaudiLocation {
  final String cityAr;
  final String cityEn;
  final String regionAr;
  final String regionEn;
  final String? governorateAr;  // إضافة حقل المحافظة بالعربية
  final String? governorateEn;  // إضافة حقل المحافظة بالإنجليزية
  final double lat;
  final double lng;

  const SaudiLocation({
    required this.cityAr,
    required this.cityEn,
    required this.regionAr,
    required this.regionEn,
    this.governorateAr,
    this.governorateEn,
    required this.lat,
    required this.lng,
  });

  factory SaudiLocation.fromJson(Map<String, dynamic> json) {
    return SaudiLocation(
      cityAr: (json['city_ar'] ?? '').toString().trim(),
      cityEn: (json['city_en'] ?? '').toString().trim(),
      regionAr: (json['region_ar'] ?? '').toString().trim(),
      regionEn: (json['region_en'] ?? '').toString().trim(),
      governorateAr: (json['governorate_ar'] as String?)?.trim(),
      governorateEn: (json['governorate_en'] as String?)?.trim(),
      lat: (json['lat'] as num?)?.toDouble() ?? 0.0,
      lng: (json['lng'] as num?)?.toDouble() ?? 0.0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'city_ar': cityAr,
      'city_en': cityEn,
      'region_ar': regionAr,
      'region_en': regionEn,
      'governorate_ar': governorateAr,
      'governorate_en': governorateEn,
      'lat': lat,
      'lng': lng,
    };
  }
}