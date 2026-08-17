import 'package:flutter/material.dart';

import 'inline_property_video_stub.dart'
    if (dart.library.io) 'inline_property_video_io.dart';

/// معاينة فيديو الغلاف مع أدوات تشغيل (Chewie على iOS/Android/Desktop؛ ورقة على الويب).
class InlinePropertyVideoPlayer extends StatelessWidget {
  final String videoUrl;
  final bool isAr;

  const InlinePropertyVideoPlayer({
    super.key,
    required this.videoUrl,
    required this.isAr,
  });

  @override
  Widget build(BuildContext context) {
    return InlinePropertyVideoPlayerImpl(
      videoUrl: videoUrl,
      isAr: isAr,
    );
  }
}
