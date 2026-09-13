import 'dart:html' as html;
import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';

class ShortsTourPaneBody extends StatelessWidget {
  const ShortsTourPaneBody({super.key, required this.url, required this.isAr});

  final String url;
  final bool isAr;

  @override
  Widget build(BuildContext context) {
    final viewId = 'shorts-tour-${url.hashCode}';
    ui_web.platformViewRegistry.registerViewFactory(viewId, (int _) {
      final el = html.IFrameElement()
        ..src = url
        ..style.border = 'none'
        ..style.width = '100%'
        ..style.height = '100%'
        ..allowFullscreen = true
        ..referrerPolicy = 'no-referrer'
        ..setAttribute(
          'sandbox',
          'allow-scripts allow-same-origin allow-fullscreen',
        );
      return el;
    });
    return HtmlElementView(viewType: viewId);
  }
}
