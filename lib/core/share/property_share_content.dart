import '../branding/app_branding.dart';
import '../listing/property_listing_display.dart';
import '../utils/app_money.dart';
import '../../models/property.dart';

abstract final class PropertyShareContent {
  static String build({
    required Property property,
    required bool isArabic,
    required String listingUrl,
    required Iterable<String> imageUrls,
    required Iterable<String> videoUrls,
    required Iterable<String> tourUrls,
    required bool hasInAppTour,
    required String description,
    Map<String, String> mediaAttributions = const {},
  }) {
    final title = property.title.trim();
    final type = PropertyListingDisplay.typeLabelForProperty(
      property,
      isArabic,
    );
    final purpose = PropertyListingDisplay.purposeBitShort(
      property,
      isArabic,
    ).trim();
    final address = PropertyListingDisplay.addressLine(
      property,
      isAr: isArabic,
    );
    final amount = property.isAuction
        ? (property.currentBid ?? property.price)
        : property.displayTotalPrice;
    final currency =
        property.currency.trim().isEmpty ? 'SAR' : property.currency.trim();
    final lines = <String>[
      '🏡 $title',
      if (type.isNotEmpty || purpose.isNotEmpty)
        '🏠 ${[type, purpose].where((value) => value.isNotEmpty).join(' · ')}',
      if (address.isNotEmpty) '📍 $address',
      '💰 ${isArabic ? 'السعر' : 'Price'}: ${AppMoney.formatWithCurrencyCode(
        amount,
        isAr: isArabic,
        currencyCode: currency,
        maxFractionDigits: 0,
      )}',
      '📐 ${isArabic ? 'المساحة' : 'Area'}: ${AppMoney.formatNumber(
        property.area,
        isAr: isArabic,
        maxFractionDigits: 0,
      )} ${isArabic ? 'م²' : 'm²'}',
      if (property.bedrooms != null)
        '🛏️ ${isArabic ? 'غرف النوم' : 'Bedrooms'}: ${property.bedrooms}',
      if (property.bathrooms != null)
        '🛁 ${isArabic ? 'دورات المياه' : 'Bathrooms'}: ${property.bathrooms}',
    ];

    final cleanDescription = description.trim();
    if (cleanDescription.isNotEmpty) {
      final compactDescription = cleanDescription.length <= 500
          ? cleanDescription
          : '${cleanDescription.substring(0, 497).trimRight()}...';
      lines
        ..add('')
        ..add('${isArabic ? 'نبذة' : 'About'}: $compactDescription');
    }

    final seen = <String>{};
    void addMedia(String label, Iterable<String> candidates) {
      for (final raw in candidates) {
        final url = raw.trim();
        final uri = Uri.tryParse(url);
        if (url.isEmpty ||
            uri == null ||
            uri.host.isEmpty ||
            (!uri.isScheme('http') && !uri.isScheme('https'))) {
          continue;
        }
        final key = '${uri.scheme.toLowerCase()}://${uri.host.toLowerCase()}'
            '${uri.path}';
        if (!seen.add(key)) continue;
        final attribution = mediaAttributions[url]?.trim();
        final credit = attribution == null || attribution.isEmpty
            ? ''
            : (isArabic ? ' — تصوير $attribution' : ' — Photo by $attribution');
        lines.add('$label$credit: $url');
      }
    }

    addMedia(isArabic ? '🖼️ صورة' : '🖼️ Photo', imageUrls);
    addMedia(isArabic ? '🎥 فيديو' : '🎥 Video', videoUrls);
    addMedia(isArabic ? '🧭 جولة' : '🧭 Tour', tourUrls);
    if (hasInAppTour) {
      lines.add(
        isArabic
            ? '✨ جولة تفاعلية متاحة عبر رابط الإعلان'
            : '✨ Interactive tour available through the listing link',
      );
    }

    final url = listingUrl.trim();
    if (url.isNotEmpty) {
      lines
        ..add('')
        ..add('${isArabic ? '🔗 رابط الإعلان' : '🔗 View listing'}: $url');
    }
    lines
      ..add('')
      ..add('— ${AppBranding.shareBrandLine(isAr: isArabic)}');
    return lines.join('\n');
  }
}
