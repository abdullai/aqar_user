import 'package:share_plus/share_plus.dart';

import '../listing/listing_media_urls.dart';

Future<void> shareListingRich({
  required String text,
  String? imageHttpUrl,
  String? subject,
}) async {
  final primary = imageHttpUrl?.trim();
  final fallback = ListingMediaUrls.fallbackSharePreviewImageUrl();
  final imgLine =
      (primary != null && primary.isNotEmpty) ? primary : fallback;
  final full = '$text\n$imgLine';
  await Share.share(
    full,
    subject: subject,
  );
}
