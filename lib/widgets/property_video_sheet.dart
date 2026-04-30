// lib/widgets/property_video_sheet.dart
library property_video_sheet;

import 'package:flutter/material.dart';

// ✅ على الويب: نستخدم Stub (بدون chewie/video_player)
// ✅ على الموبايل: نستخدم التنفيذ الحقيقي
import 'property_video_sheet_stub.dart'
    if (dart.library.io) 'property_video_sheet_io.dart';

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