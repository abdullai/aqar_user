// ignore_for_file: unused_field

import 'package:flutter/material.dart';
import 'package:aqar_user/core/gestures/app_keyboard_popups.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/subscription/subscription_billing_context.dart';
import '../core/utils/date_helper.dart';
import '../core/utils/profile_greeting_from_row.dart';
import '../core/utils/users_profiles_safe_select.dart';
import '../core/utils/app_money.dart';
import '../core/workflow/app_role_helper.dart';
import '../l10n/app_localizations.dart';
import '../main.dart' show langNotifier;
import '../services/org_team_service.dart';
import '../services/subscription_service.dart';
import '../widgets/aqar_text_field.dart';

/// تجديد فال المعروضة وشراء المقاعد — مكانها تبويب الاشتراكات فقط.
class OrgFalAndSeatsPanel extends StatefulWidget {
  const OrgFalAndSeatsPanel({
    super.key,
    this.accountType,
    this.organizationId,
    this.lang,
    this.onOpenPlans,
  });

  final String? accountType;
  final String? organizationId;
  final String? lang;
  final VoidCallback? onOpenPlans;

  @override
  State<OrgFalAndSeatsPanel> createState() => _OrgFalAndSeatsPanelState();
}

class _OrgFalAndSeatsPanelState extends State<OrgFalAndSeatsPanel> {
  final _svc = OrgTeamService(Supabase.instance.client);
  final _sub = SubscriptionService(Supabase.instance.client);
  bool _busy = false;
  bool _loaded = false;
  bool _showNeedPlanBanner = false;
  bool _hadAnySubscriptionRow = false;
  DateTime? _expiredAtLocal;
  int _members = 0;
  int _limit = 1;
  String _partnerName = '';
  String _entityLabel = '';
  String _resolvedAccountType = '';
  String? _resolvedOrgId;

  bool get _isAr =>
      (widget.lang ?? langNotifier.value).toLowerCase() != 'en';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      await _svc.ensureMyOrgUnit();
      final org = await _svc.orgUnitForOwner();
      final orgId = (widget.organizationId ?? org?['id']?.toString() ?? '')
          .trim();
      _resolvedOrgId = orgId.isEmpty ? null : orgId;

      SubscriptionBillingContext? ctx;
      try {
        ctx = await _sub.resolveBillingContext();
      } catch (_) {}

      final accountType = (widget.accountType ??
              ctx?.accountType ??
              org?['account_type']?.toString() ??
              '')
          .trim();
      _resolvedAccountType = accountType;

      final sub = await _sub.getCurrentSubscription(
        organizationId: orgId.isEmpty ? null : orgId,
      );
      final access = await _sub.hasActiveMarketingSubscriptionAccess(
        organizationId: orgId.isEmpty ? null : orgId,
      );
      final grants = access ||
          SubscriptionService.subscriptionRowGrantsMarketingAccess(sub) ||
          (ctx != null &&
              ctx.ok &&
              (ctx.hasMarketingFeatureAccess ||
                  ctx.hasActivePaidSubscription ||
                  ctx.hasActiveTrial));

      DateTime? expiredAt;
      if (!grants && sub != null) {
        final exclusive = SubscriptionService.subscriptionExclusiveEndUtc(sub);
        if (exclusive != null) {
          expiredAt = exclusive.toLocal().subtract(const Duration(seconds: 1));
        } else {
          expiredAt = DateHelper.tryParse(sub['ends_at'] ?? sub['end_date'])
              ?.toLocal();
        }
      }

      String partner = '';
      String entity = '';
      Map<String, dynamic>? profile;
      final uid = Supabase.instance.client.auth.currentUser?.id;
      if (uid != null && uid.isNotEmpty) {
        profile = await UsersProfilesSafeSelect.fetchProfileById(
          Supabase.instance.client,
          uid,
          columnAttempts: UsersProfilesSafeSelect.structuredLegalNameColumns,
        );
      }
      if (profile != null) {
        partner = (ProfileGreetingFromRow.displayName(profile, isAr: _isAr) ??
                '')
            .trim();
      }
      partner = partner.isNotEmpty
          ? partner
          : (ProfileGreetingFromRow.displayNameFromAuthMetadata(
                    Supabase.instance.client.auth.currentUser?.userMetadata,
                  ) ??
                  '')
              .trim();

      final profileAccountType =
          (profile?['account_type'] ?? '').toString().trim();
      final audienceType =
          accountType.isEmpty ? profileAccountType : accountType;

      entity = SubscriptionService.planAudienceLabel(
        isAr: _isAr,
        accountType: audienceType,
      );
      if (orgId.isNotEmpty) {
        final p = await _svc.publicOrganizationProfile(orgId);
        final orgName = _isAr
            ? '${p?['display_name_ar'] ?? ''}'.trim()
            : '${p?['display_name_en'] ?? ''}'.trim();
        if (orgName.isNotEmpty) entity = orgName;
        if (!mounted) return;
        setState(() {
          _members = int.tryParse('${p?['member_count']}') ?? 0;
          _limit = int.tryParse('${p?['seat_limit']}') ?? 1;
        });
      }

      if (!mounted) return;
      setState(() {
        _loaded = true;
        _showNeedPlanBanner = !grants &&
            AppRoleHelper.isMarketingAccountType(audienceType);
        _hadAnySubscriptionRow = sub != null;
        _expiredAtLocal = expiredAt;
        _partnerName = partner;
        _entityLabel = entity;
        if (orgId.isEmpty) {
          // keep previous seats if no org
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loaded = true);
    }
  }

  void _openPlans() {
    if (widget.onOpenPlans != null) {
      widget.onOpenPlans!();
      return;
    }
  }

  Future<void> _renew() async {
    final t = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    final r = await _svc.renewFalLicense();
    if (!mounted) return;
    setState(() => _busy = false);
    if (r['ok'] == true) {
      final c = '${r['fal_public_code'] ?? ''}';
      await Clipboard.setData(ClipboardData(text: c));
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text(t.orgSetupFalLine(c))));
      await _load();
    } else {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            '${r['error'] ?? (_isAr ? 'تعذر التجديد' : 'Renew failed')}',
          ),
        ),
      );
    }
  }

  Future<void> _buySeats() async {
    final t = AppLocalizations.of(context)!;
    final info = await _sub.getSeatUnitPriceInfo();
    if (!mounted) return;
    if (info['ok'] != true) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _isAr
                ? 'لا يمكن قراءة سعر المقعد — هل لديك اشتراك فعّال؟'
                : 'Cannot read seat price — do you have an active subscription?',
          ),
        ),
      );
      return;
    }
    final seatPriceNum = info['seat_unit_price_sar'];
    final seatPrice = (seatPriceNum is num)
        ? seatPriceNum.toDouble()
        : double.tryParse('$seatPriceNum') ?? 0;
    final disc = int.tryParse('${info['team_member_discount_percent']}') ?? 50;
    final ctrl = TextEditingController(text: '1');
    final ok = await showAppDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t.orgBuySeats),
        content: StatefulBuilder(
          builder: (ctx2, setS) {
            final n = int.tryParse(ctrl.text.trim()) ?? 0;
            final total = (n > 0 ? n : 0) * seatPrice;
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _isAr
                      ? 'سعر العضو الإضافي: ${AppMoney.sarPhrase(seatPrice.toStringAsFixed(0), isAr: true)} (خصم $disc٪ تلقائي)'
                      : 'Seat price: ${AppMoney.formatWithCurrencyCode(seatPrice, isAr: false, maxFractionDigits: 0)} (auto $disc% discount)',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 12),
                AqarTextField(
                  controller: ctrl,
                  keyboardType: TextInputType.number,
                  onChanged: (_) => setS(() {}),
                  decoration: InputDecoration(
                    labelText: _isAr ? 'عدد المقاعد' : 'Number of seats',
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _isAr
                      ? 'الإجمالي: ${AppMoney.sarPhrase(total.toStringAsFixed(0), isAr: true)}'
                      : 'Total: ${AppMoney.formatWithCurrencyCode(total, isAr: false, maxFractionDigits: 0)}',
                ),
              ],
            );
          },
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
    if (ok != true) {
      ctrl.dispose();
      return;
    }
    final n = int.tryParse(ctrl.text.trim()) ?? 0;
    ctrl.dispose();
    if (n <= 0) return;
    setState(() => _busy = true);
    final r = await _sub.purchaseExtraSeatsPriced(extraSeats: n);
    if (!mounted) return;
    setState(() => _busy = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          r['ok'] == true
              ? (_isAr
                  ? 'تم تحديث المقاعد · المبلغ: ${AppMoney.sarPhrase('${r['total_charged_sar']}', isAr: true)}'
                  : 'Seats updated · Total: ${AppMoney.formatWithCurrencyCode(double.tryParse('${r['total_charged_sar']}') ?? 0, isAr: false, maxFractionDigits: 2)}')
              : '${r['error']}',
        ),
      ),
    );
    if (r['ok'] == true) await _load();
  }

  String _bannerBody() {
    final orgish = AppRoleHelper.isOrgEntity(_resolvedAccountType);
    final who = orgish
        ? (_entityLabel.isNotEmpty ? _entityLabel : _partnerName)
        : (_partnerName.isNotEmpty ? _partnerName : _entityLabel);
    final expired = _hadAnySubscriptionRow && _expiredAtLocal != null;
    final when = _expiredAtLocal == null
        ? ''
        : DateHelper.fmtCivilDateTime(_expiredAtLocal!, isAr: _isAr);

    if (_isAr) {
      final greet = who.isEmpty
          ? 'شريكنا العقاري'
          : 'شريكنا العقاري $who';
      if (expired) {
        return orgish
            ? '$greet\nالمنشأة منتهي اشتراكها بتاريخ $when'
            : '$greet\nانتهى اشتراكك بتاريخ $when';
      }
      return orgish
          ? '$greet\nالمنشأة لا يوجد لديها اشتراك'
          : '$greet\nلا يوجد لديك اشتراك في باقة';
    }

    final greet = who.isEmpty
        ? 'Our real estate partner'
        : 'Our real estate partner $who';
    if (expired) {
      return orgish
          ? '$greet\nThe organization subscription expired on $when'
          : '$greet\nYour plan expired on $when';
    }
    return orgish
        ? '$greet\nThe organization has no plan subscription'
        : '$greet\nYou do not have an active plan';
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final renewLabel = _hadAnySubscriptionRow
        ? (_isAr ? 'تجديد الاشتراك' : 'Renew subscription')
        : (_isAr ? 'اشتراك' : 'Subscribe');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_loaded && _showNeedPlanBanner)
          Card(
            color: cs.errorContainer,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.warning_amber_rounded,
                        color: cs.onErrorContainer,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _bannerBody(),
                          style: TextStyle(
                            color: cs.onErrorContainer,
                            fontWeight: FontWeight.w800,
                            height: 1.35,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: _busy ? null : _openPlans,
                    style: FilledButton.styleFrom(
                      backgroundColor: cs.error,
                      foregroundColor: cs.onError,
                      minimumSize: const Size.fromHeight(44),
                    ),
                    child: Text(
                      renewLabel,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                  ),
                ],
              ),
            ),
          ),
        if (_loaded && _showNeedPlanBanner) const SizedBox(height: 8),
        LinearProgressIndicator(value: _limit > 0 ? _members / _limit : null),
        Text(
          _isAr
              ? 'المقاعد المستخدمة: $_members من $_limit'
              : 'Seats used: $_members / $_limit',
          textAlign: TextAlign.end,
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 12),
        FilledButton.tonal(
          onPressed: (_busy || _showNeedPlanBanner) ? null : _renew,
          child: Text(
            t.orgRenewFal,
            textAlign: TextAlign.center,
            maxLines: 2,
          ),
        ),
        const SizedBox(height: 8),
        FilledButton.tonal(
          onPressed: _busy ? null : _buySeats,
          child: Text(
            t.orgBuySeats,
            textAlign: TextAlign.center,
            maxLines: 2,
          ),
        ),
      ],
    );
  }
}
