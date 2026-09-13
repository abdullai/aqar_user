import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class ShortsTourPaneBody extends StatelessWidget {
  const ShortsTourPaneBody({super.key, required this.url, required this.isAr});

  final String url;
  final bool isAr;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: FilledButton.tonal(
        onPressed: () {
          final u = Uri.tryParse(url);
          if (u != null) {
            launchUrl(u, mode: LaunchMode.externalApplication);
          }
        },
        child: Text(isAr ? 'فتح الجولة' : 'Open tour'),
      ),
    );
  }
}
