import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:aqar_user/widgets/aqar_text_field.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/branding/app_branding.dart';
import '../core/compliance/platform_compliance_config.dart';
import '../services/compliance_audit_service.dart';

/// شكوى داخل التطبيق → جدول [regc_user_complaints] + سجل تدقيق (ترحيل 20260515183000).
Future<void> showInAppComplaintDialog(
  BuildContext context, {
  required bool isAr,
}) async {
  final subject = TextEditingController();
  final body = TextEditingController();
  try {
    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text(isAr ? 'شكوى داخل التطبيق' : 'In-app complaint'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AqarTextField(
                  controller: subject,
                  decoration: InputDecoration(
                    labelText: isAr ? 'الموضوع' : 'Subject',
                  ),
                ),
                const SizedBox(height: 12),
                AqarTextField(
                  controller: body,
                  maxLines: 5,
                  decoration: InputDecoration(
                    labelText: isAr ? 'التفاصيل' : 'Details',
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

  const SupportPage({
    super.key,
    required this.userId,
    required this.isAr,
    required this.bankColor,
    this.wrapInScaffold = true,
    this.hideComplaintForm = false,
  });

  Future<void> _openMail(
    BuildContext context, {
    required String email,
    required String subject,
  }) async {
    final u = Uri(
      scheme: 'mailto',
      path: email,
      queryParameters: <String, String>{'subject': subject},
    );
    try {
      if (await canLaunchUrl(u)) {
        await launchUrl(u);
      }
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isAr ? 'تعذر فتح تطبيق البريد' : 'Could not open mail app',
          ),
        ),
      );
    }
  }

  Widget _body(BuildContext context) {
    final support = PlatformComplianceConfig.supportEmail();
    final complaints = PlatformComplianceConfig.complaintsEmail();
    final web = PlatformComplianceConfig.complaintsWebUrl();

    return Padding(
      padding: const EdgeInsets.all(16),
      child: ListView(
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isAr ? 'مركز الدعم الفني' : 'Support Center',
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    isAr
                        ? 'للاستفسارات التقنية والحساب. يُفضّل إرفاق لقطة شاشة ورقم الطلب عند الإنابة عن مشكلة في إعلان أو عقد.'
                        : 'For technical and account issues. Please attach a screenshot and reference IDs when reporting listing or contract problems.',
                  ),
                  const SizedBox(height: 16),
                  ListTile(
                    leading: Icon(Icons.email_outlined, color: bankColor),
                    title: Text(isAr ? 'البريد الإلكتروني' : 'Email'),
                    subtitle: SelectableText(support),
                    onTap: () => _openMail(
                      context,
                      email: support,
                      subject: isAr
                          ? 'دعم فني — ${AppBranding.brandNameAr}'
                          : 'Support — ${AppBranding.brandNameEn}',
                    ),
                  ),
                  ListTile(
                    leading: Icon(Icons.phone_outlined, color: bankColor),
                    title: Text(isAr ? 'الهاتف (يُحدَّث من المشغّل)' : 'Phone (operator)'),
                    subtitle: Text(isAr ? '+966 500 000 000' : '+966 500 000 000'),
                  ),
                  ListTile(
                    leading: Icon(Icons.schedule_outlined, color: bankColor),
                    title: Text(isAr ? 'ساعات الاستجابة' : 'Response hours'),
                    subtitle: Text(isAr ? 'أيام العمل — 9 ص إلى 5 م (توقيت السعودية)' : 'Business days — 9 AM to 5 PM (KSA)'),
                  ),
                  if (userId.isNotEmpty)
                    ListTile(
                      leading: Icon(Icons.badge_outlined, color: bankColor),
                      title: Text(isAr ? 'معرّف المستخدم' : 'User ID'),
                      subtitle: SelectableText(
                        userId,
                        style: const TextStyle(fontSize: 12),
                      ),
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
                  ListTile(
                    leading: Icon(Icons.forward_to_inbox, color: bankColor),
                    title: Text(isAr ? 'بريد الشكاوى' : 'Complaints mailbox'),
                    subtitle: SelectableText(complaints),
                    onTap: () => _openMail(
                      context,
                      email: complaints,
                      subject: isAr
                          ? 'شكوى — ${AppBranding.brandNameAr}'
                          : 'Complaint — ${AppBranding.brandNameEn}',
                    ),
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
      appBar: AppBar(
        title: Text(isAr ? 'الدعم والشكاوى' : 'Support & complaints'),
      ),
      body: _body(context),
    );
  }
}
