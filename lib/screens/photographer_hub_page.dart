import 'dart:async';

import 'package:flutter/material.dart';
import 'package:aqar_user/core/gestures/app_keyboard_popups.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/utils/app_money.dart';
import '../core/utils/date_helper.dart';
import '../core/utils/rpc_user_message.dart';
import '../l10n/app_localizations.dart';
import '../services/photographer_service.dart';
import '../widgets/app_logo_loading.dart';
import '../widgets/app_page_close_button.dart';
import '../widgets/aqar_text_field.dart';
import '../widgets/certified_photographer_name.dart';
import 'photographer_deliver_page.dart';
import 'photographer_join_page.dart';

class PhotographerHubPage extends StatefulWidget {
  const PhotographerHubPage({
    super.key,
    required this.lang,
    this.embedAppBar = false,
    this.initialTab = 0,
  });

  final String lang;
  final bool embedAppBar;
  final int initialTab;

  @override
  State<PhotographerHubPage> createState() => _PhotographerHubPageState();
}

class _PhotographerHubPageState extends State<PhotographerHubPage>
    with SingleTickerProviderStateMixin {
  final _svc = PhotographerService(Supabase.instance.client);
  late final TabController _tabs;
  PhotographerProfile? _profile;
  List<PhotoShootRequest> _shots = const [];
  var _loading = true;
  DateTime _calDay = DateTime(
    DateTime.now().year,
    DateTime.now().month,
    DateTime.now().day,
  );
  Timer? _tick;

  bool get _isAr => widget.lang != 'en';

  @override
  void initState() {
    super.initState();
    _tabs = TabController(
      length: 5,
      vsync: this,
      initialIndex: widget.initialTab.clamp(0, 4),
    );
    _tick = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
    _reload();
  }

  @override
  void dispose() {
    _tick?.cancel();
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    setState(() => _loading = true);
    try {
      final p = await _svc.myProfile();
      final shots = p == null
          ? const <PhotoShootRequest>[]
          : await _svc.myShootsAsPhotographer();
      if (!mounted) return;
      setState(() {
        _profile = p;
        _shots = shots;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<PhotoShootRequest> _of(Iterable<String> st) =>
      _shots.where((s) => st.contains(s.status)).toList();

  int get _acceptedToday {
    final n = DateTime.now();
    return _shots.where((s) {
      final a = s.acceptedAt;
      if (a == null) return false;
      final l = a.toLocal();
      return l.year == n.year && l.month == n.month && l.day == n.day;
    }).length;
  }

  String _windowLabel(PhotoShootRequest r, AppLocalizations l10n) {
    final left = r.acceptWindowLeft;
    if (left == null) return '';
    if (left.isNegative) return l10n.photographerAcceptWindowExpired;
    final h = left.inHours;
    final m = left.inMinutes.remainder(60);
    if (h > 0) return l10n.photographerAcceptWindow('${h}h ${m}m');
    return l10n.photographerAcceptWindow('${m}m');
  }

  Future<void> _respond(PhotoShootRequest r, bool accept) async {
    final l10n = AppLocalizations.of(context)!;
    if (r.acceptWindowExpired) {
      await _svc.expireStaleShoots();
      await _reload();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.photographerAcceptWindowExpired)),
      );
      return;
    }
    String? reason;
    if (!accept) {
      final ctrl = TextEditingController();
      final ok = await showAppDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(l10n.photographerDeclineTitle),
          content: AqarTextField(
            controller: ctrl,
            maxLines: 3,
            decoration: InputDecoration(
              labelText: l10n.photographerDeclineReason,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(l10n.photographerDialogCancel),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(l10n.photographerDeclineConfirm),
            ),
          ],
        ),
      );
      if (ok != true) return;
      reason = ctrl.text.trim();
    }
    try {
      await _svc.respond(
        requestId: r.id,
        accept: accept,
        rejectReason: reason,
      );
      await _reload();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(RpcUserMessage.of(e, isAr: _isAr))),
      );
    }
  }

  Future<void> _deliver(PhotoShootRequest r) async {
    final l10n = AppLocalizations.of(context)!;
    if (r.propertyId.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.photographerNeedListing)),
      );
      return;
    }
    final ok = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => PhotographerDeliverPage(
          request: r,
          lang: widget.lang,
        ),
      ),
    );
    if (ok == true) await _reload();
  }

  Future<void> _editCap() async {
    final l10n = AppLocalizations.of(context)!;
    final ctrl = TextEditingController(
      text: '${_profile?.maxAcceptsPerDay ?? 5}',
    );
    final ok = await showAppDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.photographerDailyCapTitle),
        content: AqarTextField(
          controller: ctrl,
          keyboardType: TextInputType.number,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.photographerDialogCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.photographerDialogSave),
          ),
        ],
      ),
    );
    final n = int.tryParse(ctrl.text.trim());
    if (ok != true || n == null) return;
    try {
      await _svc.setDailyCap(n);
      await _reload();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(RpcUserMessage.of(e, isAr: _isAr))),
      );
    }
  }

  Widget _incomingPane(List<PhotoShootRequest> items) {
    final l10n = AppLocalizations.of(context)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
          child: Text(
            l10n.photographerIncomingHint,
            style: TextStyle(
              fontWeight: FontWeight.w700,
              height: 1.35,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        Expanded(child: _list(items, incoming: true)),
      ],
    );
  }

  Widget _list(List<PhotoShootRequest> items, {required bool incoming}) {
    final l10n = AppLocalizations.of(context)!;
    if (items.isEmpty) {
      return Center(child: Text(l10n.photographerEmptyTab));
    }
    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: items.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, i) {
        final r = items[i];
        final window = incoming ? _windowLabel(r, l10n) : '';
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  r.locationText.trim().isEmpty
                      ? l10n.photographerShootFallback
                      : r.locationText,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 4),
                Text(r.shootKinds.join(' · ')),
                if (r.quotedAmountSar != null)
                  Text(
                    '${l10n.photographerQuoteAgreed}: ${AppMoney.sarPhrase(r.quotedAmountSar!.toStringAsFixed(0), isAr: _isAr)}',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                if (r.preferredAt != null)
                  Text(
                    DateHelper.fmtCivilDateTime(
                      r.preferredAt!.toLocal(),
                      isAr: _isAr,
                    ),
                    style: const TextStyle(fontSize: 12),
                  ),
                if (window.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    window,
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      color: r.acceptWindowExpired
                          ? Theme.of(context).colorScheme.error
                          : const Color(0xFF0F766E),
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                if (incoming)
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton(
                          onPressed: r.acceptWindowExpired
                              ? null
                              : () => _respond(r, true),
                          child: Text(l10n.photographerAccept),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton(
                          onPressed: r.acceptWindowExpired
                              ? null
                              : () => _respond(r, false),
                          child: Text(l10n.photographerDecline),
                        ),
                      ),
                    ],
                  )
                else if (r.status == 'accepted' || r.status == 'in_progress')
                  FilledButton.icon(
                    onPressed: () => _deliver(r),
                    icon: const Icon(Icons.cloud_upload_outlined),
                    label: Text(l10n.photographerUploadMedia),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  Widget _calendar() {
    final l10n = AppLocalizations.of(context)!;
    final cap = _profile?.maxAcceptsPerDay ?? 5;
    final left = (cap - _acceptedToday).clamp(0, cap);
    final dayItems = _shots.where((s) {
      final at = s.preferredAt;
      if (at == null) return false;
      if (s.status == 'rejected' || s.status == 'cancelled') return false;
      return _sameDay(at.toLocal(), _calDay);
    }).toList();
    final now = DateTime.now();
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Text(
          l10n.photographerCalendarCapRemaining(left, cap),
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: OutlinedButton.icon(
            onPressed: _editCap,
            icon: const Icon(Icons.tune),
            label: Text(l10n.photographerDailyCapTitle),
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 360,
          child: CalendarDatePicker(
            initialDate: _calDay,
            firstDate: DateTime(now.year - 1),
            lastDate: DateTime(now.year + 2),
            onDateChanged: (d) => setState(
              () => _calDay = DateTime(d.year, d.month, d.day),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          l10n.photographerSessionsOnDay(dayItems.length),
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        if (dayItems.isEmpty)
          Text(l10n.photographerCalendarEmpty)
        else
          ...dayItems.map((r) {
            final t = r.preferredAt == null
                ? ''
                : DateHelper.fmtCivilDateTime(
                    r.preferredAt!.toLocal(),
                    isAr: _isAr,
                  );
            return Card(
              child: ListTile(
                title: Text(
                  r.locationText.trim().isEmpty
                      ? l10n.photographerShootFallback
                      : r.locationText,
                ),
                subtitle: Text('$t · ${r.status}'),
              ),
            );
          }),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    if (_loading && _profile == null && _shots.isEmpty) {
      return const Scaffold(body: Center(child: AppLogoLoading()));
    }
    if (_profile == null) {
      return PhotographerJoinPage(lang: widget.lang);
    }

    final incoming = _of({'pending'});
    final active = _of({'accepted', 'in_progress'});
    final done = _of({'delivered'});

    final tabBar = TabBar(
      controller: _tabs,
      isScrollable: true,
      tabs: [
        Tab(text: l10n.photographerTabIncoming),
        Tab(text: l10n.photographerTabActive),
        Tab(text: l10n.photographerTabDone),
        Tab(text: l10n.photographerTabCalendar),
        Tab(text: l10n.photographerTabPortfolio),
      ],
    );

    final view = TabBarView(
      controller: _tabs,
      physics: const NeverScrollableScrollPhysics(),
      children: [
        _incomingPane(incoming),
        _list(active, incoming: false),
        _list(done, incoming: false),
        _calendar(),
        ListView(
          padding: const EdgeInsets.all(16),
          children: [
            CertifiedPhotographerName(
              name: _profile!.displayName,
              verified: _profile!.isVerified,
            ),
            const SizedBox(height: 8),
            if (_profile!.ratingCount > 0)
              Text(
                l10n.photographerRatingLine(
                  _profile!.ratingAvg.toStringAsFixed(1),
                  _profile!.ratingCount,
                ),
              ),
            if (_profile!.photoRateSar != null)
              Text(
                '${l10n.photographerPhotoRate}: ${AppMoney.sarPhrase(_profile!.photoRateSar!.toStringAsFixed(0), isAr: _isAr)}',
              ),
            const SizedBox(height: 12),
            Text(
              _profile!.portfolio.isEmpty
                  ? l10n.photographerEmptyPortfolio
                  : l10n.photographerFilesCount(_profile!.portfolio.length),
            ),
          ],
        ),
      ],
    );

    final scaffold = Scaffold(
      appBar: widget.embedAppBar
          ? null
          : AppBar(
              automaticallyImplyLeading: false,
              leading: AppPageCloseButton(isArabic: _isAr),
              title: Text(l10n.photographerHubTitle),
              actions: [
                IconButton(
                  tooltip: l10n.photographerDailyCapTitle,
                  onPressed: _editCap,
                  icon: const Icon(Icons.tune),
                ),
              ],
              bottom: tabBar,
            ),
      body: Column(
        children: [
          if (widget.embedAppBar) tabBar,
          Expanded(child: view),
        ],
      ),
    );

    return Directionality(
      textDirection: _isAr ? TextDirection.rtl : TextDirection.ltr,
      child: scaffold,
    );
  }
}
