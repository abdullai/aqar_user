import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../screens/in_app_notifications_page.dart';
import '../screens/listing_request_status_page.dart';

/// خطوات مسار المسوّق — دعوة حتى النشر والإشعارات.
Future<void> showMarketingFullScenarioSheet(
  BuildContext context, {
  required String lang,
  /// عند التمرير من سياق طلب محدد: زر يفتح [ListingRequestStatusPage].
  String? linkedRequestId,
}) {
  final isAr = lang.toLowerCase() != 'en';
  String t(String ar, String en) => isAr ? ar : en;

  final steps = <_ScenarioStep>[
    _ScenarioStep(
      icon: Icons.storefront_outlined,
      title: t('السوق العقاري — الدعوة والعرض', 'Real estate market — invite & offer'),
      body: t(
        'من تبويب «السوق العقاري» افتح تفاصيل الإعلان ثم قدّم عرض أتعاب التسويق. يُرسل إشعار للمالك تلقائياً.',
        'From the Real estate market tab, open listing details and submit your marketing fee offer. The owner is notified automatically.',
      ),
    ),
    _ScenarioStep(
      icon: Icons.notifications_active_outlined,
      title: t('إشعار المالك', 'Owner notification'),
      body: t(
        'يصل للمالك تنبيه داخل التطبيق لمراجعة العروض (صفحة «العروض العقارية» على حسابه).',
        'The owner receives an in-app alert to review offers on their side.',
      ),
    ),
    _ScenarioStep(
      icon: Icons.how_to_reg_outlined,
      title: t('قرار المالك: قبول، رفض، أو اعتذار', 'Owner decision: accept, reject, or apology'),
      body: t(
        'عند القبول ينتقل الطلب للتعاقد. عند الرفض قد يُحسب ضمن حدّ المسوّقين حسب السياسة. الاعتذار لا يُحسب كرفض في العدّاد — يصلك إشعاراً من الخادم.',
        'On acceptance, the request moves to contracting. A decline may count toward policy limits. An apology does not count as a decline — the server sends a dedicated notification.',
      ),
    ),
    _ScenarioStep(
      icon: Icons.description_outlined,
      title: t('التعاقد والتوقيع', 'Contracting & signatures'),
      body: t(
        'من تبويب «بانتظار المالك · التعاقد» أنشئ العقد بعد قبول عرضك، تابع المحادثة والتوقيع من شاشة العقد.',
        'Under Awaiting owner · Contracting, create the contract after your offer is accepted; follow chat and signing in the contract flow.',
      ),
    ),
    _ScenarioStep(
      icon: Icons.verified_outlined,
      title: t('تصريح REGA وفال (72 ساعة)', 'REGA & FAL permit (72h)'),
      body: t(
        'من تبويب التصريح: اربط رقم ترخيص الإعلان من منصة الهيئة، ويمكن التحقق من رقم فال. يتوفر بلاغ عدم مطابقة عند اختلاف البيانات (سياسة الخادم).',
        'In the permit tab: link the ad license from the authority portal; FAL verification is available. Use the mismatch report if data does not align (server policy).',
      ),
    ),
    _ScenarioStep(
      icon: Icons.campaign_outlined,
      title: t('النشر والظهور', 'Publishing'),
      body: t(
        'بعد اكتمال التعاقد والتصريح يظهر الإعلان في تبويب المنشور/المحجوز حسب مرحلة الطلب.',
        'After contract and permit steps complete, the listing appears under Published / reserved depending on stage.',
      ),
    ),
    _ScenarioStep(
      icon: Icons.inbox_outlined,
      title: t('صندوق الإشعارات', 'Notification inbox'),
      body: t(
        'كل خطوة مهمة تُرسل إشعاراً داخل التطبيق — افتح صندوق الإشعارات للانتقال السريع للطلب أو العقد.',
        'Key steps generate in-app notifications — open the inbox to jump to the request or contract.',
      ),
    ),
  ];

  final l10n = AppLocalizations.of(context)!;
  return _showScenarioBottomSheet(
    context,
    lang: lang,
    title: l10n.marketerFullScenarioSheetTitle,
    steps: steps,
    linkedRequestId: linkedRequestId,
    l10n: l10n,
  );
}

/// خطوات مسار المعلن — من الطلب حتى النشر والإشعارات.
Future<void> showOwnerMarketingScenarioSheet(
  BuildContext context, {
  required String lang,
  String? linkedRequestId,
}) {
  final isAr = lang.toLowerCase() != 'en';
  String t(String ar, String en) => isAr ? ar : en;

  final steps = <_ScenarioStep>[
    _ScenarioStep(
      icon: Icons.post_add_outlined,
      title: t('طلب التسويق والمعاينة', 'Listing request & preview'),
      body: t(
        'أنشئ طلب تسويق أو أضف إعلانك؛ يظهر للمسوّقين المدعوين أو في السوق حسب إعداداتك.',
        'Create a marketing request or add your listing; it becomes visible to invited marketers or on the market depending on your setup.',
      ),
    ),
    _ScenarioStep(
      icon: Icons.groups_outlined,
      title: t('الدعوات واستقبال العروض', 'Invites & offers'),
      body: t(
        'ادعُ مسوّقين أو استقبل عروضهم. راجع «العروض العقارية» لكل طلب قبل الاختيار.',
        'Invite marketers or receive their offers. Use Real estate offers per request before you choose.',
      ),
    ),
    _ScenarioStep(
      icon: Icons.rule_folder_outlined,
      title: t('قبول، رفض، أو اعتذار', 'Accept, reject, or apologize'),
      body: t(
        'اقبل عرضاً واحداً للمتابعة. الرفض يُحسب ضمن حدّ السياسة؛ الاعتذار يُبلَّغ للمسوّق دون احتساب كرفض في العدّاد.',
        'Accept one offer to proceed. A reject may count toward policy limits; an apology notifies the marketer without counting as a decline in the cap.',
      ),
    ),
    _ScenarioStep(
      icon: Icons.chat_outlined,
      title: t('التعاقد والمحادثة', 'Contract & chat'),
      body: t(
        'بعد القبول: أنشئ/وقّع عقد التسويق عبر محادثة العقد، حتى يكتمل المسار للتصريح.',
        'After acceptance: create and sign the marketing contract via the contract chat until the path is ready for permitting.',
      ),
    ),
    _ScenarioStep(
      icon: Icons.gavel_outlined,
      title: t('REGA والتصريح', 'REGA & permit'),
      body: t(
        'يتابع المسوّق المختار ترخيص الإعلان وفق مهلة 72 ساعة؛ يمكنك مراجعة البيانات وبلاغ عدم مطابقة عند الحاجة.',
        'The selected marketer follows the ad license under the 72h rule; you can review data and file a mismatch report when needed.',
      ),
    ),
    _ScenarioStep(
      icon: Icons.public_outlined,
      title: t('النشر', 'Publishing'),
      body: t(
        'بعد اكتمال الشروط يُنشر الإعلان ويظهر في «إعلاناتي» والرئيسية حسب المرحلة.',
        'When requirements are met, the listing publishes and appears under My ads and Home as appropriate.',
      ),
    ),
    _ScenarioStep(
      icon: Icons.inbox_outlined,
      title: t('صندوق الإشعارات', 'Notifications'),
      body: t(
        'التنبيهات (عروض، عقد، تصريح، نشر…) تصل إلى صندوق الإشعارات مع اختصار للطلب.',
        'Alerts (offers, contract, permit, publish…) land in the inbox with shortcuts to the request.',
      ),
    ),
  ];

  final l10n = AppLocalizations.of(context)!;
  return _showScenarioBottomSheet(
    context,
    lang: lang,
    title: l10n.ownerFullScenarioSheetTitle,
    steps: steps,
    linkedRequestId: linkedRequestId,
    l10n: l10n,
  );
}

Future<void> _showScenarioBottomSheet(
  BuildContext context, {
  required String lang,
  required String title,
  required List<_ScenarioStep> steps,
  required AppLocalizations l10n,
  String? linkedRequestId,
}) {
  final isAr = lang.toLowerCase() != 'en';
  final rid = (linkedRequestId ?? '').trim();

  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) {
      final cs = Theme.of(ctx).colorScheme;
      final bottom = MediaQuery.paddingOf(ctx).bottom;
      final sheetH = MediaQuery.sizeOf(ctx).height * 0.82;
      return SizedBox(
        height: sheetH,
        child: Padding(
          padding: EdgeInsets.fromLTRB(20, 4, 20, 8 + bottom),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 18,
                  height: 1.25,
                ),
                textAlign: isAr ? TextAlign.right : TextAlign.left,
              ),
              const SizedBox(height: 8),
              Text(
                l10n.workflowGuideSheetIntro,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                  height: 1.4,
                  color: cs.onSurfaceVariant,
                ),
                textAlign: isAr ? TextAlign.right : TextAlign.left,
              ),
              const SizedBox(height: 12),
              Expanded(
                child: ListView(
                  children: [
                    for (var i = 0; i < steps.length; i++) ...[
                      _ScenarioStepTile(
                        index: i + 1,
                        step: steps[i],
                        colorScheme: cs,
                        isAr: isAr,
                      ),
                      if (i < steps.length - 1) const SizedBox(height: 10),
                    ],
                  ],
                ),
              ),
              if (rid.isNotEmpty) ...[
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () {
                    Navigator.of(ctx).pop();
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (!context.mounted) return;
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => ListingRequestStatusPage(
                            requestId: rid,
                            lang: lang,
                          ),
                        ),
                      );
                    });
                  },
                  icon: const Icon(Icons.open_in_new_outlined, size: 20),
                  label: Text(l10n.scenarioOpenRequestStatusButton),
                ),
              ],
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: () {
                  Navigator.of(ctx).pop();
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (!context.mounted) return;
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => InAppNotificationsPage(lang: lang),
                      ),
                    );
                  });
                },
                icon: const Icon(Icons.notifications_outlined, size: 20),
                label: Text(l10n.marketerFullScenarioOpenInbox),
              ),
              const SizedBox(height: 4),
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: Text(l10n.marketerFullScenarioUnderstood),
              ),
            ],
          ),
        ),
      );
    },
  );
}

class _ScenarioStep {
  final IconData icon;
  final String title;
  final String body;

  const _ScenarioStep({
    required this.icon,
    required this.title,
    required this.body,
  });
}

class _ScenarioStepTile extends StatelessWidget {
  final int index;
  final _ScenarioStep step;
  final ColorScheme colorScheme;
  final bool isAr;

  const _ScenarioStepTile({
    required this.index,
    required this.step,
    required this.colorScheme,
    required this.isAr,
  });

  @override
  Widget build(BuildContext context) {
    final accent = colorScheme.primary;
    return Material(
      color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: accent.withValues(alpha: 0.12),
              child: Text(
                '$index',
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  color: accent,
                  fontSize: 14,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Icon(step.icon, size: 18, color: accent),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          step.title,
                          style: const TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 14,
                            height: 1.25,
                          ),
                          textAlign: isAr ? TextAlign.right : TextAlign.left,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    step.body,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 12.5,
                      height: 1.4,
                      color: colorScheme.onSurfaceVariant,
                    ),
                    textAlign: isAr ? TextAlign.right : TextAlign.left,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
