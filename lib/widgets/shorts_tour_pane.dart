import 'package:flutter/material.dart';

import '../core/shorts/shorts_url_guard.dart';
import 'shorts_tour_pane_stub.dart'
    if (dart.library.io) 'shorts_tour_pane_io.dart'
    if (dart.library.html) 'shorts_tour_pane_web.dart' as impl;

/// جولة افتراضية داخل شريحة التصفح السريع.
class ShortsTourPane extends StatelessWidget {
  const ShortsTourPane({
    super.key,
    required this.url,
    required this.isAr,
    required this.active,
  });

  final String url;
  final bool isAr;
  final bool active;

  @override
  Widget build(BuildContext context) {
    if (!active) {
      return ColoredBox(
        color: Colors.black12,
        child: Center(
          child: Text(
            isAr ? 'جولة افتراضية' : 'Virtual tour',
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
        ),
      );
    }
    if (!ShortsUrlGuard.isSafeHttps(url)) {
      return Center(
        child: Text(
          isAr ? 'رابط الجولة غير آمن' : 'Tour link is not safe',
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
      );
    }
    return impl.ShortsTourPaneBody(url: url, isAr: isAr);
  }
}
