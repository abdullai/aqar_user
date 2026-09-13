import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:aqar_user/widgets/aqar_text_field.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/branding/app_branding.dart';
import '../core/compliance/platform_compliance_config.dart';
import '../core/gestures/app_keyboard_popups.dart';
import '../core/navigation/safe_overlay_pop.dart';
import '../l10n/app_localizations.dart';
import '../services/compliance_audit_service.dart';
import '../widgets/app_page_close_button.dart';
import '../widgets/support/support_contact_actions.dart';
import '../widgets/support/support_labeled_table.dart';

/// شكوى داخل التطبيق → جدول [regc_user_complaints] + سجل تدقيق (ترحيل 20260515183000).
Future<void> showInAppComplaintDialog(
  BuildContext context, {
  required bool isAr,
}) async {
  final subject = TextEditingController();
  final body = TextEditingController();
  try {
    await showAppDialog<void>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text(isAr ? 'شكوى داخل التطبيق' : 'In-app complaint'),
          content: SingleChildScrollView(
            child: SupportLabeledTable(
              rows: [
                SupportLabeledRow(
                  label: isAr ? 'الموضوع' : 'Subject',
                  child: AqarTextField(
                    controller: subject,
                    minLines: 2,
                    maxLines: 6,
                    keyboardType: TextInputType.multiline,
                    textInputAction: TextInputAction.newline,
                    decoration: InputDecoration(
                      hintText: isAr ? 'موضوع واضح' : 'Clear subject',
                      border: InputBorder.none,
                    ),
                  ),
                ),
                SupportLabeledRow(
                  label: isAr ? 'التفاصيل' : 'Details',
                  child: AqarTextField(
                    controller: body,
                    minLines: 4,
                    maxLines: 10,
                    keyboardType: TextInputType.multiline,
                    textInputAction: TextInputAction.newline,
                    decoration: InputDecoration(
                      hintText: isAr
                          ? 'اشرح المشكلة بالتفصيل'
                          : 'Describe the issue',
                      border: InputBorder.none,
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(isAr ? 'إلغاء' : 'Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                final s = subject.text.trim();
                final b = body.text.trim();
                if (s.isEmpty || b.isEmpty) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    SnackBar(
                      content: Text(
                        isAr ? 'يرجى تعبئة الموضوع والتفاصيل' : 'Please fill subject and details',
                      ),
                    ),
                  );
                  return;
                }
                final uid = Supabase.instance.client.auth.currentUser?.id;
                if (uid == null) return;
                try {
                  final ins = await Supabase.instance.client
                      .from('regc_user_complaints')
                      .insert({
                        'user_id': uid,
                        'subject': s,
                        'body': b,
                      })
                      .select('id')
                      .maybeSingle();
                  final id = ins?['id']?.toString();
                  if (ctx.mounted) Navigator.pop(ctx);
                  unawaited(
                    ComplianceAuditService.instance.log('complaint.submitted', {
                      if (id != null) 'complaint_id': id,
                    }),
                  );
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          isAr ? 'سُجِّلت الشكوى في النظام' : 'Complaint recorded',
                        ),
                      ),
                    );
                  }
                } catch (e) {
                  if (ctx.mounted) {
                    ScaffoldMessenger.of(ctx).showSnackBar(
                      SnackBar(content: Text('$e')),
                    );
                  }
                }
              },
              child: Text(isAr ? 'إرسال' : 'Submit'),
            ),
          ],
        );
      },
    );
  } finally {
    subject.dispose();
    body.dispose();
  }
}

class SupportPage extends StatelessWidget {
  final String userId;
  final bool isAr;
  final Color bankColor;

  /// عند false يُعاد المحتوى فقط (للتضمين داخل تبويبات لوحة أخرى).
  final bool wrapInScaffold;

  /// إخفاء نموذج الشكوى القديم (يُعرض في [ComplaintSubmitForm]).
  final bool hideComplaintForm;

  final ScrollController? scrollController;

  const SupportPage({
    super.key,
    required this.userId,
    required this.isAr,
    required this.bankColor,
    this.wrapInScaffold = true,
    this.hideComplaintForm = true,
    this.scrollController,
  });

  Widget _body(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final support = PlatformComplianceConfig.supportEmail();
    final complaints = PlatformComplianceConfig.complaintsEmail();
    final web = PlatformComplianceConfig.complaintsWebUrl();
    final mailSubject = isAr
        ? 'دعم فني — ${AppBranding.brandNameAr}'
        : 'Support — ${AppBranding.brandNameEn}';

    return Padding(
      padding: const EdgeInsets.all(16),
      child: ListView(
        controller: scrollController,
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.supportCenterTitle,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    l10n.supportCenterIntro,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: 16),
                  SupportEmailTile(
                    email: support,
                    subject: mailSubject,
                    accentColor: bankColor,
                  ),
                  SupportPhoneLinesColumn(accentColor: bankColor),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.schedule_outlined, color: bankColor),
                    title: Text(l10n.supportHoursLabel),
                    subtitle: Text(l10n.supportHoursValue),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            color: Theme.of(context).colorScheme.errorContainer.withValues(alpha: 0.35),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.report_problem_outlined,
                          color: Theme.of(context).colorScheme.error),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          isAr ? 'الشكاوى والامتثال' : 'Complaints & compliance',
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    isAr
                        ? 'للإبلاغ عن مخالفة أو طلب امتثال: يُسجَّل الطلب عبر البريد المخصّص. تُعالَج الشكاوى وفق سياسة داخلية (تصنيف، مهلة أول رد، إحالة للجنة عند الحاجة) — يُرفق وصفها في ملف الترخيص عند الطلب.'
                        : 'To report a violation or compliance matter: use the dedicated mailbox. Complaints follow an internal workflow (triage, first-response SLA, escalation) — document this in your licensing file when required.',
                  ),
                  const SizedBox(height: 12),
                  if (!hideComplaintForm)
                    ListTile(
                      leading: Icon(Icons.post_add_outlined, color: bankColor),
                      title: Text(isAr ? 'تسجيل شكوى في المنصة' : 'Log in-app complaint'),
                      subtitle: Text(
                        isAr
                            ? 'يُحفَظ السجل في قاعدة البيانات مع تدقيق امتثال (يتطلّب ترحيل الخادم).'
                            : 'Stored in the database with a compliance audit event (requires server migration).',
                      ),
                      trailing: Icon(Icons.chevron_right_rounded, color: bankColor),
                      onTap: () => showInAppComplaintDialog(context, isAr: isAr),
                    ),
                  SupportEmailTile(
                    email: complaints,
                    subject: isAr
                        ? 'شكوى — ${AppBranding.brandNameAr}'
                        : 'Complaint — ${AppBranding.brandNameEn}',
                    accentColor: bankColor,
                  ),
                  if (web != null && !hideComplaintForm)
                    ListTile(
                      leading: Icon(Icons.language_outlined, color: bankColor),
                      title: Text(isAr ? 'صفحة الشكاوى على الويب' : 'Web complaints page'),
                      subtitle: Text(web),
                      onTap: () async {
                        final u = Uri.parse(web);
                        try {
                          if (await canLaunchUrl(u)) {
                            await launchUrl(u, mode: LaunchMode.externalApplication);
                          }
                        } catch (_) {}
                      },
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isAr ? 'الأسئلة الشائعة' : 'Frequently Asked Questions',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 8),
                  ExpansionTile(
                    title: Text(
                      isAr ? 'كيف أضيف إعلاناً؟' : 'How to add a listing?',
                    ),
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(
                          isAr
                              ? 'من الشريط السفلي أو لوحة «صفحتي» حسب نوع حسابك، ثم اتبع خطوات الترخيص والتصريح المعروضة.'
                              : 'Use the bottom bar or «My ads» flow depending on your account type, then follow the license and permit steps shown.',
                        ),
                      ),
                    ],
                  ),
                  ExpansionTile(
                    title: Text(
                      isAr ? 'أين سياسات المنصة؟' : 'Where are platform policies?',
                    ),
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(
                          isAr
                              ? 'الإعدادات ← الامتثال والسياسات ← سياسات المنصة (شروط الاستخدام، الخصوصية، الملكية الفكرية، الكوكيز).'
                              : 'Settings → Compliance & policies → Platform policies (tabs).',
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!wrapInScaffold) {
      return _body(context);
    }
    return Scaffold(
      resizeToAvoidBottomInset: false,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        leading: AppPageCloseButton(
          isArabic: isAr,
          onPressed: () => SafeOverlayPop.pop(context),
        ),
        title: Text(isAr ? 'الدعم الفني' : 'Technical support'),
      ),
      body: _body(context),
    );
  }
}
