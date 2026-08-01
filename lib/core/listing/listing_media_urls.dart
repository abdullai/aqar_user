import 'package:supabase_flutter/supabase_flutter.dart';



import '../branding/app_branding.dart';

import '../share/app_listing_links.dart';

import '../../models/market_property_request_row.dart';

import '../../models/property.dart';



/// روابط موحّدة لصور/معاينات الإعلان والطلب (بطاقات، خريطة، مشاركة).

abstract final class ListingMediaUrls {

  /// أصل ثابت داخل التطبيق عند غياب صورة شبكة (ذكي: ويب→logo، تطبيق→splash).

  static String get defaultThumbAsset => AppBranding.listingPlaceholderAsset;



  /// هل المسار في التخزين يمثل غلافاً ذكياً (لا ملف حقيقي)؟

  static bool isSmartDefaultCoverPath(String? path) {

    final p = (path ?? '').trim();

    if (p.isEmpty) return true;

    return p == AppBranding.smartDefaultCoverStorageSentinel;

  }



  /// إعلان يستخدم الغلاف الذكي — من العلم في قاعدة البيانات أو غياب صور المستخدم.

  static bool propertyUsesSmartDefaultCover(Property p) =>

      p.defaultCoverUsed || p.images.isEmpty;



  /// طلب سوق يستخدم الغلاف الذكي.

  static bool marketRequestUsesSmartDefaultCover(MarketPropertyRequestRow r) =>

      r.defaultCoverUsed ||

      isSmartDefaultCoverPath(r.coverImageStoragePath);



  /// مسارات الصور للبطاقات — فارغة عند الغلاف الذكي لإجبار [BrandingLogoImage].

  static List<String> propertyCardImagePaths(Property p) {

    if (propertyUsesSmartDefaultCover(p)) return const [];

    return p.images;

  }



  /// معاينة مشاركة غنية على الويب (OG) — غلاف المؤسسة للغلاف الذكي.

  static String fallbackSharePreviewImageUrl() =>

      AppBranding.webEstablishmentCoverShareUrl();



  static String? _storagePublicUrl(SupabaseClient sb, String pathOrUrl) {

    final s = pathOrUrl.trim();

    if (s.isEmpty || isSmartDefaultCoverPath(s)) return null;

    if (s.startsWith('http://') || s.startsWith('https://')) return s;

    try {

      return sb.storage.from('property-images').getPublicUrl(s);

    } catch (_) {

      return null;

    }

  }



  /// أوّل صورة إعلان كرابط `https` — `null` للغلاف الذكي (عرض محلي ذكي).

  static String? propertyImageNetworkUrl(Property p, SupabaseClient sb) {

    if (propertyUsesSmartDefaultCover(p)) return null;

    for (final raw in p.images) {

      final u = _storagePublicUrl(sb, raw);

      if (u != null && u.isNotEmpty) return u;

    }

    return null;

  }



  /// غلاف طلب السوق — `null` للغلاف الذكي.

  static String? marketRequestCoverNetworkUrl(

    MarketPropertyRequestRow r,

    SupabaseClient sb,

  ) {

    if (marketRequestUsesSmartDefaultCover(r)) return null;

    final path = (r.coverImageStoragePath ?? '').trim();

    if (path.isEmpty) return null;

    return _storagePublicUrl(sb, path);

  }



  /// للمشاركة الغنية: صورة المستخدم أو أيقونة المؤسسة على الويب.

  static String propertySharePreviewHttpUrl(Property p, SupabaseClient sb) =>

      propertyImageNetworkUrl(p, sb) ?? fallbackSharePreviewImageUrl();



  static String marketRequestSharePreviewHttpUrl(

    MarketPropertyRequestRow r,

    SupabaseClient sb,

  ) =>

      marketRequestCoverNetworkUrl(r, sb) ?? fallbackSharePreviewImageUrl();

}

