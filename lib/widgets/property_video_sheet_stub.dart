import 'package:flutter/material.dart';

import 'property_video_sheet.dart' as impl;

Future<void> openPropertyVideoSheetImpl(
  BuildContext context, {
  required bool isAr,
  required String title,
  required String videoUrl,
}) {
  return impl.openPropertyVideoSheetImpl(
    context,
    isAr: isAr,
    title: title,
    videoUrl: videoUrl,
  );
}
