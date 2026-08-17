// lib/widgets/marketer_policy_notice_card.dart
//
// «بطاقة تنبيه السياسة للمسوّق»: تُعرض بعد تقديم العرض (أو حتّى توقيع العقد)
// بدلاً من زر/حقل «تقديم عرض»، لتُذكِّر المسوّق بالمسار الكامل من العرض إلى
// نشر الإعلان:
//   1) منع التواصل مع المالك حتى الموافقة.
//   2) إنشاء العقد ثم 72 ساعة لاستخراج التصاريح.
//   3) ظهور رقم جوّال المالك للمسوّق فقط داخل تبويب «تصاريح 72 ساعة».
//   4) إدخال رقم الترخيص الإعلاني للتحقق وإلحاق الإعلان بالسوق.
//
// تُستخدم في صفحة تفاصيل العقار وفي ورقة تفاصيل طلب السوق على حدّ سواء.

import 'package:flutter/material.dart';

class MarketerPolicyNoticeCard extends StatefulWidget {
  const MarketerPolicyNoticeCard({
    super.key,
    required this.isAr,
    this.compact = false,
    this.stageHint = MarketerPolicyStage.afterOffer,
  });

  final bool isAr;

  /// عرض مدمج (داخل بطاقات صغيرة) — يُقلِّل الحشو ويُخفي العنوان الفرعي
  /// للحفاظ على ارتفاع البطاقة المضيفة.
  final bool compact;

  /// مرحلة السير الحالية — يُغيّر النص الرئيسي والترتيب البصري للخطوات.
  final MarketerPolicyStage stageHint;

  @override
  State<MarketerPolicyNoticeCard> createState() =>
      _MarketerPolicyNoticeCardState();
}

enum MarketerPolicyStage {
  /// بعد تقديم العرض مباشرة، قبل موافقة المالك.
  afterOffer,

  /// بعد قبول العرض وقبل توقيع العقد.
  contractPending,

  /// أثناء فترة 72 ساعة لاستخراج التصاريح.
  permitWindow,
}

class _MarketerPolicyNoticeCardState extends State<MarketerPolicyNoticeCard>
    with SingleTickerProviderStateMixin {
  bool _expanded = true;

  @override
  Widget build(BuildContext context) {
    final ar = widget.isAr;
    final cs = Theme.of(context).colorScheme;
    final title = ar
        ? 'تنبيه — سياسة التواصل والمسار من العرض إلى النشر'
        : 'Notice — Communication policy & journey from offer to publish';

    final headlineByStage = switch (widget.stageHint) {
      MarketerPolicyStage.afterOffer => ar
          ? 'تم تسجيل عرضك. التواصل المباشر مع المالك مغلق حتى يقبل العرض.'
          : 'Your offer has been recorded. Direct contact with the owner is locked until acceptance.',
      MarketerPolicyStage.contractPending => ar
          ? 'تم قبول عرضك. أكمل خطوات العقد لفتح بيانات التواصل مع المالك.'
          : 'Offer accepted. Complete the contract to unlock owner contact.',
      MarketerPolicyStage.permitWindow => ar
          ? 'لديك 72 ساعة لاستخراج التصاريح ونشر الإعلان من «صفحتي → تصاريح 72 ساعة».'
          : 'You have 72 hours to extract permits and publish from «My Page → Permit 72h».',
    };

    final steps = <_PolicyStep>[
      _PolicyStep(
        index: 1,
        icon: Icons.lock_outline,
        text: ar
            ? 'حسب سياسة الاستخدام: يُمنع التواصل مع المالك المعلن حتى يوافق على العرض المقدّم منك.'
            : 'Per usage policy: direct contact with the advertising owner is blocked until they approve your offer.',
      ),
      _PolicyStep(
        index: 2,
        icon: Icons.assignment_turned_in_outlined,
        text: ar
            ? 'بعد موافقة المالك سيُنشأ عقد بين الطرفين للالتزام بوقت وتاريخ استخراج التصاريح النظامية من الهيئة العامة للعقار.'
            : 'After approval, a contract is created committing both parties to the time and date for issuing the official permits via the General Real Estate Authority (REGA).',
      ),
      _PolicyStep(
        index: 3,
        icon: Icons.phone_in_talk_outlined,
        text: ar
            ? 'بعد التعاقد تستطيع مشاهدة رقم جوّال المالك والتواصل معه داخل التطبيق أو خارجه لإصدار التصاريح الإعلانية من الجهات ذات العلاقة خلال 72 ساعة.'
            : 'Once the contract is signed you can see the owner\'s mobile number and contact them inside or outside the app to issue the listing permits within 72 hours.',
      ),
      _PolicyStep(
        index: 4,
        icon: Icons.verified_user_outlined,
        text: ar
            ? 'بعد استخراج التصاريح، ادخل حسابك وانتقل إلى «صفحتي → التصاريح 72 ساعة». أدخل رقم الترخيص الإعلاني ليتم التحقق آلياً وفورياً من صحته وتطابق البيانات ثم يُنشر الإعلان للسوق ولجميع المستخدمين.'
            : 'After issuing the permits, go to «My Page → Permit 72h» and enter the REGA license number — it will be verified automatically and instantly, then the ad is published to the market for all users.',
      ),
      _PolicyStep(
        index: 5,
        icon: Icons.timer_outlined,
        text: ar
            ? 'في حال مضى أكثر من 72 ساعة دون استخراج تصريح ونشر الإعلان، تنتقل البطاقة تلقائياً إلى تبويب «بدون إجراء» في صفحة المالك.'
            : 'If more than 72 hours elapse without issuing a permit and publishing, the card automatically moves to the owner\'s «No action» tab.',
      ),
    ];

    return Container(
      padding: EdgeInsets.fromLTRB(
        14,
        12,
        14,
        widget.compact ? 10 : 14,
      ),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: AlignmentDirectional.topStart,
          end: AlignmentDirectional.bottomEnd,
          colors: [
            cs.tertiaryContainer.withValues(alpha: 0.55),
            cs.secondaryContainer.withValues(alpha: 0.55),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: cs.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.shield_outlined, color: cs.primary),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    color: cs.onTertiaryContainer,
                    height: 1.3,
                  ),
                ),
              ),
              IconButton(
                tooltip: _expanded
                    ? (ar ? 'إخفاء التفاصيل' : 'Hide details')
                    : (ar ? 'عرض التفاصيل' : 'Show details'),
                visualDensity: VisualDensity.compact,
                onPressed: () => setState(() => _expanded = !_expanded),
                icon: Icon(
                  _expanded
                      ? Icons.keyboard_arrow_up_rounded
                      : Icons.keyboard_arrow_down_rounded,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            headlineByStage,
            style: TextStyle(
              fontWeight: FontWeight.w800,
              color: cs.onSecondaryContainer,
              height: 1.4,
              fontSize: 13.5,
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
            alignment: AlignmentDirectional.topCenter,
            child: !_expanded
                ? const SizedBox.shrink()
                : Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (final s in steps)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: _PolicyStepTile(step: s, isAr: ar),
                          ),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _PolicyStep {
  const _PolicyStep({
    required this.index,
    required this.icon,
    required this.text,
  });

  final int index;
  final IconData icon;
  final String text;
}

class _PolicyStepTile extends StatelessWidget {
  const _PolicyStepTile({required this.step, required this.isAr});

  final _PolicyStep step;
  final bool isAr;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
      decoration: BoxDecoration(
        color: cs.surface.withValues(alpha: 0.78),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 26,
            height: 26,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: cs.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              '${step.index}',
              style: TextStyle(
                color: cs.primary,
                fontWeight: FontWeight.w900,
                fontSize: 12.5,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Icon(step.icon, color: cs.primary, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              step.text,
              style: TextStyle(
                color: cs.onSurface,
                fontWeight: FontWeight.w700,
                height: 1.45,
                fontSize: 12.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
