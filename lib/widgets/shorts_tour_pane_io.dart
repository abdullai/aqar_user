import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

class ShortsTourPaneBody extends StatefulWidget {
  const ShortsTourPaneBody({super.key, required this.url, required this.isAr});

  final String url;
  final bool isAr;

  @override
  State<ShortsTourPaneBody> createState() => _ShortsTourPaneBodyState();
}

class _ShortsTourPaneBodyState extends State<ShortsTourPaneBody> {
  WebViewController? _c;
  bool _fail = false;

  @override
  void initState() {
    super.initState();
    final uri = Uri.tryParse(widget.url.trim());
    if (uri == null || !uri.isScheme('https')) {
      _fail = true;
      return;
    }
    final c = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0x00000000))
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (req) {
            final u = Uri.tryParse(req.url);
            if (u == null || u.scheme != 'https') {
              return NavigationDecision.prevent;
            }
            final h = u.host.toLowerCase();
            if (h == 'localhost' || h == '127.0.0.1' || h.endsWith('.local')) {
              return NavigationDecision.prevent;
            }
            if (u.userInfo.isNotEmpty) return NavigationDecision.prevent;
            return NavigationDecision.navigate;
          },
        ),
      )
      ..loadRequest(uri);
    _c = c;
  }

  @override
  Widget build(BuildContext context) {
    final c = _c;
    if (_fail || c == null) {
      return Center(
        child: Text(
          widget.isAr ? 'تعذر فتح الجولة' : 'Tour unavailable',
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
      );
    }
    return WebViewWidget(controller: c);
  }
}
