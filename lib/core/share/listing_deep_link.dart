import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../routes.dart';
import '../../screens/listing_loader_page.dart';
import 'app_listing_links.dart';

/// فتح روابط عميقة: تحقق من عقد (?contract=&verify=1) ثم إعلان (?listing=).
/// الويب: [Uri.base] — الموبايل: [SharedPreferences] بعد [AppLinks] في [main.dart].
/// إن وُجد الاستعلامان معاً في نفس الرابط، تُعالَج **العقد** أولاً فقط في هذه الجلسة.
abstract final class ListingDeepLink {
  static bool _contractHandled = false;
  static bool _listingHandled = false;

  static Future<void> openIfQueued(
    BuildContext context, {
    required String lang,
  }) async {
    if (!context.mounted) return;

    // ----- عقد (ويب: استعلام الرابط | أصلي: مفتاح معلّق من App Links) -----
    if (!_contractHandled) {
      String? cid;
      String? vtFromWeb;
      if (kIsWeb) {
        cid = AppListingLinks.contractIdFromVerifyUri(Uri.base);
        vtFromWeb = AppListingLinks.verifyTokenFromVerifyUri(Uri.base);
      }
      if (cid == null || cid.isEmpty) {
        try {
          final p = await SharedPreferences.getInstance();
          final v = (p.getString(AppListingLinks.pendingContractVerifyPrefKey) ??
                  '')
              .trim();
          if (v.isNotEmpty) {
            cid = v;
            await p.remove(AppListingLinks.pendingContractVerifyPrefKey);
          }
        } catch (_) {}
      }
      if (cid != null && cid.isNotEmpty) {
        _contractHandled = true;
        String? vt = vtFromWeb;
        if (vt == null || vt.isEmpty) {
          try {
            final p = await SharedPreferences.getInstance();
            vt = (p.getString(AppListingLinks.pendingContractVerifyTokenPrefKey) ??
                    '')
                .trim();
            if (vt.isNotEmpty) {
              await p.remove(AppListingLinks.pendingContractVerifyTokenPrefKey);
            }
          } catch (_) {}
        }
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!context.mounted) return;
          Navigator.of(context).pushNamed<void>(
            AppRoutes.contractVerify,
            arguments: <String, String>{
              'contractId': cid!,
              'lang': lang,
              if (vt != null && vt.isNotEmpty) 'verifyToken': vt,
            },
          );
        });
        return;
      }
    }

    // ----- إعلان -----
    if (_listingHandled) return;

    String? id;
    try {
      final p = await SharedPreferences.getInstance();
      final v =
          (p.getString(AppListingLinks.pendingListingPrefKey) ?? '').trim();
      if (v.isNotEmpty) {
        id = v;
        await p.remove(AppListingLinks.pendingListingPrefKey);
      }
    } catch (_) {}

    if ((id == null || id.isEmpty) && kIsWeb) {
      id = Uri.base.queryParameters['listing']?.trim();
    }

    if (id == null || id.isEmpty) return;
    _listingHandled = true;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!context.mounted) return;
      Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => ListingLoaderPage(propertyId: id!, lang: lang),
        ),
      );
    });
  }
}
