import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/haptics/app_haptics.dart';
import '../l10n/app_localizations.dart';
import '../main.dart' show langNotifier;
import '../services/report_service.dart';
import '../widgets/report_card.dart';
import '../widgets/subscription_staff_reports_panel.dart';
import 'custom_report_builder_screen.dart';
import 'session_history_screen.dart';

/// لوحة التقارير والتصدير؛ [embedded] للتضمين داخل تبويب «إدارتي».
class ReportsDashboardScreen extends StatelessWidget {
  const ReportsDashboardScreen({
    super.key,
    this.embedded = false,
    this.lang,
  });

  final bool embedded;
  final String? lang;

  bool _isArFromCtx(BuildContext context) {
    final l = lang ?? langNotifier.value;
    if (l.isNotEmpty) return l.toLowerCase() != 'en';
    final loc = AppLocalizations.of(context);
    return loc == null ? true : loc.localeName.toLowerCase().startsWith('ar');
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final isAr = _isArFromCtx(context);
    final svc = ReportService(Supabase.instance.client);
    final templates = svc.getReportTemplates(isAr: isAr);

    Widget body = Container(
      color: cs.surface,
      child: ListView(
        padding: EdgeInsets.fromLTRB(
          12,
          embedded ? 8 : 12,
          12,
          24,
        ),
        children: [
          if (embedded)
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
                      t.reportsDeskServerSyncHint,
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
                  builder: (_) => CustomReportBuilderScreen(lang: lang),
                ),
              );
            },
          ),
          Divider(color: cs.outlineVariant.withValues(alpha: 0.5)),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Text(
              isAr ? 'قوالب جاهزة' : 'Ready templates',
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
            ),
          ),
          ...templates.map(
            (cfg) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: ReportCard(
                title: cfg.title,
                subtitle: cfg.filtersDescription.isEmpty
                    ? (isAr ? 'اضغط للمتابعة' : 'Tap to continue')
                    : cfg.filtersDescription,
                icon: Icons.description_outlined,
                onTap: () {
                  AppHaptics.light();
                  Navigator.push<void>(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => CustomReportBuilderScreen(
                        lang: lang,
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

    if (embedded) return body;

    return Scaffold(
      appBar: AppBar(
        // عند الفتح داخل لوحة الداشبورد: السهم الموحد بالشريط العلوي للداشبورد.
        automaticallyImplyLeading: false,
        title: Text(isAr ? 'التقارير' : 'Reports'),
      ),
      body: body,
    );
  }
}
