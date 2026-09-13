library property_video_sheet;

import 'package:flutter/material.dart';

import '../core/listing/listing_media_urls.dart';
import 'app_page_close_button.dart';
import 'inline_property_video.dart';
import 'shorts_tour_pane.dart';

/// تشغيل فيديو العقار داخل طبقة فوق الصفحة (ويب + تطبيق) مع إغلاق X.
abstract class PropertyVideoSheet {
  static Future<void> open(
    BuildContext context, {
    required bool isAr,
    required String title,
    required String videoUrl,
  }) {
    return openPropertyVideoSheetImpl(
      context,
      isAr: isAr,
      title: title,
      videoUrl: videoUrl,
    );
  }
}

Future<void> openPropertyVideoSheetImpl(
  BuildContext context, {
  required bool isAr,
  required String title,
  required String videoUrl,
}) async {
  final uri = Uri.tryParse(videoUrl.trim());
  if (uri == null ||
      !(uri.isScheme('http') || uri.isScheme('https')) ||
      uri.host.isEmpty) {
    return;
  }

  final embed = ListingMediaUrls.looksLikeEmbeddableVideoHost(videoUrl);
  await showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: isAr ? 'إغلاق' : 'Close',
    barrierColor: Colors.black.withValues(alpha: 0.78),
    useRootNavigator: true,
    pageBuilder: (ctx, _, __) {
      return Material(
        color: Colors.black,
        child: SafeArea(
          child: Stack(
            children: [
              Positioned.fill(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 52, 12, 12),
                  child: embed
                      ? ShortsTourPane(
                          url: videoUrl.trim(),
                          isAr: isAr,
                          active: true,
                        )
                      : Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(
                              maxWidth: 960,
                              maxHeight: 560,
                            ),
                            child: AspectRatio(
                              aspectRatio: 16 / 9,
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(16),
                                child: InlinePropertyVideoPlayer(
                                  videoUrl: videoUrl.trim(),
                                  isAr: isAr,
                                ),
                              ),
                            ),
                          ),
                        ),
                ),
              ),
              PositionedDirectional(
                top: 4,
                start: 4,
                child: AppPageCloseButton(
                  isArabic: isAr,
                  color: Colors.white,
                  tooltip: isAr ? 'إغلاق' : 'Close',
                  onPressed: () => Navigator.of(ctx).pop(),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}
