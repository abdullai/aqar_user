import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/haptics/app_haptics.dart';
import '../l10n/app_localizations.dart';
import '../main.dart' show langNotifier;
import '../services/report_service.dart';
import '../widgets/app_logo_loading.dart';
import '../widgets/app_page_close_button.dart';
import '../widgets/report_card.dart';
import '../widgets/subscription_staff_reports_panel.dart';
import 'custom_report_builder_screen.dart';
import 'session_history_screen.dart';

/// لوحة التقارير والتصدير؛ [embedded] للتضمين داخل تبويب «إدارتي».
class ReportsDashboardScreen extends StatefulWidget {
  const ReportsDashboardScreen({
    super.key,
    this.embedded = false,
    this.lang,
  });

  final bool embedded;
  final String? lang;

  @override
  State<ReportsDashboardScreen> createState() => _ReportsDashboardScreenState();
}

class _ReportsDashboardScreenState extends State<ReportsDashboardScreen> {
  final _svc = ReportService(Supabase.instance.client);
  Future<List<ReportConfig>>? _live;
  bool? _liveForAr;

  bool _isArFromCtx(BuildContext context) {
    final l = widget.lang ?? langNotifier.value;
    if (l.isNotEmpty) return l.toLowerCase() != 'en';
    final loc = AppLocalizations.of(context);
    return loc == null ? true : loc.localeName.toLowerCase().startsWith('ar');
  }

  void _ensureLive(bool isAr) {
    if (_liveForAr == isAr && _live != null) return;
    _liveForAr = isAr;
    _live = _svc.loadLiveReports(isAr: isAr);
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final isAr = _isArFromCtx(context);
    _ensureLive(isAr);

    Widget bodyFor(List<ReportConfig> templates, {required bool loading}) {
      return Container(
        color: cs.surface,
        child: ListView(
          padding: EdgeInsets.fromLTRB(
            12,
            widget.embedded ? 8 : 12,
            12,
            24,
          ),
          children: [
            if (widget.embedded)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  children: [
                    Icon(Icons.verified_outlined, color: cs.primary, size: 22),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        t.appTitle,
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 13,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            Card(
              margin: EdgeInsets.zero,
              color: cs.primaryContainer.withValues(alpha: 0.35),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.info_outline, color: cs.primary, size: 22),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        isAr
                            ? 'التقارير أدناه من بيانات حسابك والمنشأة الحقيقية — ليست قوالب تجريبية. الذكاء الاصطناعي لا يحسب المبالغ.'
                            : 'Reports below use your live account and organization data — not sample templates. AI never computes money.',
                        style: TextStyle(
                          fontSize: 12.5,
                          height: 1.35,
                          color: cs.onSurface,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
            SubscriptionStaffReportsPanel(isAr: isAr),
            Card(
              margin: EdgeInsets.zero,
              child: ListTile(
                leading: Icon(Icons.history_rounded, color: cs.primary),
                title: Text(
                  isAr ? 'سجل جلسات الدخول' : 'Login session history',
                ),
                subtitle: Text(
                  isAr
                      ? 'عرض الجلسات وإنهاء الأجهزة الأخرى'
                      : 'View sessions and revoke other devices',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  AppHaptics.light();
                  Navigator.push<void>(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => const SessionHistoryScreen(),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 10),
            ListTile(
              leading: Icon(Icons.build_outlined, color: cs.primary),
              title: Text(isAr ? 'منشئ تقرير مخصص' : 'Custom report builder'),
              subtitle: Text(
                isAr
                    ? 'فترة، أعمدة، ثم معاينة وتصدير'
                    : 'Date range, columns, then preview and export',
              ),
              onTap: () {
                AppHaptics.light();
                Navigator.push<void>(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => CustomReportBuilderScreen(lang: widget.lang),
                  ),
                );
              },
            ),
            Divider(color: cs.outlineVariant.withValues(alpha: 0.5)),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Text(
                isAr ? 'تقارير الحساب' : 'Account reports',
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
              ),
            ),
            if (loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: AppLogoLoading()),
              )
            else
              ...templates.map(
                (cfg) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: ReportCard(
                    title: cfg.title,
                    subtitle: cfg.filtersDescription.isEmpty
                        ? (isAr ? 'بيانات حية — اضغط للمعاينة' : 'Live data — tap to preview')
                        : cfg.filtersDescription,
                    icon: Icons.description_outlined,
                    onTap: () {
                      AppHaptics.light();
                      Navigator.push<void>(
                        context,
                        MaterialPageRoute<void>(
                          builder: (_) => CustomReportBuilderScreen(
                            lang: widget.lang,
                            initialConfig: cfg,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
          ],
        ),
      );
    }

    final body = FutureBuilder<List<ReportConfig>>(
      future: _live,
      builder: (context, snap) {
        final loading =
            snap.connectionState != ConnectionState.done && !snap.hasData;
        final templates = snap.data ?? const <ReportConfig>[];
        return bodyFor(templates, loading: loading);
      },
    );

    if (widget.embedded) return body;

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        leading: AppPageCloseButton(isArabic: isAr),
        title: Text(isAr ? 'التقارير' : 'Reports'),
      ),
      body: body,
    );
  }
}
