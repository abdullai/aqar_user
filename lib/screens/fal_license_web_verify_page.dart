import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../widgets/app_logo_loading.dart';

/// صفحة WebView تفتح **تفاصيل رخصة الوساطة** على بوابة الهيئة (aqari) مباشرة.
class FalLicenseWebVerifyPage extends StatefulWidget {
  final String licenseNo;

  const FalLicenseWebVerifyPage({
    super.key,
    required this.licenseNo,
  });

  /// الرابط الرسمي لصفحة التفاصيل (يُستخدم أيضاً لفتح المتصفح على الويب).
  static Uri detailsUri(String licenseNo) {
    final d = licenseNo.replaceAll(RegExp(r'\D'), '');
    return Uri.parse(
      'https://aqari.rega.gov.sa/Inquires/Brokerage/Details/$d',
    );
  }

  @override
  State<FalLicenseWebVerifyPage> createState() =>
      _FalLicenseWebVerifyPageState();
}

class _FalLicenseWebVerifyPageState extends State<FalLicenseWebVerifyPage> {
  late final WebViewController _controller;

  bool _loading = true;
  bool _returned = false;
  bool _watchStarted = false;

  Timer? _watchTimer;
  Timer? _timeoutTimer;

  @override
  void initState() {
    super.initState();

    final uri = FalLicenseWebVerifyPage.detailsUri(widget.licenseNo);
    debugPrint('[FAL] init, url=$uri');

    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.white)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (url) {
            debugPrint('[FAL] page started: $url');
          },
          onPageFinished: (url) async {
            debugPrint('[FAL] page finished: $url');
            if (_returned || _watchStarted) return;
            _watchStarted = true;
            await Future<void>.delayed(const Duration(milliseconds: 1400));
            if (!mounted || _returned) return;
            setState(() => _loading = false);
            _startWatching();
          },
          onWebResourceError: (error) {
            debugPrint(
              '[FAL] web resource error: ${error.errorCode} | ${error.description}',
            );
          },
        ),
      )
      ..loadRequest(uri);

    _startTimeout();
  }

  @override
  void dispose() {
    _watchTimer?.cancel();
    _timeoutTimer?.cancel();
    super.dispose();
  }

  void _startTimeout() {
    _timeoutTimer?.cancel();
    _timeoutTimer = Timer(const Duration(seconds: 50), () {
      if (!mounted || _returned) return;

      debugPrint('[FAL] timeout reached');
      _finishWithResult({
        'valid': false,
        'owner_name': null,
        'status': 'timeout',
        'status_text': 'timeout',
        'start_date': '',
        'end_date': '',
        'error': 'timeout',
      });
    });
  }

  void _finishWithResult(Map<String, dynamic> result) {
    if (_returned || !mounted) return;

    _returned = true;
    _watchTimer?.cancel();
    _timeoutTimer?.cancel();

    debugPrint('[FAL] returning result: $result');
    Navigator.pop(context, result);
  }

  /// استخراج تواريخ بصيغة dd/mm/yyyy من النص.
  static List<String> _extractDatesDdMmYyyy(String body) {
    final re = RegExp(r'\b(\d{2}/\d{2}/\d{4})\b');
    return re.allMatches(body).map((m) => m.group(1)!).toList();
  }

  /// تواريخ بصيغة yyyy-mm-dd كما تظهر أحياناً في واجهة عقاري.
  static List<String> _extractDatesYyyyMmDd(String body) {
    final re = RegExp(r'\b(\d{4}-\d{2}-\d{2})\b');
    return re.allMatches(body).map((m) => m.group(1)!).toList();
  }

  /// بعد تسمية «معلومات الوسيط»: السطر التالي لـ «الاسم» غالباً اسم الوسيط الكامل.
  static String? _ownerNameFromBrokerSection(List<String> lines) {
    final idx = lines.indexWhere((e) => e.contains('معلومات الوسيط'));
    if (idx < 0) return null;
    final end = (idx + 22).clamp(0, lines.length);
    for (var i = idx + 1; i < end; i++) {
      final line = lines[i];
      if (line == 'الاسم' || line.startsWith('الاسم')) {
        if (i + 1 >= lines.length) continue;
        final v = lines[i + 1];
        if (v.contains('@')) continue;
        if (v.length >= 6) return v;
      }
    }
    return null;
  }

  static String? _firstEmailAfterMarker(String body, String marker, int maxLen) {
    final i = body.indexOf(marker);
    if (i < 0) return null;
    final end = (i + maxLen < body.length) ? i + maxLen : body.length;
    final slice = body.substring(i, end);
    final m = RegExp(
      r'[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-zA-Z]{2,}',
    ).firstMatch(slice);
    return m?.group(0);
  }

  static String? _firstMobile05AfterMarker(String body, String marker, int maxLen) {
    final i = body.indexOf(marker);
    if (i < 0) return null;
    final end = (i + maxLen < body.length) ? i + maxLen : body.length;
    final compact = body.substring(i, end).replaceAll(RegExp(r'[^\d]'), '');
    final m = RegExp(r'05\d{8}').firstMatch(compact);
    return m?.group(0);
  }

  /// `null` = لم يكتمل التحميل أو لا توجد بيانات كافية بعد؛ غير `null` = أغلق الصفحة بهذه النتيجة.
  static Map<String, dynamic>? _parseLicensePage(
    String currentUrl,
    String bodyText,
  ) {
    if (bodyText.isEmpty) return null;

    if (bodyText.contains('رفض') ||
        bodyText.contains('غير مسموح') ||
        bodyText.contains('Access denied') ||
        bodyText.contains('This content is blocked') ||
        bodyText.contains('refused to connect') ||
        (bodyText.contains('403') && bodyText.length < 800)) {
      return {
        'valid': false,
        'owner_name': null,
        'status': 'blocked',
        'status_text': 'blocked',
        'start_date': '',
        'end_date': '',
        'error': 'blocked_by_site_policy',
      };
    }

    final onDetailsPath = currentUrl.contains('Brokerage/Details') ||
        currentUrl.contains('Inquires/Brokerage');

    // أخطاء مثل 401 على web-uniplatform.nhc.sa أو فشل main.css لا تمنع
    // عادةً قراءة document.body.innerText لصفحة التفاصيل على aqari.
    final hasResult = onDetailsPath ||
        bodyText.contains('معلومات الوسيط') ||
        bodyText.contains('استعلام عن وسيط') ||
        bodyText.contains('اسم الوسيط') ||
        bodyText.contains('حالة الرخصة') ||
        bodyText.contains('بداية الرخصة') ||
        bodyText.contains('نهاية الرخصة') ||
        bodyText.contains('تاريخ بداية') ||
        bodyText.contains('تاريخ انتهاء') ||
        (bodyText.contains('License') && bodyText.contains('Broker'));

    if (!hasResult) return null;

    final lines = bodyText
        .split('\n')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();

    String? valueAfter(String label) {
      final i = lines.indexWhere((e) => e == label || e.contains(label));
      if (i >= 0 && i + 1 < lines.length) {
        return lines[i + 1];
      }
      for (final line in lines) {
        if (line.contains(label) && line.contains(':')) {
          final parts = line.split(':');
          if (parts.length >= 2) {
            final v = parts.sublist(1).join(':').trim();
            if (v.isNotEmpty) return v;
          }
        }
      }
      return null;
    }

    final ownerFromBroker = _ownerNameFromBrokerSection(lines);
    final ownerName = valueAfter('اسم الوسيط') ??
        valueAfter('اسم الوسيط فرد / المنشأة') ??
        valueAfter('اسم الوسيط فرد') ??
        valueAfter('Broker name') ??
        ownerFromBroker ??
        valueAfter('الاسم');

    final statusText = valueAfter('حالة الرخصة') ??
        valueAfter('License status') ??
        (bodyText.contains('سارية')
            ? 'سارية'
            : bodyText.contains('منتهية')
                ? 'منتهية'
                : null);

    var startDate = valueAfter('تاريخ بداية الرخصة') ??
        valueAfter('بداية الرخصة') ??
        valueAfter('تاريخ البداية') ??
        valueAfter('Start date') ??
        '';

    var endDate = valueAfter('تاريخ انتهاء الرخصة') ??
        valueAfter('تاريخ انتهاء صلاحية الرخصة') ??
        valueAfter('تاريخ نهاية الرخصة') ??
        valueAfter('نهاية الرخصة') ??
        valueAfter('تاريخ النهاية') ??
        valueAfter('End date') ??
        valueAfter('Expiry date') ??
        valueAfter('License expiry') ??
        '';

    if (startDate.isEmpty || endDate.isEmpty) {
      final iso = _extractDatesYyyyMmDd(bodyText);
      if (iso.isNotEmpty) {
        if (startDate.isEmpty) startDate = iso.first;
        if (endDate.isEmpty) {
          endDate = iso.length > 1 ? iso.last : iso.first;
        }
      }
    }

    if ((startDate.isEmpty || endDate.isEmpty)) {
      final dates = _extractDatesDdMmYyyy(bodyText);
      if (dates.length >= 2) {
        if (startDate.isEmpty) startDate = dates.first;
        if (endDate.isEmpty) endDate = dates.last;
      } else if (dates.length == 1 && endDate.isEmpty) {
        endDate = dates.first;
      }
    }

    // رقم الهوية: فقط من التسميات حتى لا يُخلط مع رقم رخصة فال (10 أرقام).
    final nidRaw = (valueAfter('رقم الهوية') ??
            valueAfter('الهوية الوطنية') ??
            valueAfter('هوية الوسيط') ??
            valueAfter('رقم الهوية / الإقامة') ??
            valueAfter('رقم الإقامة') ??
            valueAfter('National ID') ??
            valueAfter('Iqama') ??
            '')
        .trim();
    final nidDigits = nidRaw.replaceAll(RegExp(r'\D'), '');
    final String? brokerNationalId =
        nidDigits.length == 10 ? nidDigits : null;

    var brokerEmail = valueAfter('البريد الإلكتروني') ??
        valueAfter('Email') ??
        _firstEmailAfterMarker(bodyText, 'معلومات الوسيط', 2000);
    if (brokerEmail != null && !brokerEmail.contains('@')) {
      brokerEmail = null;
    }

    var brokerMobile = valueAfter('رقم الجوال') ??
        valueAfter('جوال') ??
        valueAfter('Mobile') ??
        valueAfter('رقم الهاتف') ??
        _firstMobile05AfterMarker(bodyText, 'معلومات الوسيط', 1200);

    final isValid = ownerName != null ||
        statusText != null ||
        (startDate.isNotEmpty || endDate.isNotEmpty);

    if (!isValid) return null;

    return {
      'valid': true,
      'owner_name': ownerName,
      'status': statusText ?? '',
      'status_text': statusText,
      'start_date': startDate,
      'end_date': endDate,
      if (brokerEmail != null && brokerEmail.isNotEmpty)
        'broker_email': brokerEmail,
      if (brokerMobile != null && brokerMobile.isNotEmpty)
        'broker_mobile': brokerMobile,
      if (brokerNationalId != null && brokerNationalId.isNotEmpty)
        'broker_national_id': brokerNationalId,
    };
  }

  void _startWatching() {
    _watchTimer?.cancel();

    _watchTimer = Timer.periodic(const Duration(seconds: 2), (timer) async {
      if (!mounted || _returned) {
        timer.cancel();
        return;
      }

      try {
        final currentUrl = await _controller.currentUrl() ?? '';

        debugPrint('[FAL] watch tick, url=$currentUrl');

        final raw = await _controller.runJavaScriptReturningResult(r'''
(function() {
  return JSON.stringify({
    url: location.href,
    title: document.title || '',
    text: (document.body?.innerText || '').trim()
  });
})();
''');

        final normalized = raw.toString();
        final cleaned = normalized.startsWith('"') && normalized.endsWith('"')
            ? jsonDecode(normalized) as String
            : normalized;

        final map = jsonDecode(cleaned) as Map<String, dynamic>;
        final bodyText = (map['text'] ?? '').toString();
        final pageTitle = (map['title'] ?? '').toString();

        debugPrint(
          '[FAL] title=$pageTitle | body length=${bodyText.length}',
        );

        final parsed = _parseLicensePage(currentUrl, bodyText);
        if (parsed != null) {
          debugPrint('[FAL] parsed: $parsed');
          _finishWithResult(parsed);
        }
      } catch (e) {
        debugPrint('[FAL] watch error: $e');
      }
    });
  }

  Future<void> _onContinueToSignupPressed() async {
    if (!mounted || _returned) return;
    try {
      final currentUrl = await _controller.currentUrl() ?? '';
      final raw = await _controller.runJavaScriptReturningResult(r'''
(function() {
  return JSON.stringify({
    text: (document.body?.innerText || '').trim()
  });
})();
''');
      final normalized = raw.toString();
      final cleaned = normalized.startsWith('"') && normalized.endsWith('"')
          ? jsonDecode(normalized) as String
          : normalized;
      final map = jsonDecode(cleaned) as Map<String, dynamic>;
      final bodyText = (map['text'] ?? '').toString();
      final parsed = _parseLicensePage(currentUrl, bodyText);
      if (parsed != null) {
        _finishWithResult(parsed);
        return;
      }
      if (!mounted || _returned) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text(
            'تعذر قراءة بيانات الرخصة تلقائياً. سنعود لصفحة التسجيل — أعد الضغط على «التحقق» إن لزم.',
          ),
        ),
      );
      _finishWithResult({
        'valid': false,
        'owner_name': null,
        'status': 'manual_no_parse',
        'status_text': 'manual_no_parse',
        'start_date': '',
        'end_date': '',
        'error': 'manual_no_parse',
        '_error_detail':
            'لم نتمكن من قراءة بيانات الرخصة من الصفحة. أعد المحاولة من صفحة التسجيل.',
      });
    } catch (e) {
      debugPrint('[FAL] manual continue error: $e');
      if (!mounted || _returned) return;
      _finishWithResult({
        'valid': false,
        'owner_name': null,
        'status': 'manual_no_parse',
        'status_text': 'manual_no_parse',
        'start_date': '',
        'end_date': '',
        'error': 'manual_no_parse',
        '_error_detail': e.toString(),
      });
    }
  }

  Future<void> _handleSystemBack() async {
    if (!mounted || _returned) return;
    try {
      final canBack = await _controller.canGoBack();
      if (canBack) {
        await _controller.goBack();
      } else {
        _finishWithResult({
          'valid': false,
          'owner_name': null,
          'status': 'cancelled',
          'status_text': 'cancelled',
          'start_date': '',
          'end_date': '',
          'error': 'cancelled_by_user',
        });
      }
    } catch (_) {
      if (!mounted || _returned) return;
      _finishWithResult({
        'valid': false,
        'owner_name': null,
        'status': 'cancelled',
        'status_text': 'cancelled',
        'start_date': '',
        'end_date': '',
        'error': 'cancelled_by_user',
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final scaffold = Scaffold(
      appBar: AppBar(
        title: const Text('التحقق من رخصة فال — الهيئة العامة للعقار'),
        actions: [
          IconButton(
            onPressed: () {
              _finishWithResult({
                'valid': false,
                'owner_name': null,
                'status': 'cancelled',
                'status_text': 'cancelled',
                'start_date': '',
                'end_date': '',
                'error': 'cancelled_by_user',
              });
            },
            icon: const Icon(Icons.close),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Stack(
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
                            const SizedBox(height: 18),
                            Text(
                              'الرجاء الانتظار… جاري التحقق من بيانات الرخصة لدى الهيئة العامة للعقار.',
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
          Material(
            elevation: 8,
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _onContinueToSignupPressed,
                    icon: const Icon(Icons.check_circle_outline),
                    label: const Text(
                      'تم عرض التفاصيل — متابعة التسجيل',
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, Object? result) {
        if (didPop || _returned) return;
        unawaited(_handleSystemBack());
      },
      child: scaffold,
    );
  }
}
