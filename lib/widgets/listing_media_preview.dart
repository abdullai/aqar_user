import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/listing/in_app_tour.dart';
import '../core/listing/listing_media_hydration.dart';
import '../core/listing/listing_media_urls.dart';
import 'in_app_tour_viewer.dart';
import 'listing_media_gallery.dart';
import 'property_video_sheet.dart';

class ListingMediaPreview extends StatelessWidget {
  const ListingMediaPreview({
    super.key,
    required this.mediaRow,
    required this.isAr,
    this.mediaOwnerKey,
    this.aspectRatio = 16 / 9,
    this.maxHeight = 280,
    this.borderRadius = 14,
    this.emptyChild,
  });

  final Map<String, dynamic> mediaRow;
  final bool isAr;
  final String? mediaOwnerKey;
  final double aspectRatio;
  final double maxHeight;
  final double borderRadius;
  final Widget? emptyChild;

  @override
  Widget build(BuildContext context) {
    final sb = Supabase.instance.client;
    final row = ListingMediaHydration.resolveRow(property: mediaRow);
    final imagePaths =
        ListingMediaUrls.imagePathsFromPropertyImages(row['property_images']);
    final images = ListingMediaUrls.publicUrls(sb, imagePaths);
    final videoUrl = ListingMediaUrls.videoPlayableUrl(sb, row['video_url']);
    final rawTour = ListingMediaUrls.virtualTourFromPayload(row);
    final tourUrl = ListingMediaUrls.storagePublicUrl(sb, rawTour);
    final inAppTour = ListingMediaUrls.inAppTourFromPayload(row) ??
        _firstPhotographerTour(row['listing_guidance']);
    final title = (row['title'] ?? '').toString().trim();

    return ListingMediaGallery(
      imageUrls: images,
      videoUrl: videoUrl,
      tourUrl: tourUrl,
      isAr: isAr,
      mediaOwnerKey: mediaOwnerKey ?? (row['id'] ?? '').toString(),
      aspectRatio: aspectRatio,
      maxHeight: maxHeight,
      borderRadius: borderRadius,
      preferVideoFirst: (row['listing_guidance'] is Map
              ? (row['listing_guidance']['cover_primary'] ?? '')
                  .toString()
                  .toLowerCase()
              : '') ==
          'video',
      onOpenVideo: videoUrl == null
          ? null
          : () => unawaited(
                PropertyVideoSheet.open(
                  context,
                  isAr: isAr,
                  title: title,
                  videoUrl: videoUrl,
                ),
              ),
      onOpenTour: tourUrl == null && inAppTour == null
          ? null
          : () {
              if (inAppTour != null) {
                unawaited(
                  openInAppTourViewer(
                    context: context,
                    tour: inAppTour,
                    isAr: isAr,
                  ),
                );
              } else {
                unawaited(
                  PropertyVideoSheet.open(
                    context,
                    isAr: isAr,
                    title: title,
                    videoUrl: tourUrl!,
                  ),
                );
              }
            },
      emptyChild: emptyChild,
    );
  }

  InAppTour? _firstPhotographerTour(dynamic rawGuidance) {
    final guidance = ListingMediaHydration.guidanceMap(rawGuidance);
    final rawTours = guidance?['photographer_tours'];
    if (rawTours is! List) return null;
    for (final rawTour in rawTours) {
      final tour = InAppTour.fromRaw(rawTour);
      if (tour?.isNotEmpty == true) return tour;
    }
    return null;
  }
}
