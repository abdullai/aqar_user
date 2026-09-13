import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/gestures/app_keyboard_inset.dart';
import '../../core/gestures/app_keyboard_popups.dart';
import '../../core/payment/checkout_offer.dart';
import '../../core/platform/viewport_scroll_policy.dart';
import '../../core/utils/date_helper.dart';
import '../../l10n/app_localizations.dart';
import '../../widgets/aqar_desktop_scrollbar.dart';

/// نافذة الأكواد المتاحة: أعلى خصماً / الأقرب انتهاءً، جدول مرن، شريط تمرير ذكي.
class CheckoutPromoCodesSheet extends StatefulWidget {
  const CheckoutPromoCodesSheet({
    super.key,
    required this.codes,
    required this.isAr,
    required this.initialSort,
    required this.onSort,
    required this.onUse,
    this.minPercentExclusive = 0,
  });

  final List<CheckoutPromoOption> codes;
  final bool isAr;
  final String initialSort;
  final Future<List<CheckoutPromoOption>> Function(String sort) onSort;
  final ValueChanged<String> onUse;
  final double minPercentExclusive;

  static Future<void> show({
    required BuildContext context,
    required List<CheckoutPromoOption> codes,
    required bool isAr,
    required String initialSort,
    required Future<List<CheckoutPromoOption>> Function(String sort) onSort,
    required ValueChanged<String> onUse,
    double minPercentExclusive = 0,
  }) {
    return showAppDialog<void>(
      context: context,
      builder: (ctx) => CheckoutPromoCodesSheet(
        codes: codes,
        isAr: isAr,
        initialSort: initialSort,
        onSort: onSort,
        onUse: onUse,
        minPercentExclusive: minPercentExclusive,
      ),
    );
  }

  @override
  State<CheckoutPromoCodesSheet> createState() =>
      _CheckoutPromoCodesSheetState();
}

class _CheckoutPromoCodesSheetState extends State<CheckoutPromoCodesSheet> {
  late String _sort;
  late List<CheckoutPromoOption> _codes;
  bool _busy = false;
  final _scroll = ScrollController();

  List<CheckoutPromoOption> _keepBetter(List<CheckoutPromoOption> raw) {
    final min = widget.minPercentExclusive;
    if (min <= 0) return List<CheckoutPromoOption>.from(raw);
    return raw.where((c) => c.percent > min + 0.0001).toList();
  }

  @override
  void initState() {
    super.initState();
    _sort = widget.initialSort;
    _codes = _keepBetter(widget.codes);
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _selectSort(String sort) async {
    if (_busy || _sort == sort) return;
    setState(() {
      _busy = true;
      _sort = sort;
    });
    try {
      final next = await widget.onSort(sort);
      if (!mounted) return;
      setState(() => _codes = _keepBetter(next));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _validLabel(AppLocalizations t, CheckoutPromoOption c) {
    final raw = (c.validTo ?? '').trim();
    if (raw.isEmpty) return t.checkoutPromoAvailable;
    final dt = DateTime.tryParse(raw);
    if (dt == null) return raw;
    return DateHelper.fmtCivilDate(dt.toLocal(), isAr: widget.isAr);
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final maxW = MediaQuery.sizeOf(context).width;
    final vis = AppKeyboardInset.visibleHeightOf(context);
    final compact = ViewportScrollPolicy.isCompactTouchLike(context) ||
        maxW < 520;
    final dialogW = compact ? maxW - 32 : 560.0;
    final listMax = math.max(120.0, math.min(vis * 0.58, vis - 96));

    return AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      title: Text(t.checkoutPromoBrowse),
      content: SizedBox(
        width: dialogW.clamp(260, 560),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: _sortChip(
                    cs: cs,
                    label: t.checkoutPromoSortHighest,
                    selected: _sort == 'highest',
                    onTap: () => unawaited(_selectSort('highest')),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _sortChip(
                    cs: cs,
                    label: t.checkoutPromoSortExpiring,
                    selected: _sort == 'expiring',
                    onTap: () => unawaited(_selectSort('expiring')),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (_busy)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
              )
            else
              ConstrainedBox(
                constraints: BoxConstraints(maxHeight: listMax),
                child: AqarDesktopScrollbar(
                  controller: _scroll,
                  alwaysShowThumb:
                      ViewportScrollPolicy.showPersistentScrollbar(context),
                  child: ListView.separated(
                    controller: _scroll,
                    shrinkWrap: true,
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    itemCount: _codes.length + (compact ? 0 : 1),
                    separatorBuilder: (_, __) => Divider(
                      height: 1,
                      color: cs.outlineVariant.withValues(alpha: 0.6),
                    ),
                    itemBuilder: (context, i) {
                      if (!compact && i == 0) {
                        return _wideHeader(t, cs);
                      }
                      final c = _codes[compact ? i : i - 1];
                      return compact
                          ? _compactRow(t, cs, c)
                          : _wideRow(t, cs, c);
                    },
                  ),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(t.closeLabel),
        ),
      ],
    );
  }

  Widget _sortChip({
    required ColorScheme cs,
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Material(
      color: selected ? cs.primaryContainer : cs.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          alignment: Alignment.center,
          constraints: const BoxConstraints(minHeight: 40),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: selected ? cs.primary : cs.outlineVariant,
            ),
          ),
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 13,
              color: selected ? cs.onPrimaryContainer : cs.onSurface,
            ),
          ),
        ),
      ),
    );
  }

  Widget _wideHeader(AppLocalizations t, ColorScheme cs) {
    final style = TextStyle(
      fontWeight: FontWeight.w800,
      fontSize: 12,
      color: cs.onSurfaceVariant,
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 6, top: 4),
      child: Row(
        children: [
          Expanded(
            flex: 14,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: AlignmentDirectional.centerStart,
              child: Text(t.checkoutPromoCode, maxLines: 1, style: style),
            ),
          ),
          Expanded(
            flex: 8,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(t.checkoutPromoPercentCol, maxLines: 1, style: style),
            ),
          ),
          Expanded(
            flex: 10,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(t.checkoutPromoValidCol, maxLines: 1, style: style),
            ),
          ),
          SizedBox(
            width: 72,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(t.checkoutPromoActionCol, maxLines: 1, style: style),
            ),
          ),
        ],
      ),
    );
  }

  Widget _wideRow(
    AppLocalizations t,
    ColorScheme cs,
    CheckoutPromoOption c,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(
            flex: 14,
            child: Text(
              c.code,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
          Expanded(
            flex: 8,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                c.percentLabel(isAr: widget.isAr),
                maxLines: 1,
                textAlign: TextAlign.center,
              ),
            ),
          ),
          Expanded(
            flex: 10,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                _validLabel(t, c),
                maxLines: 1,
                textAlign: TextAlign.center,
              ),
            ),
          ),
          SizedBox(
            width: 72,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: TextButton(
                onPressed: () {
                  Navigator.pop(context);
                  widget.onUse(c.code);
                },
                child: Text(t.checkoutPromoUse),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _compactRow(
    AppLocalizations t,
    ColorScheme cs,
    CheckoutPromoOption c,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            c.code,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
          ),
          const SizedBox(height: 4),
          Text(
            [
              c.percentLabel(isAr: widget.isAr),
              _validLabel(t, c),
            ].where((e) => e.trim().isNotEmpty).join(' · '),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: cs.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 6),
          FilledButton(
            onPressed: () {
              Navigator.pop(context);
              widget.onUse(c.code);
            },
            child: Text(t.checkoutPromoUse),
          ),
        ],
      ),
    );
  }
}
