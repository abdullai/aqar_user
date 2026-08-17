import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/compliance_legal_service.dart';

/// إدارة موافقات الكوكيز الاختيارية (تحليلات / تسويق) — من الإعدادات فقط.
class ConsentPreferencesScreen extends StatefulWidget {
  const ConsentPreferencesScreen({super.key, required this.isAr});

  final bool isAr;

  @override
  State<ConsentPreferencesScreen> createState() =>
      _ConsentPreferencesScreenState();
}

class _ConsentPreferencesScreenState extends State<ConsentPreferencesScreen> {
  final _sb = Supabase.instance.client;
  bool _loading = true;
  bool _saving = false;
  bool _analytics = false;
  bool _marketing = false;
  bool _essential = true;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final uid = _sb.auth.currentUser?.id;
    if (uid == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    try {
      final row = await _sb
          .from('regc_consent_preferences')
          .select('analytics_cookies, marketing_cookies, essential_ack')
          .eq('user_id', uid)
          .maybeSingle();
      if (!mounted) return;
      if (row != null) {
        setState(() {
          _analytics = row['analytics_cookies'] == true;
          _marketing = row['marketing_cookies'] == true;
          _essential = row['essential_ack'] != false;
          _loading = false;
        });
        return;
      }
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await ComplianceLegalService.upsertConsentPreferences(
        analyticsCookies: _analytics,
        marketingCookies: _marketing,
        essentialAck: _essential,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(widget.isAr ? 'تم حفظ التفضيلات' : 'Preferences saved'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _withdrawOptional() async {
    setState(() {
      _analytics = false;
      _marketing = false;
      _essential = true;
    });
    await _save();
  }

  @override
  Widget build(BuildContext context) {
    final ar = widget.isAr;
    final cs = Theme.of(context).colorScheme;
    return Directionality(
      textDirection: ar ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        appBar: AppBar(
          title: Text(ar ? 'إدارة الموافقات' : 'Consent management'),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  Text(
                    ar
                        ? 'الكوكيز الضرورية للجلسة والأمان لا يمكن تعطيلها من التطبيق دون التأثير على تسجيل الدخول.'
                        : 'Essential session/security cookies cannot be disabled here without breaking sign-in.',
                    style: TextStyle(
                      height: 1.4,
                      fontWeight: FontWeight.w600,
                      color: cs.onSurface.withValues(alpha: 0.88),
                    ),
                  ),
                  const SizedBox(height: 16),
                  ListTile(
                    leading: Icon(Icons.check_circle, color: cs.primary),
                    title: Text(
                      ar ? 'التخزين الضروري / الكوكيز الأساسية' : 'Essential storage / cookies',
                    ),
                    subtitle: Text(
                      ar ? 'مفعّل للجلسة والأمان — لا يُعطَّل من هنا' : 'On for session & security — not disabled here',
                    ),
                  ),
                  SwitchListTile(
                    value: _analytics,
                    onChanged: _saving
                        ? null
                        : (v) => setState(() => _analytics = v),
                    title: Text(ar ? 'كوكيز التحليلات' : 'Analytics cookies'),
                    subtitle: Text(
                      ar
                          ? 'لتحسين الأداء وفهم الاستخدام بشكل مجهّل قدر الإمكان'
                          : 'To improve performance and understand usage (aggregated where possible)',
                    ),
                  ),
                  SwitchListTile(
                    value: _marketing,
                    onChanged: _saving
                        ? null
                        : (v) => setState(() => _marketing = v),
                    title: Text(ar ? 'كوكيز تسويقية' : 'Marketing cookies'),
                    subtitle: Text(
                      ar
                          ? 'عند تفعيل ميزات تسويقية مستقبلية داخل المنصة'
                          : 'For future in-platform marketing features',
                    ),
                  ),
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: _saving ? null : _save,
                    child: Text(ar ? 'حفظ' : 'Save'),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton(
                    onPressed: _saving ? null : _withdrawOptional,
                    child: Text(
                      ar
                          ? 'سحب الموافقات الاختيارية'
                          : 'Withdraw optional consents',
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
