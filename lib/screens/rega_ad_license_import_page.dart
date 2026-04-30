import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../widgets/app_logo_loading.dart';

/// استيراد بيانات **ترخيص الإعلان العقاري** من صفحة تفاصيل الإعلان في بوابة الهيئة
/// (`/public/OfficesBroker/ElanDetails/{uuid}`) عبر WebView + تحليل النص / `__NEXT_DATA__`.
class RegaAdLicenseImportPage extends StatefulWidget {
  final bool isAr;

  const RegaAdLicenseImportPage({
    super.key,
    required this.isAr,
  });

  static final RegExp _uuidRe = RegExp(
    r'[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}',
    caseSensitive: false,
  );

  /// يقبل الرابط الكامل أو أي نص يحوي UUID صفحة التفاصيل.
  static Uri? parseElanDetailsUri(String raw) {
    final s = raw.trim();
    if (s.isEmpty) return null;
    final m = _uuidRe.firstMatch(s);
    if (m == null) return null;
    return Uri.parse(
      'https://eservicesredp.rega.gov.sa/public/OfficesBroker/ElanDetails/${m.group(0)}',
    );
  }

  static String? _firstNonEmptyLine(String s) {
    for (final line in s.split(RegExp(r'[\r\n]+'))) {
      final t = line.trim();
      if (t.isNotEmpty) return t;
    }
    return null;
  }

  static String? _valueAfterLabel(String body, String label) {
    final i = body.indexOf(label);
    if (i < 0) return null;
    var tail = body.substring(i + label.length).trimLeft();
    if (tail.startsWith(':') || tail.startsWith('：')) {
      tail = tail.substring(1).trimLeft();
    }
    return _firstNonEmptyLine(tail);
  }

  /// تحليل نص منسوخ من صفحة الهيئة (أو `innerText` من WebView).
  static Map<String, dynamic> parsePayloadFromPastedPageText(String raw) {
    final body = raw
        .replaceAll('\u200f', '')
        .replaceAll('\u200e', '')
        .replaceAll('\ufeff', '');

    final out = <String, dynamic>{};

    void put(String key, String? v) {
      if (v == null) return;
      final t = v.trim();
      if (t.isEmpty) return;
      final cur = out[key]?.toString().trim() ?? '';
      if (cur.isNotEmpty) return;
      out[key] = t;
    }

    put('rega_ad_license_number', _valueAfterLabel(body, 'رقم الترخيص'));
    put('rega_issue_date', _valueAfterLabel(body, 'تاريخ إصدار الترخيص'));
    put(
      'rega_expiry_date',
      _valueAfterLabel(body, 'تاريخ انتهاء الترخيص') ??
          _valueAfterLabel(body, 'تاريخ الانتهاء'),
    );
    put('marketer_entity_display_name', _valueAfterLabel(body, 'اسم المعلن'));
    put(
      'rega_advertiser_unified_number',
      _valueAfterLabel(body, 'الرقم الموحد لمنشأة المعلن'),
    );
    put(
      'fal_broker_license_number',
      _valueAfterLabel(
            body,
            'رقم رخصة فال للوساطة والتسويق العقاري',
          ) ??
          _valueAfterLabel(body, 'رقم رخصة فال'),
    );
    put(
      'rega_ad_responsible_name',
      _valueAfterLabel(body, 'الموظف المسؤول عن الإعلان'),
    );
    put(
      'rega_ad_responsible_mobile',
      _valueAfterLabel(body, 'رقم جوال مسؤول الإعلان'),
    );
    put('rega_ad_purpose', _valueAfterLabel(body, 'غرض الإعلان'));
    put(
      'rega_deed_doc_type',
      _valueAfterLabel(body, 'نوع وثيقة الملكية/المنفعة'),
    );
    put(
      'deed_or_benefit_doc_number',
      _valueAfterLabel(body, 'رقم وثيقة الملكية/المنفعة'),
    );
    put('rega_unit_price', _valueAfterLabel(body, 'سعر الوحدة'));
    put(
      'rega_land_use',
      _valueAfterLabel(body, 'إستخدام الأرض') ??
          _valueAfterLabel(body, 'استخدام الأرض'),
    );
    put('rega_property_type_ar', _valueAfterLabel(body, 'نوع العقار'));
    put('rega_area_sqm', _valueAfterLabel(body, 'مساحة العقار'));
    put('rega_street_width', _valueAfterLabel(body, 'عرض الشارع'));
    put('rega_plan_number', _valueAfterLabel(body, 'رقم المخطط'));
    put('rega_rooms', _valueAfterLabel(body, 'عدد الغرف'));
    put('rega_facade', _valueAfterLabel(body, 'واجهة العقار'));
    put('rega_region', _valueAfterLabel(body, 'المنطقة'));
    put('rega_city', _valueAfterLabel(body, 'المدينة'));
    put('rega_district', _valueAfterLabel(body, 'الحي'));
    put('rega_street', _valueAfterLabel(body, 'الشارع'));

    // إنجليزي (إن وُجد في لقطة مختلطة)
    put('rega_ad_license_number', _valueAfterLabel(body, 'License Number'));
    put('rega_issue_date', _valueAfterLabel(body, 'License Issue Date'));
    put('rega_expiry_date', _valueAfterLabel(body, 'License Expiry Date'));

    return out;
  }

  static Map<String, dynamic> _parseNextDataLoose(String raw) {
    final out = <String, dynamic>{};
    if (raw.trim().isEmpty) return out;

    String? q(String pattern) {
      final m = RegExp(pattern, caseSensitive: false).firstMatch(raw);
      return m?.group(1)?.trim();
    }

    void put(String k, String? v) {
      if (v == null || v.isEmpty) return;
      if (!out.containsKey(k)) out[k] = v;
    }

    put(
      'rega_ad_license_number',
      q(r'"(?:adLicenseNo|AdLicenseNo|licenseNumber|LicenseNumber|advertisementLicenseNo)"\s*:\s*"(\d{5,20})"'),
    );
    put(
      'rega_ad_license_number',
      q(r'"(?:adLicenseNo|licenseNumber|LicenseNumber)"\s*:\s*(\d{5,20})\b'),
    );
    put(
      'fal_broker_license_number',
      q(r'"(?:falLicenseNo|FalLicenseNo|brokerLicenseNo|BrokerLicenseNo)"\s*:\s*"(\d{5,20})"'),
    );
    put(
      'marketer_entity_display_name',
      q(r'"(?:advertiserName|AdvertiserName|advertiserNameAr)"\s*:\s*"([^"]{2,200})"'),
    );

    return out;
  }

  static String? findQrImageUrl(String html, Uri base) {
    if (html.isEmpty) return null;
    final imgRe = RegExp(r'<img\b[^>]*>', caseSensitive: false);
    for (final m in imgRe.allMatches(html)) {
      final tag = m.group(0)!;
      final srcMatch = RegExp(r'\bsrc\s*=\s*"([^"]+)"', caseSensitive: false)
              .firstMatch(tag) ??
          RegExp(r"\bsrc\s*=\s*'([^']+)'", caseSensitive: false)
              .firstMatch(tag);
      if (srcMatch == null) continue;
      final src = srcMatch.group(1)!.trim();
      if (src.isEmpty) continue;
      final tl = tag.toLowerCase();
      final sl = src.toLowerCase();
      if (tl.contains('qr') ||
          sl.contains('qr') ||
          sl.contains('barcode') ||
          tl.contains('barcode')) {
        return _resolveUrl(src, base);
      }
    }
    return null;
  }

  static String _resolveUrl(String src, Uri base) {
    if (src.startsWith('http://') || src.startsWith('https://')) return src;
    if (src.startsWith('//')) return '${base.scheme}:$src';
    if (src.startsWith('/')) return '${base.origin}$src';
    return base.resolve(src).toString();
  }

  static Map<String, dynamic> mergeExtract({
    required String innerText,
    required String html,
    String? nextJson,
    required Uri pageUri,
  }) {
    final textMap = parsePayloadFromPastedPageText(innerText);
    final merged = Map<String, dynamic>.from(textMap);

    if (nextJson != null && nextJson.trim().isNotEmpty) {
      for (final e in _parseNextDataLoose(nextJson).entries) {
        final cur = merged[e.key]?.toString().trim() ?? '';
        if (cur.isEmpty) merged[e.key] = e.value;
      }
    }

    final qr = findQrImageUrl(html, pageUri);
    if (qr != null && qr.isNotEmpty) merged['ad_qr_image_url'] = qr;

    merged['rega_source_url'] = pageUri.toString();
    return merged;
  }

  @override
  State<RegaAdLicenseImportPage> createState() =>
      _RegaAdLicenseImportPageState();
}

/// حوار للويب: لصق الرابط + نص الصفحة (لا يوجد WebView لنطاق الهيئة من المتصفح بسبب CORS).
Future<Map<String, dynamic>?> showRegaElanImportWebDialog(
  BuildContext context, {
  required bool isAr,
}) {
  return showDialog<Map<String, dynamic>>(
    context: context,
    barrierDismissible: true,
    builder: (ctx) => _RegaElanWebImportDialog(isAr: isAr),
  );
}

class _RegaElanWebImportDialog extends StatefulWidget {
  final bool isAr;

  const _RegaElanWebImportDialog({required this.isAr});

  @override
  State<_RegaElanWebImportDialog> createState() =>
      _RegaElanWebImportDialogState();
}

class _RegaElanWebImportDialogState extends State<_RegaElanWebImportDialog> {
  late final TextEditingController _linkCtrl;
  late final TextEditingController _pasteCtrl;

  @override
  void initState() {
    super.initState();
    _linkCtrl = TextEditingController();
    _pasteCtrl = TextEditingController();
  }

  @override
  void dispose() {
    _linkCtrl.dispose();
    _pasteCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isAr = widget.isAr;
    return Directionality(
      textDirection: isAr ? TextDirection.rtl : TextDirection.ltr,
      child: AlertDialog(
        title: Text(
          isAr ? 'ربط التصريح مع الهيئة' : 'Link permit with REGA',
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                isAr
                    ? 'الصق رابط صفحة «تفاصيل الإعلان» من بوابة الهيئة، أو UUID الصفحة.'
                    : 'Paste the Elan details URL or the page UUID.',
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _linkCtrl,
                decoration: InputDecoration(
                  labelText: isAr ? 'الرابط' : 'URL',
                ),
              ),
              const SizedBox(height: 8),
              Text(
                isAr
                    ? 'لا يُفتح متصفح خارجي. انسخ نص صفحة تفاصيل الإعلان من بوابة الهيئة والصقه أدناه لاستخراج الحقول تلقائياً.'
                    : 'No external browser. Copy the Elan details page text from REGA and paste below.',
              ),
              const SizedBox(height: 12),
              Text(
                isAr
                    ? 'ثم انسخ كل النص من الصفحة والصقه هنا لاستخراج الحقول تلقائياً.'
                    : 'Then copy all visible text from the page and paste below.',
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _pasteCtrl,
                maxLines: 8,
                decoration: InputDecoration(
                  labelText: isAr ? 'نص الصفحة' : 'Page text',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(isAr ? 'إلغاء' : 'Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final uri = RegaAdLicenseImportPage.parseElanDetailsUri(
                    _linkCtrl.text,
                  ) ??
                  RegaAdLicenseImportPage.parseElanDetailsUri(_pasteCtrl.text);
              if (uri == null) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      isAr
                          ? 'أدخل رابطاً يحتوي على معرف الصفحة (UUID).'
                          : 'Enter a URL containing the page UUID.',
                    ),
                  ),
                );
                return;
              }
              final m = RegaAdLicenseImportPage.parsePayloadFromPastedPageText(
                _pasteCtrl.text,
              );
              m['rega_source_url'] = uri.toString();
              Navigator.pop(context, m);
            },
            child: Text(isAr ? 'استيراد' : 'Import'),
          ),
        ],
      ),
    );
  }
}

class _RegaAdLicenseImportPageState extends State<RegaAdLicenseImportPage> {
  late final TextEditingController _urlCtrl;
  late final WebViewController _controller;

  bool _initialLoading = false;
  bool _extracting = false;

  String _t(String ar, String en) => widget.isAr ? ar : en;

  @override
  void initState() {
    super.initState();
    _urlCtrl = TextEditingController();

    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.white)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (url) {
            if (!mounted) return;
            setState(() => _initialLoading = false);
          },
          onWebResourceError: (_) {
            if (!mounted) return;
            setState(() => _initialLoading = false);
          },
        ),
      )
      ..loadRequest(Uri.parse('about:blank'));
  }

  @override
  void dispose() {
    _urlCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadParsedUrl() async {
    final u = RegaAdLicenseImportPage.parseElanDetailsUri(_urlCtrl.text);
    if (u == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_t('رابط غير صالح', 'Invalid URL'))),
      );
      return;
    }
    setState(() => _initialLoading = true);
    await _controller.loadRequest(u);
    Future<void>.delayed(const Duration(seconds: 14), () {
      if (!mounted || !_initialLoading) return;
      setState(() => _initialLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _t(
              'إذا بقيت صفحة الهيئة فارغة، انسخ نص الصفحة والصقه بدلاً من WebView.',
              'If the REGA page stays blank, paste the page text instead of WebView.',
            ),
          ),
        ),
      );
    });
  }

  Future<void> _extractFromCurrentPage() async {
    if (_extracting) return;
    setState(() => _extracting = true);
    try {
      final href = await _controller.currentUrl() ?? '';
      final pageUri = Uri.tryParse(href) ??
          RegaAdLicenseImportPage.parseElanDetailsUri(_urlCtrl.text);
      if (pageUri == null || !pageUri.host.contains('rega.gov.sa')) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _t(
                'افتح صفحة تفاصيل الإعلان من بوابة الهيئة أولاً.',
                'Open the REGA Elan details page first.',
              ),
            ),
          ),
        );
        return;
      }

      final raw = await _controller.runJavaScriptReturningResult(r'''
(function() {
  var el = document.getElementById('__NEXT_DATA__');
  return JSON.stringify({
    next: el ? el.textContent : null,
    text: (document.body && document.body.innerText) ? document.body.innerText.trim() : '',
    html: document.documentElement ? document.documentElement.outerHTML : ''
  });
})();
''');

      final normalized = raw.toString();
      final cleaned = normalized.startsWith('"') && normalized.endsWith('"')
          ? jsonDecode(normalized) as String
          : normalized;
      final map = jsonDecode(cleaned) as Map<String, dynamic>;
      final next = map['next']?.toString();
      final text = (map['text'] ?? '').toString();
      final html = (map['html'] ?? '').toString();

      if (text.trim().isEmpty && (next == null || next.trim().isEmpty)) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _t('تعذر قراءة الصفحة.', 'Could not read page content.'),
            ),
          ),
        );
        return;
      }

      final payload = RegaAdLicenseImportPage.mergeExtract(
        innerText: text,
        html: html,
        nextJson: next,
        pageUri: pageUri,
      );

      if (!mounted) return;
      if ((payload['rega_ad_license_number'] ?? '').toString().trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _t(
                'لم يُعثر على رقم الترخيص. انسخ نص الصفحة والصقه في الويب، أو أعد التحميل.',
                'License number not found. Retry or use web paste flow.',
              ),
            ),
          ),
        );
        return;
      }

      Navigator.pop(context, payload);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${_t('خطأ', 'Error')}: $e')),
      );
    } finally {
      if (mounted) setState(() => _extracting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Directionality(
      textDirection: widget.isAr ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            _t('ربط التصريح مع الهيئة', 'Link permit with REGA'),
          ),
        ),
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: _urlCtrl,
                    decoration: InputDecoration(
                      labelText: _t(
                        'رابط صفحة الهيئة (ElanDetails)',
                        'REGA ElanDetails URL',
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  FilledButton.icon(
                    onPressed: _loadParsedUrl,
                    icon: const Icon(Icons.download_outlined),
                    label: Text(
                        _t('تحميل الصفحة داخل التطبيق', 'Load page in app')),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Stack(
                children: [
                  WebViewWidget(controller: _controller),
                  if (_initialLoading || _extracting)
                    ColoredBox(
                      color: Colors.white.withOpacity(0.94),
                      child: Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const AppLogoLoading(),
                              const SizedBox(height: 20),
                              Text(
                                _extracting
                                    ? _t(
                                        'جاري استخراج بيانات ترخيص الإعلان ومطابقتها مع بيانات الهيئة…',
                                        'Extracting ad license data to match REGA…',
                                      )
                                    : _t(
                                        'الرجاء الانتظار… جاري التحميل من بوابة الهيئة العامة للعقار.',
                                        'Please wait… Loading from REGA.',
                                      ),
                                textAlign: TextAlign.center,
                                style: Theme.of(context)
                                    .textTheme
                                    .bodyLarge
                                    ?.copyWith(fontWeight: FontWeight.w600),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: FilledButton.icon(
                  onPressed: _extracting ? null : _extractFromCurrentPage,
                  icon: const Icon(Icons.assignment_turned_in_outlined),
                  style: FilledButton.styleFrom(
                    backgroundColor: cs.primary,
                    foregroundColor: cs.onPrimary,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  label: Text(
                    _extracting
                        ? _t('جاري الاستيراد…', 'Importing…')
                        : _t('استيراد البيانات من الصفحة', 'Import from page'),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
