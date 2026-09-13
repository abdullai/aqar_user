import 'package:flutter/material.dart';

import '../core/l10n/locale_content.dart';
import '../core/listing/property_type_catalog.dart';
import '../core/utils/app_money.dart';
import '../l10n/app_localizations.dart';
import '../services/rega_open_indicators_service.dart';

/// مرجع سعر/إيجار من مؤشرات الهيئة المفتوحة (مجمّع حسب المدينة والنوع).
class RegaOfficialBenchCard extends StatefulWidget {
  final bool isAr;
  final String city;
  final String typeCode;
  final bool isRent;

  const RegaOfficialBenchCard({
    super.key,
    required this.isAr,
    required this.city,
    required this.typeCode,
    required this.isRent,
  });

  @override
  State<RegaOfficialBenchCard> createState() => _RegaOfficialBenchCardState();
}

class _RegaOfficialBenchCardState extends State<RegaOfficialBenchCard> {
  RegaOpenIndicatorHit? _hit;
  Map<String, int>? _period;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant RegaOfficialBenchCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.city != widget.city ||
        oldWidget.typeCode != widget.typeCode ||
        oldWidget.isRent != widget.isRent) {
      _resolve();
    }
  }

  Future<void> _load() async {
    await RegaOpenIndicatorsService.instance.ensureLoaded();
    if (!mounted) return;
    _resolve();
  }

  void _resolve() {
    final svc = RegaOpenIndicatorsService.instance;
    setState(() {
      _hit = svc.lookup(
        city: widget.city,
        typeCode: widget.typeCode,
        isRent: widget.isRent,
      );
      _period = widget.isRent ? svc.rentalPeriod() : svc.salesPeriod();
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    final hit = _hit;
    if (hit == null) return const SizedBox.shrink();
    final y = _period?['year'];
    final q = _period?['quarter'];
    final period = (y != null && q != null) ? '$y · Q$q' : '';
    final typeLabel = PropertyTypeCatalog.label(widget.typeCode, widget.isAr);
    final cityLabel = LocaleContent.forUi(hit.cityAr, isAr: widget.isAr);
    String amountLine() {
      if (widget.isRent && hit.avgRent != null) {
        return AppMoney.sarPhrase(
          hit.avgRent!.round().toString(),
          isAr: widget.isAr,
        );
      }
      if (hit.avgM2 != null) {
        return AppMoney.sarPhrase(
          hit.avgM2!.round().toString(),
          isAr: widget.isAr,
        );
      }
      return '—';
    }

    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF0F766E).withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: const Color(0xFF0F766E).withValues(alpha: 0.28),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l10n?.listingOfficialRegaBenchTitle ??
                (widget.isAr
                    ? 'مرجع الهيئة العامة للعقار'
                    : 'REGA official benchmark'),
            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14.5),
          ),
          const SizedBox(height: 4),
          Text(
            widget.isRent
                ? (l10n?.listingOfficialRegaBenchRent(
                      cityLabel,
                      typeLabel,
                      amountLine(),
                      hit.deals,
                      period,
                    ) ??
                    '')
                : (l10n?.listingOfficialRegaBenchSale(
                      cityLabel,
                      typeLabel,
                      amountLine(),
                      hit.deals,
                      period,
                    ) ??
                    ''),
            style: TextStyle(
              fontWeight: FontWeight.w700,
              height: 1.35,
              color: cs.onSurface,
            ),
          ),
        ],
      ),
    );
  }
}
