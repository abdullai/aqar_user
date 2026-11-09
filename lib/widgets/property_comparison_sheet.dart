import 'package:flutter/material.dart';

import '../core/listing/property_listing_display.dart';
import '../core/utils/app_money.dart';
import '../models/property.dart';

class PropertyComparisonSheet extends StatefulWidget {
  const PropertyComparisonSheet({
    super.key,
    required this.properties,
    required this.isArabic,
  });

  final List<Property> properties;
  final bool isArabic;

  @override
  State<PropertyComparisonSheet> createState() =>
      _PropertyComparisonSheetState();
}

class _PropertyComparisonSheetState extends State<PropertyComparisonSheet> {
  late String _firstId;
  late String _secondId;

  bool get _isArabic => widget.isArabic;

  @override
  void initState() {
    super.initState();
    _firstId = widget.properties.first.id;
    _secondId = widget.properties[1].id;
  }

  Property get _first =>
      widget.properties.firstWhere((property) => property.id == _firstId);

  Property get _second =>
      widget.properties.firstWhere((property) => property.id == _secondId);

  String _propertyName(Property property) {
    final title = property.title.trim();
    final location = [property.location, property.city]
        .whereType<String>()
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .join('، ');
    if (title.isEmpty) return location;
    if (location.isEmpty) return title;
    return '$title · $location';
  }

  String _money(Property property) {
    final amount = _amount(property);
    return AppMoney.formatWithCurrencyCode(
      amount,
      isAr: _isArabic,
      currencyCode: property.currency,
      maxFractionDigits: 0,
    );
  }

  String _number(double value) => AppMoney.formatNumber(
        value,
        isAr: _isArabic,
        maxFractionDigits: 0,
      );

  String _optionalNumber(int? value) =>
      value == null ? _dash : _number(value.toDouble());

  String get _dash => _isArabic ? 'غير متوفر' : 'Not available';

  double _amount(Property property) => property.isAuction
      ? (property.currentBid ?? property.price)
      : property.displayTotalPrice;

  List<({String label, String first, String second})> _facts() {
    final a = _first;
    final b = _second;
    final pricePerMeterA = a.area > 0 ? _amount(a) / a.area : null;
    final pricePerMeterB = b.area > 0 ? _amount(b) / b.area : null;
    return [
      (
        label: _isArabic ? 'السعر الظاهر' : 'Displayed price',
        first: _money(a),
        second: _money(b),
      ),
      (
        label: _isArabic ? 'المساحة' : 'Area',
        first: '${_number(a.area)} ${_isArabic ? 'م²' : 'm²'}',
        second: '${_number(b.area)} ${_isArabic ? 'م²' : 'm²'}',
      ),
      (
        label: _isArabic ? 'السعر لكل م²' : 'Price per m²',
        first: pricePerMeterA == null
            ? _dash
            : AppMoney.formatWithCurrencyCode(
                pricePerMeterA,
                isAr: _isArabic,
                currencyCode: a.currency,
                maxFractionDigits: 0,
              ),
        second: pricePerMeterB == null
            ? _dash
            : AppMoney.formatWithCurrencyCode(
                pricePerMeterB,
                isAr: _isArabic,
                currencyCode: b.currency,
                maxFractionDigits: 0,
              ),
      ),
      (
        label: _isArabic ? 'نوع العقار' : 'Property type',
        first: PropertyListingDisplay.typeLabelForProperty(a, _isArabic),
        second: PropertyListingDisplay.typeLabelForProperty(b, _isArabic),
      ),
      (
        label: _isArabic ? 'المدينة والحي' : 'City and district',
        first: [
          a.city,
          a.location,
        ]
            .whereType<String>()
            .map((v) => v.trim())
            .where((v) => v.isNotEmpty)
            .join('، '),
        second: [
          b.city,
          b.location,
        ]
            .whereType<String>()
            .map((v) => v.trim())
            .where((v) => v.isNotEmpty)
            .join('، '),
      ),
      (
        label: _isArabic ? 'غرف النوم' : 'Bedrooms',
        first: _optionalNumber(a.bedrooms),
        second: _optionalNumber(b.bedrooms),
      ),
      (
        label: _isArabic ? 'دورات المياه' : 'Bathrooms',
        first: _optionalNumber(a.bathrooms),
        second: _optionalNumber(b.bathrooms),
      ),
      (
        label: _isArabic ? 'مؤثث' : 'Furnished',
        first: a.furnished == null
            ? _dash
            : (a.furnished!
                ? (_isArabic ? 'نعم' : 'Yes')
                : (_isArabic ? 'لا' : 'No')),
        second: b.furnished == null
            ? _dash
            : (b.furnished!
                ? (_isArabic ? 'نعم' : 'Yes')
                : (_isArabic ? 'لا' : 'No')),
      ),
      (
        label: _isArabic ? 'سنة البناء' : 'Year built',
        first: _optionalNumber(a.yearBuilt),
        second: _optionalNumber(b.yearBuilt),
      ),
      (
        label: _isArabic ? 'قابل للتفاوض' : 'Negotiable',
        first: a.negotiable
            ? (_isArabic ? 'نعم' : 'Yes')
            : (_isArabic ? 'لا' : 'No'),
        second: b.negotiable
            ? (_isArabic ? 'نعم' : 'Yes')
            : (_isArabic ? 'لا' : 'No'),
      ),
    ];
  }

  Widget _selector({
    required String label,
    required String value,
    required ValueChanged<String?> onChanged,
    required String excludedId,
  }) {
    return DropdownButtonFormField<String>(
      value: value,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: const Icon(Icons.home_work_outlined),
      ),
      items: widget.properties
          .where((property) => property.id != excludedId)
          .map(
            (property) => DropdownMenuItem<String>(
              value: property.id,
              child: Text(
                _propertyName(property),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          )
          .toList(growable: false),
      onChanged: onChanged,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final maxHeight = MediaQuery.sizeOf(context).height * 0.9;
    return SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: Material(
          color: cs.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          clipBehavior: Clip.antiAlias,
          child: SingleChildScrollView(
            padding: const EdgeInsetsDirectional.fromSTEB(18, 12, 18, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 38,
                    height: 4,
                    decoration: BoxDecoration(
                      color: cs.onSurfaceVariant.withValues(alpha: 0.35),
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                ),
                const SizedBox(height: 17),
                Row(
                  children: [
                    Icon(Icons.compare_arrows_rounded, color: cs.primary),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Text(
                        _isArabic ? 'مقارنة العقارات' : 'Compare properties',
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: _isArabic ? 'إغلاق' : 'Close',
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _selector(
                  label: _isArabic ? 'العقار الأول' : 'First property',
                  value: _firstId,
                  excludedId: _secondId,
                  onChanged: (id) {
                    if (id == null) return;
                    setState(() => _firstId = id);
                  },
                ),
                const SizedBox(height: 10),
                _selector(
                  label: _isArabic ? 'العقار الثاني' : 'Second property',
                  value: _secondId,
                  excludedId: _firstId,
                  onChanged: (id) {
                    if (id == null) return;
                    setState(() => _secondId = id);
                  },
                ),
                const SizedBox(height: 18),
                for (final fact in _facts()) ...[
                  _ComparisonRow(
                    label: fact.label,
                    first: fact.first.isEmpty ? _dash : fact.first,
                    second: fact.second.isEmpty ? _dash : fact.second,
                  ),
                  const SizedBox(height: 8),
                ],
                const SizedBox(height: 8),
                Text(
                  _isArabic
                      ? 'المقارنة للمساعدة على اتخاذ القرار؛ تحقّق من تفاصيل الإعلان قبل إتمام أي اتفاق.'
                      : 'This comparison is for guidance. Verify listing details before making a decision.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                    height: 1.45,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ComparisonRow extends StatelessWidget {
  const _ComparisonRow({
    required this.label,
    required this.first,
    required this.second,
  });

  final String label;
  final String first;
  final String second;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.55)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            label,
            style: theme.textTheme.labelLarge?.copyWith(
              color: cs.primary,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _valueTile(context, first)),
              const SizedBox(width: 8),
              Expanded(child: _valueTile(context, second)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _valueTile(BuildContext context, String value) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      constraints: const BoxConstraints(minHeight: 40),
      alignment: AlignmentDirectional.centerStart,
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 8),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(11),
      ),
      child: Text(
        value,
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w800,
            ),
      ),
    );
  }
}
