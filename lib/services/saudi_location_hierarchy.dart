import '../core/geo/saudi_official_admin.dart';
import '../models/saudi_location.dart';

/// هرم منطقة → محافظة → مدينة من [SaudiLocation] (نفس منطق إضافة الإعلان).
class SaudiLocationHierarchy {
  SaudiLocationHierarchy({
    required this.regionOptions,
    required this.governoratesByRegion,
    required this.citiesByGovernorate,
  });

  final List<String> regionOptions;
  final Map<String, List<String>> governoratesByRegion;
  final Map<String, List<String>> citiesByGovernorate;

  /// فوق هذا العدد نستخدم [SearchableSelectField] بدل القائمة المنسدلة فقط.
  static const int kLocSearchThreshold = 6;

  static SaudiLocationHierarchy build(
    List<SaudiLocation> all, {
    required bool isAr,
  }) {
    final regions = <String>{};
    final governoratesByRegion = <String, Set<String>>{};
    final citiesByGovernorate = <String, Set<String>>{};

    for (final r in SaudiOfficialAdmin.officialRegionNames(isAr: isAr)) {
      regions.add(r);
      governoratesByRegion.putIfAbsent(r, () => <String>{}).addAll(
            SaudiOfficialAdmin.governorates(region: r, isAr: isAr),
          );
    }

    for (final item in all) {
      final region = SaudiOfficialAdmin.canonicalRegionName(
            isAr ? item.regionAr : item.regionEn,
            isAr: isAr,
          ) ??
          '';
      final governorate = isAr
          ? (item.governorateAr?.trim() ?? '')
          : (item.governorateEn?.trim() ?? '');
      final city = isAr ? item.cityAr.trim() : item.cityEn.trim();

      if (region.isEmpty || city.isEmpty) continue;

      regions.add(region);
      final officialGovs = SaudiOfficialAdmin.governorates(
        region: region,
        isAr: isAr,
      );
      if (officialGovs.isNotEmpty) {
        governoratesByRegion.putIfAbsent(region, () => <String>{}).addAll(officialGovs);
      }

      var gov = governorate;
      if (gov.isEmpty ||
          !SaudiOfficialAdmin.isOfficialGovernorate(
            region: region,
            governorate: gov,
          )) {
        if (SaudiOfficialAdmin.isOfficialGovernorate(
          region: region,
          governorate: city,
        )) {
          gov = city;
        } else {
          gov = '';
        }
      }
      if (gov.isNotEmpty) {
        governoratesByRegion.putIfAbsent(region, () => <String>{}).add(gov);
        citiesByGovernorate.putIfAbsent(gov, () => <String>{}).add(city);
      }
    }

    final sortedRegions = regions.toList()..sort();
    final sortedGovernoratesByRegion = <String, List<String>>{};
    for (final entry in governoratesByRegion.entries) {
      sortedGovernoratesByRegion[entry.key] = entry.value.toList()..sort();
    }
    final sortedCitiesByGovernorate = <String, List<String>>{};
    for (final entry in citiesByGovernorate.entries) {
      sortedCitiesByGovernorate[entry.key] = entry.value.toList()..sort();
    }

    return SaudiLocationHierarchy(
      regionOptions: sortedRegions,
      governoratesByRegion: sortedGovernoratesByRegion,
      citiesByGovernorate: sortedCitiesByGovernorate,
    );
  }
}
