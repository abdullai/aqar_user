import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/subscription.dart';
import '../services/subscription_service.dart';

/// صفحة باقات الاشتراك (AR/EN).
class SubscriptionPage extends StatefulWidget {
  final String userId;
  final String lang;
  final Color accentColor;

  const SubscriptionPage({
    super.key,
    required this.userId,
    required this.lang,
    this.accentColor = const Color(0xFF2E7D32),
  });

  @override
  State<SubscriptionPage> createState() => _SubscriptionPageState();
}

class _SubscriptionPageState extends State<SubscriptionPage> {
  bool get _isAr => widget.lang == 'ar';

  bool _loading = true;
  bool _busy = false;
  String? _error;

  List<SubscriptionPlan> _plans = const [];
  UserSubscription? _current;
  int _usedListings = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final plans = await SubscriptionService.fetchPlans();
      final sub =
          await SubscriptionService.getCurrentSubscription(widget.userId);
      final used =
          await SubscriptionService.countActiveListings(widget.userId);
      if (!mounted) return;
      setState(() {
        _plans = plans;
        _current = sub;
        _usedListings = used;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
        _plans = SubscriptionService.defaultPlans;
        _current = UserSubscription.free(widget.userId);
      });
    }
  }

  SubscriptionPlan get _currentPlan {
    final id = (_current?.isActive == true)
        ? _current!.planId
        : SubscriptionPlanId.free;
    return SubscriptionService.planById(id);
  }

  Future<void> _subscribe(SubscriptionPlan plan) async {
    if (_busy) return;
    if (widget.userId.trim().isEmpty) {
      _toast(
        _isAr ? 'يلزم تسجيل الدخول أولاً' : 'Please sign in first',
        isError: true,
      );
      return;
    }

    final isSame = _currentPlan.id == plan.id && (_current?.isActive ?? false);
    if (isSame) {
      _toast(_isAr ? 'هذه باقتك الحالية' : 'This is already your plan');
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return Directionality(
          textDirection: _isAr ? TextDirection.rtl : TextDirection.ltr,
          child: AlertDialog(
            title: Text(
              plan.isFree
                  ? (_isAr ? 'الرجوع للباقة المجانية' : 'Switch to Free')
                  : (_isAr
                      ? 'تفعيل باقة ${plan.nameAr}'
                      : 'Activate ${plan.nameEn}'),
            ),
            content: Text(
              plan.isFree
                  ? (_isAr
                      ? 'سيتم إلغاء الباقة المدفوعة والرجوع للباقة المجانية (إعلان واحد).'
                      : 'Your paid plan will be cancelled and you will return to Free (1 listing).')
                  : (_isAr
                      ? 'سيتم تفعيل «${plan.nameAr}» لمدة ${plan.durationDays} يوماً.\nالسعر: ${plan.priceLabel(true)}\n\nملاحظة: بوابة الدفع ستُربط لاحقاً؛ التفعيل الآن تجريبي داخل التطبيق.'
                      : '«${plan.nameEn}» will be activated for ${plan.durationDays} days.\nPrice: ${plan.priceLabel(false)}\n\nNote: Payment gateway will be integrated later; activation is in-app for now.'),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(_isAr ? 'إلغاء' : 'Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(_isAr ? 'تأكيد' : 'Confirm'),
              ),
            ],
          ),
        );
      },
    );

    if (confirm != true) return;

    setState(() => _busy = true);
    try {
      final UserSubscription updated;
      if (plan.isFree) {
        updated = await SubscriptionService.cancelToFree(widget.userId);
      } else {
        updated = await SubscriptionService.requestPlan(
          userId: widget.userId,
          planId: plan.id,
        );
      }
      if (!mounted) return;
      setState(() => _current = updated);
      _toast(
        _isAr
            ? 'تم تفعيل باقة «${plan.nameAr}»'
            : '«${plan.nameEn}» plan activated',
      );
      await _load();
    } catch (e) {
      _toast(
        _isAr ? 'فشل تفعيل الباقة: $e' : 'Failed to activate plan: $e',
        isError: true,
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _toast(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: isError ? Colors.red : widget.accentColor,
          content: Text(msg),
        ),
      );
  }

  String _formatDate(DateTime? dt) {
    if (dt == null) return _isAr ? '—' : '—';
    return DateFormat.yMMMd(_isAr ? 'ar' : 'en').format(dt.toLocal());
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final plan = _currentPlan;
    final max = plan.maxActiveListings;

    return Directionality(
      textDirection: _isAr ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            _isAr ? 'الاشتراك' : 'Subscription',
            style: const TextStyle(fontWeight: FontWeight.w900),
          ),
          actions: [
            IconButton(
              tooltip: _isAr ? 'تحديث' : 'Refresh',
              onPressed: _loading || _busy ? null : _load,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(
                onRefresh: _load,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
                  children: [
                    if (_error != null) ...[
                      _InfoBanner(
                        color: Colors.orange,
                        icon: Icons.info_outline,
                        text: _isAr
                            ? 'تعذر مزامنة الباقات من السحابة؛ يتم عرض الباقات المحلية.'
                            : 'Could not sync plans from cloud; showing built-in plans.',
                      ),
                      const SizedBox(height: 12),
                    ],
                    _CurrentPlanCard(
                      isAr: _isAr,
                      accent: widget.accentColor,
                      plan: plan,
                      subscription: _current ??
                          UserSubscription.free(widget.userId),
                      used: _usedListings,
                      max: max,
                      expiresLabel: _formatDate(_current?.expiresAt),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      _isAr ? 'اختر الباقة المناسبة' : 'Choose a plan',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w900,
                          ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _isAr
                          ? 'زِد عدد إعلاناتك النشطة واستفد من الظهور المميز.'
                          : 'Increase your active listings and unlock featured visibility.',
                      style: TextStyle(
                        color: cs.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 14),
                    ..._plans.map((p) {
                      final isCurrent =
                          p.id == plan.id && (_current?.isActive ?? true);
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _PlanCard(
                          isAr: _isAr,
                          plan: p,
                          accent: widget.accentColor,
                          isCurrent: isCurrent,
                          busy: _busy,
                          onSelect: () => _subscribe(p),
                        ),
                      );
                    }),
                    const SizedBox(height: 8),
                    _InfoBanner(
                      color: cs.primary,
                      icon: Icons.payment_outlined,
                      text: _isAr
                          ? 'بوابة الدفع (مدى/بطاقة) ستُربط لاحقاً. التفعيل الحالي يحدّث حدود الإعلانات داخل التطبيق فوراً.'
                          : 'Payment (Mada/card) will be connected later. Current activation updates listing limits in-app immediately.',
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}

class _CurrentPlanCard extends StatelessWidget {
  final bool isAr;
  final Color accent;
  final SubscriptionPlan plan;
  final UserSubscription subscription;
  final int used;
  final int? max;
  final String expiresLabel;

  const _CurrentPlanCard({
    required this.isAr,
    required this.accent,
    required this.plan,
    required this.subscription,
    required this.used,
    required this.max,
    required this.expiresLabel,
  });

  @override
  Widget build(BuildContext context) {
    final usageText = max == null
        ? (isAr ? '$used إعلان نشط (بلا حد)' : '$used active (unlimited)')
        : (isAr ? '$used / $max إعلانات نشطة' : '$used / $max active listings');

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: LinearGradient(
          colors: [
            accent.withOpacity(0.95),
            accent.withOpacity(0.72),
          ],
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
        ),
        boxShadow: [
          BoxShadow(
            color: accent.withOpacity(0.25),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.18),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  isAr ? 'باقتك الحالية' : 'Current plan',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 12,
                  ),
                ),
              ),
              const Spacer(),
              const Icon(Icons.workspace_premium, color: Colors.white),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            plan.name(isAr),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 26,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            plan.priceLabel(isAr),
            style: TextStyle(
              color: Colors.white.withOpacity(0.92),
              fontWeight: FontWeight.w700,
              fontSize: 15,
            ),
          ),
          const SizedBox(height: 14),
          _softChip(Icons.home_work_outlined, usageText),
          const SizedBox(height: 8),
          if (!plan.isFree)
            _softChip(
              Icons.event_available_outlined,
              isAr ? 'ينتهي: $expiresLabel' : 'Expires: $expiresLabel',
            ),
          if (subscription.status == SubscriptionStatus.expired) ...[
            const SizedBox(height: 8),
            _softChip(
              Icons.warning_amber_rounded,
              isAr
                  ? 'انتهى الاشتراك — تم الرجوع للمجاني'
                  : 'Subscription expired — reverted to Free',
            ),
          ],
          const SizedBox(height: 4),
          Text(
            plan.description(isAr),
            style: TextStyle(
              color: Colors.white.withOpacity(0.88),
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }

  Widget _softChip(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.14),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: Colors.white),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              text,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PlanCard extends StatelessWidget {
  final bool isAr;
  final SubscriptionPlan plan;
  final Color accent;
  final bool isCurrent;
  final bool busy;
  final VoidCallback onSelect;

  const _PlanCard({
    required this.isAr,
    required this.plan,
    required this.accent,
    required this.isCurrent,
    required this.busy,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final borderColor =
        isCurrent || plan.isPopular ? accent : cs.outlineVariant;

    return Material(
      color: cs.surface,
      elevation: plan.isPopular ? 2 : 0,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: (busy || isCurrent) ? null : onSelect,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: borderColor.withOpacity(isCurrent ? 0.95 : 0.55),
              width: isCurrent || plan.isPopular ? 2 : 1,
            ),
          ),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      plan.name(isAr),
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  if (plan.isPopular)
                    Container(
                      margin: const EdgeInsetsDirectional.only(end: 8),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: accent.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        isAr ? 'الأكثر طلباً' : 'Popular',
                        style: TextStyle(
                          color: accent,
                          fontWeight: FontWeight.w800,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  if (isCurrent)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: accent,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        isAr ? 'الحالية' : 'Current',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 11,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                plan.priceLabel(isAr),
                style: TextStyle(
                  color: accent,
                  fontWeight: FontWeight.w900,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                plan.limitLabel(isAr),
                style: TextStyle(
                  color: cs.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                plan.description(isAr),
                style: TextStyle(color: cs.onSurfaceVariant, height: 1.35),
              ),
              const SizedBox(height: 12),
              ...plan.features(isAr).map(
                    (f) => Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.check_circle, size: 18, color: accent),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              f,
                              style:
                                  const TextStyle(fontWeight: FontWeight.w600),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: (busy || isCurrent) ? null : onSelect,
                  style: FilledButton.styleFrom(
                    backgroundColor: accent,
                    disabledBackgroundColor: cs.surfaceContainerHighest,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Text(
                    isCurrent
                        ? (isAr ? 'باقتك الحالية' : 'Current plan')
                        : plan.isFree
                            ? (isAr ? 'اختيار المجاني' : 'Choose Free')
                            : (isAr ? 'اشتراك الآن' : 'Subscribe now'),
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InfoBanner extends StatelessWidget {
  final Color color;
  final IconData icon;
  final String text;

  const _InfoBanner({
    required this.color,
    required this.icon,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withOpacity(0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontWeight: FontWeight.w600, height: 1.35),
            ),
          ),
        ],
      ),
    );
  }
}
