import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'app_logo_loading.dart';

/// عرض صفحة جهة حكومية داخل التطبيق فقط — دون `launchUrl` أو متصفح خارجي.
class GovernmentInAppWebViewPage extends StatefulWidget {
  final Uri uri;
  final String title;

  const GovernmentInAppWebViewPage({
    super.key,
    required this.uri,
    required this.title,
  });

  @override
  State<GovernmentInAppWebViewPage> createState() =>
      _GovernmentInAppWebViewPageState();
}

class _GovernmentInAppWebViewPageState extends State<GovernmentInAppWebViewPage> {
  late final WebViewController _controller;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.white)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) {
            if (mounted) setState(() => _loading = true);
          },
          onPageFinished: (_) {
            if (mounted) setState(() => _loading = false);
          },
          onWebResourceError: (_) {
            if (mounted) setState(() => _loading = false);
          },
        ),
      )
      ..loadRequest(widget.uri);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.pop(context),
          tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
        ),
      ),
      body: Stack(
        children: [
          WebViewWidget(controller: _controller),
          if (_loading)
            ColoredBox(
              color: Colors.white.withOpacity(0.92),
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const AppLogoLoading(),
                      const SizedBox(height: 20),
                      Text(
                        Localizations.localeOf(context).languageCode == 'ar'
                            ? 'الرجاء الانتظار… جاري التحميل من الجهة المعنية.'
                            : 'Please wait… Loading from the authority.',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
