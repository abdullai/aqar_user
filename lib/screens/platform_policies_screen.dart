import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/compliance/platform_policy_copy.dart';

/// عرض سياسات المنصة — يحمّل النص الكامل من `docs/compliance/*.md` عند توفره في الأصول، وإلا الملخص المحلي.
class PlatformPoliciesScreen extends StatefulWidget {
  const PlatformPoliciesScreen({
    super.key,
    required this.isAr,
    this.initialDoc,
  });

  final bool isAr;
  final PlatformPolicyDoc? initialDoc;

  @override
  State<PlatformPoliciesScreen> createState() => _PlatformPoliciesScreenState();
}

class _PlatformPoliciesScreenState extends State<PlatformPoliciesScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _ctrl;

  static const _docs = <PlatformPolicyDoc>[
    PlatformPolicyDoc.termsOfUse,
    PlatformPolicyDoc.privacy,
    PlatformPolicyDoc.intellectualProperty,
    PlatformPolicyDoc.cookies,
  ];

  late final Map<PlatformPolicyDoc, Future<String>> _resolvedBodies;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialDoc;
    final initialIndex =
        initial == null ? 0 : _docs.indexOf(initial).clamp(0, _docs.length - 1);
    _ctrl = TabController(
      length: _docs.length,
      vsync: this,
      initialIndex: initialIndex,
    );
    final ar = widget.isAr;
    _resolvedBodies = {
      for (final d in _docs) d: _resolvePolicy(d, ar),
    };
  }

  static String _complianceAssetPath(PlatformPolicyDoc d, bool ar) {
    final lang = ar ? 'AR' : 'EN';
    switch (d) {
      case PlatformPolicyDoc.termsOfUse:
        return 'docs/compliance/TERMS_OF_USE_$lang.md';
      case PlatformPolicyDoc.privacy:
        return 'docs/compliance/PRIVACY_POLICY_$lang.md';
      case PlatformPolicyDoc.intellectualProperty:
        return 'docs/compliance/INTELLECTUAL_PROPERTY_$lang.md';
      case PlatformPolicyDoc.cookies:
        return 'docs/compliance/COOKIES_POLICY_$lang.md';
    }
  }

  static Future<String> _loadBundledPolicy(String path) async {
    try {
      final s = await rootBundle.loadString(path);
      if (s.trim().isNotEmpty) return s;
    } catch (_) {}
    return '';
  }

  static Future<String> _resolvePolicy(PlatformPolicyDoc d, bool ar) async {
    final raw = await _loadBundledPolicy(_complianceAssetPath(d, ar));
    if (raw.isNotEmpty) return raw;
    return PlatformPolicyCopy.body(d, ar);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ar = widget.isAr;
    final cs = Theme.of(context).colorScheme;
    return Directionality(
      textDirection: ar ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        appBar: AppBar(
          title: Text(ar ? 'سياسات المنصة' : 'Platform policies'),
          bottom: TabBar(
            controller: _ctrl,
            isScrollable: true,
            tabs: [
              for (final d in _docs)
                Tab(text: PlatformPolicyCopy.title(d, ar)),
            ],
          ),
        ),
        body: TabBarView(
          controller: _ctrl,
          children: [
            for (final d in _docs)
              FutureBuilder<String>(
                future: _resolvedBodies[d],
                builder: (context, snap) {
                  final text = snap.data ??
                      PlatformPolicyCopy.body(d, ar);
                  return SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
                    child: SelectableText(
                      text,
                      style: TextStyle(
                        height: 1.5,
                        fontWeight: FontWeight.w600,
                        color: cs.onSurface.withValues(alpha: 0.92),
                      ),
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }
}
