import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/branding/app_branding.dart';
import '../../core/subscription/plan_display_copy.dart';
import '../../core/config/app_config.dart';
import '../../core/payment/plan_price_resolver.dart';
import '../../core/utils/app_money.dart';
import '../../services/subscription_service.dart';
import '../../widgets/fal_support_whatsapp_row.dart';
import '../../widgets/subscription/subscription_ui_helpers.dart';

/// شاشة تفاصيل الباقة — تعرض الأسعار حسب الفترة التي اختارها المستخدم (شهري/سنوي/مرة واحدة).
class PlanDetailsScreen extends StatelessWidget {
  const PlanDetailsScreen({
    super.key,
    required this.lang,
    required this.plan,
    this.selectedPeriod = 'monthly',
  });

  final String lang;
  final Map<String, dynamic> plan;

  /// `monthly` | `yearly` | `one_time` — من شريحة اختيار الفترة في شاشة الباقات.
  final String selectedPeriod;

  bool get _isAr => lang.toLowerCase() != 'en';

  String get _name => AppBranding.planNameFromRow(plan, isAr: _isAr);

  int? _intOf(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    return int.tryParse('$v');
  }

  double? _doubleOf(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    return double.tryParse('$v');
  }

  String _lim(dynamic v) {
    final n = _intOf(v);
    if (n == null || n <= 0) return _isAr ? 'غير محدود' : 'Unlimited';
    return '$n';
  }

  String _planTierLabel() {
    if (plan['is_trial_plan'] == true) return _isAr ? 'تجريبية' : 'Trial';
    return _name;
  }

  String _planAboutParagraph() =>
      PlanDisplayCopy.aboutParagraph(plan, lang: lang, planName: _name);

  Future<void> _openWhatsapp() async {
    final uri = Uri.parse('https://wa.me/966500229909');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  String _marketOffersValue() =>
      PlanDisplayCopy.marketOffersDetailValue(plan, lang: lang);

  double _autoPayPct() {
    final v = plan['auto_pay_discount_percent'];
    if (v is num && v > 0) return v.toDouble();
    return 10.0;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final resolver = PlanPriceResolver(plan);
    final monthly = resolver.monthly;
    final yearly = resolver.yearly;
    final seatPrice = _doubleOf(plan['seat_unit_price_sar']) ?? (monthly * 0.5);
    final maxMembers = _intOf(plan['max_members']) ?? 0;
    final maxAds = plan['max_ads_per_month'];
    final maxRequests = plan['max_listing_requests'];
    final hasFal = plan['has_fal_license'] == true;
    final hasAnalytics = plan['has_analytics'] == true;
    final hasApi = plan['has_api_access'] == true;
    final hasPriority = plan['has_priority_support'] == true;
    final isTrial = plan['is_trial_plan'] == true;
    final program =
        (plan['plan_program'] ?? 'monthly').toString().trim().toLowerCase();
    final isOneTime = program == 'lifetime_one_time' || selectedPeriod == 'one_time';
    final sortOrder = int.tryParse('${plan['sort_order'] ?? 0}') ?? 0;
    final showFalSupport = SubscriptionService.isMainPlanSortOrder(sortOrder);
    final isComprehensive =
        SubscriptionService.isComprehensivePlanSortOrder(sortOrder);
    final periodLabel =
        SubscriptionUiHelpers.periodChipLabel(isAr: _isAr, period: selectedPeriod);
    final selectedBase = isOneTime
        ? monthly
        : resolver.priceForPeriod(
            selectedPeriod == 'yearly' ? 'yearly' : 'monthly',
          );
    final autoPayPct = _autoPayPct();
    final withAutoPay = (selectedBase * (1 - autoPayPct / 100));

    return Scaffold(
      appBar: AppBar(
        title: Text(_isAr ? 'تفاصيل الباقة' : 'Plan details'),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: AppConfig.maxContentWidth),
          child: ListView(
            padding: const EdgeInsets.all(14),
            children: [
              _header(context, cs, isTrial, periodLabel),
              SubscriptionUiHelpers.section(
                context: context,
                title: _isAr ? 'عن هذه الباقة' : 'About this plan',
                children: [
                  Text(
                    _planAboutParagraph(),
                    style: SubscriptionUiHelpers.denseBody(context),
                  ),
                ],
              ),
              SubscriptionUiHelpers.section(
                context: context,
                title: _isAr
                    ? 'الأسعار (${periodLabel})'
                    : 'Pricing ($periodLabel)',
                children: [
                  if (isOneTime) ...[
                    SubscriptionUiHelpers.priceTableRow(
                      context: context,
                      isAr: _isAr,
                      label: _isAr ? 'دفعة واحدة' : 'One-time payment',
                      amount: monthly,
                      emphasize: true,
                    ),
                    _noteLine(
                      context,
                      _isAr
                          ? 'لا تجديد تلقائي — ينتهي الرصيد عند الاستنفاد.'
                          : 'No auto-renewal — balance ends when used up.',
                    ),
                  ] else if (selectedPeriod == 'yearly' && yearly > 0) ...[
                    SubscriptionUiHelpers.priceTableRow(
                      context: context,
                      isAr: _isAr,
                      label: _isAr ? 'سعر سنوي' : 'Yearly price',
                      amount: yearly,
                      emphasize: true,
                    ),
                    if (monthly > 0)
                      _noteLine(
                        context,
                        _isAr
                            ? 'مقارنة: ${AppMoney.formatWithCurrencyCode(monthly * 12, isAr: _isAr, maxFractionDigits: 0)} شهرياً × 12'
                            : 'Compare: ${AppMoney.formatWithCurrencyCode(monthly * 12, isAr: false, maxFractionDigits: 0)} monthly × 12',
                      ),
                  ] else ...[
                    SubscriptionUiHelpers.priceTableRow(
                      context: context,
                      isAr: _isAr,
                      label: _isAr ? 'سعر شهري' : 'Monthly price',
                      amount: monthly,
                      emphasize: true,
                    ),
                    if (yearly > 0)
                      SubscriptionUiHelpers.priceTableRow(
                        context: context,
                        isAr: _isAr,
                        label: _isAr ? 'سعر سنوي (مرجع)' : 'Yearly price (reference)',
                        amount: yearly,
                      ),
                  ],
                  if (!isTrial && !isOneTime)
                    SubscriptionUiHelpers.priceTableRow(
                      context: context,
                      isAr: _isAr,
                      label: _isAr
                          ? 'مع الدفع التلقائي (−${autoPayPct.toStringAsFixed(0)}%)'
                          : 'With auto-pay (−${autoPayPct.toStringAsFixed(0)}%)',
                      amount: withAutoPay,
                    ),
                  if (!isTrial && !isOneTime && maxMembers > 0)
                    SubscriptionUiHelpers.priceTableRow(
                      context: context,
                      isAr: _isAr,
                      label: _isAr ? 'عضو إضافي / شهرياً' : 'Extra seat / month',
                      amount: seatPrice,
                    ),
                  const SizedBox(height: 6),
                  SubscriptionUiHelpers.legalNote(context: context, isAr: _isAr),
                ],
              ),
              SubscriptionUiHelpers.section(
                context: context,
                title: _isAr ? 'حدود الباقة' : 'Plan limits',
                children: [
                  SubscriptionUiHelpers.tableRow(
                    context: context,
                    label: _isAr ? 'إعلانات / شهر' : 'Listings / month',
                    value: _lim(maxAds),
                  ),
                  SubscriptionUiHelpers.tableRow(
                    context: context,
                    label: _isAr ? 'طلبات من الرئيسية' : 'Home requests',
                    value: _lim(maxRequests),
                  ),
                  SubscriptionUiHelpers.tableRow(
                    context: context,
                    label: _isAr ? 'إتمام الصفقة' : 'Complete deal',
                    value: _marketOffersValue(),
                  ),
                ],
              ),
              SubscriptionUiHelpers.section(
                context: context,
                title: _isAr ? 'ميزات الباقة' : 'Plan features',
                children: [
                  if (showFalSupport && hasFal && !isComprehensive)
                    _check(context, true,
                        _isAr ? 'دعم رخصة فال ضمن الباقة' : 'FAL license support via plan'),
                  if (isComprehensive && sortOrder == 14)
                    _check(
                      context,
                      true,
                      _isAr
                          ? 'رخصة فال اختيارية للفرد'
                          : 'Optional FAL for individuals',
                    ),
                  if (isComprehensive && sortOrder == 4)
                    _check(
                      context,
                      true,
                      _isAr
                          ? 'رخصة فال سارية مطلوبة للتفعيل'
                          : 'Valid FAL required for activation',
                    ),
                  _check(context, hasAnalytics,
                      _isAr ? 'تحليلات السوق' : 'Market analytics'),
                  _check(context, hasApi, _isAr ? 'وصول API' : 'API access'),
                  _check(context, hasPriority,
                      _isAr ? 'دعم ذو أولوية' : 'Priority support'),
                ],
              ),
              if (showFalSupport && !hasFal && !isComprehensive)
                _falContactCard(context, cs),
              if (isComprehensive)
                _comprehensiveFalCard(context, cs, sortOrder),
              SubscriptionUiHelpers.section(
                context: context,
                title: _isAr ? 'كيف تستخدم الباقة' : 'How to use this plan',
                children: _usageLines(context, isTrial),
              ),
              if (!isTrial)
                SubscriptionUiHelpers.section(
                  context: context,
                  title: _isAr ? 'سياسة الاشتراك' : 'Subscription policy',
                  children: [
                    Text(
                      _isAr
                          ? '• حساب واحد — لا إضافة أعضاء\n'
                            '• خصم 10٪ على الشهري مع التجديد التلقائي\n'
                            '• السنوي −20٪ — بدون تجديد تلقائي\n'
                            '• إيقاف التجديد التلقائي قبل نهاية الفترة يتطلب رسوم تكميلية (فرق الخصم)'
                          : '• One account — no extra seats\n'
                            '• 10% off monthly with auto-renew\n'
                            '• Yearly 20% off — no auto-renew\n'
                            '• Disabling auto-renew early requires a penalty (discount difference)',
                      style: SubscriptionUiHelpers.denseBody(context),
                    ),
                  ],
                ),
              SubscriptionUiHelpers.section(
                context: context,
                title: _isAr ? 'مساعدة' : 'Help',
                children: [
                  Text(
                    _isAr
                        ? 'للاستفسار عن الباقة أو رخصة فال — تواصل معنا.'
                        : 'For plan or FAL questions — contact us.',
                    style: SubscriptionUiHelpers.denseBody(context),
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: FilledButton.icon(
                      onPressed: _openWhatsapp,
                      icon: const Icon(Icons.chat_bubble_outline, size: 18),
                      label: Text(
                        _isAr ? 'واتساب · 0500229909' : 'WhatsApp · 0500229909',
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header(
    BuildContext context,
    ColorScheme cs,
    bool isTrial,
    String periodLabel,
  ) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: SubscriptionUiHelpers.sectionDecoration(cs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                isTrial
                    ? Icons.card_giftcard_outlined
                    : Icons.workspace_premium_outlined,
                color: cs.primary,
                size: 22,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${_planTierLabel()} — $_name',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                        color: cs.onSurface,
                      ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '${_isAr ? 'فترة العرض' : 'Billing view'}: $periodLabel',
            style: SubscriptionUiHelpers.denseLabel(context).copyWith(
              color: cs.primary,
              fontSize: 12.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _noteLine(BuildContext context, String text) {
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 2),
      child: Text(
        text,
        style: SubscriptionUiHelpers.denseBody(context).copyWith(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }

  Widget _check(BuildContext context, bool ok, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            ok ? Icons.check_circle_outline : Icons.remove_circle_outline,
            size: 17,
            color: ok ? Colors.green.shade800 : Colors.grey,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(text, style: SubscriptionUiHelpers.denseBody(context)),
          ),
        ],
      ),
    );
  }

  List<Widget> _usageLines(BuildContext context, bool isTrial) {
    final lines = _isAr
        ? <String>[
            'من «صفحتي» انشر إعلاناتك وتابع طلباتك ضمن حدود الباقة.',
            'استقبل عروض المسوقين وتابع مسار الطلب من تبويبات صفحتي.',
            'تواصل مع الأطراف عبر الدردشة داخل التطبيق.',
            if (!isTrial)
              'أدر فريقك من إعدادات المنشأة ضمن عدد المقاعد المسموح.',
            if (isTrial)
              'بعد انتهاء التجربة (٣ أيام) يلزم اشتراك مدفوع للمتابعة.',
          ]
        : <String>[
            'From My Desk, publish listings and track requests within plan limits.',
            'Receive marketer offers and follow workflow stages in My Desk tabs.',
            'Communicate via in-app chat.',
            if (!isTrial)
              'Manage your team from organization settings within seat limits.',
            if (isTrial)
              'After the 3-day trial, a paid subscription is required to continue.',
          ];
    return [
      for (final l in lines)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('• ', style: SubscriptionUiHelpers.denseBody(context)),
              Expanded(
                child: Text(l, style: SubscriptionUiHelpers.denseBody(context)),
              ),
            ],
          ),
        ),
    ];
  }

  Widget _comprehensiveFalCard(
    BuildContext context,
    ColorScheme cs,
    int sortOrder,
  ) {
    final isIndividual = sortOrder == 14;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: SubscriptionUiHelpers.sectionDecoration(cs).copyWith(
        color: cs.tertiaryContainer.withValues(alpha: 0.2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _isAr ? 'رخصة فال (REGA)' : 'FAL license (REGA)',
            style: SubscriptionUiHelpers.denseLabel(context),
          ),
          const SizedBox(height: 4),
          Text(
            isIndividual
                ? (_isAr
                    ? 'للمالك الفرد: رخصة فال اختيارية — يمكن طلبها عبر الدعم.'
                    : 'For individuals: FAL is optional — request via support.')
                : (_isAr
                    ? 'للمسوّق/المكتب: رخصة فال سارية مطلوبة قبل تفعيل الاشتراك.'
                    : 'For marketers/offices: a valid FAL is required before activation.'),
            style: SubscriptionUiHelpers.denseBody(context),
          ),
          const SizedBox(height: 6),
          FalSupportWhatsappRow(isAr: _isAr, inline: false),
        ],
      ),
    );
  }

  Widget _falContactCard(BuildContext context, ColorScheme cs) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: SubscriptionUiHelpers.sectionDecoration(cs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _isAr ? 'رخصة فال (REGA)' : 'FAL license (REGA)',
            style: SubscriptionUiHelpers.denseLabel(context),
          ),
          const SizedBox(height: 4),
          FalSupportWhatsappRow(isAr: _isAr, inline: false),
        ],
      ),
    );
  }
}
