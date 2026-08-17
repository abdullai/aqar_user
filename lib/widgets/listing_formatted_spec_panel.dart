import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/listing/property_listing_display.dart';
import '../core/listing/property_type_catalog.dart';
import '../core/utils/app_money.dart';
import '../core/utils/display_ids.dart';
import '../models/property.dart';

/// لوحة عرض منسّقة لبيانات الإعلان (عنوان | قيمة) مع نسخ حيث يناسب.
/// تُستخدم داخل الصفحة أو داخل ورقة منبثقة.
class ListingFormattedSpecPanel extends StatelessWidget {
  const ListingFormattedSpecPanel({
    super.key,
    required this.property,
    required this.isAr,
    this.padding = EdgeInsets.zero,
    /// عند true تُخفى كتلة الصك هنا (تُعرض في بطاقة صك مستقلة أعلاه).
    this.omitDeedSection = false,
  });

  final Property property;
  final bool isAr;
  final EdgeInsetsGeometry padding;
  final bool omitDeedSection;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final w = MediaQuery.sizeOf(context).width;
    final twoCol = w >= 960;

    final listingCodeRaw = (property.listingPublicCode ?? '').trim();
    final listingCode = listingCodeRaw.isEmpty
        ? ''
        : DisplayIds.tenDigit(property.listingPublicCode);

    final sections = <Widget>[
      _section(
        context,
        title: isAr ? 'معلومات أساسية' : 'Basic information',
        rows: [
          if (listingCode.isNotEmpty)
            _kv(
              context,
              isAr,
              isAr ? 'رقم الإعلان' : 'Listing number',
              listingCode,
              copyText: listingCode,
            ),
          _kv(
            context,
            isAr,
            isAr ? 'نوع العقار' : 'Property type',
            PropertyTypeCatalog.label(
              property.listingTypeKey.trim().isNotEmpty
                  ? property.listingTypeKey
                  : property.type.name,
              isAr,
            ),
          ),
          _kv(
            context,
            isAr,
            isAr ? 'الغرض' : 'Purpose',
            PropertyListingDisplay.purposeLabel(property, isAr),
          ),
          _kv(
            context,
            isAr,
            isAr ? 'السعر' : 'Price',
            AppMoney.formatWithCurrencyCode(
              property.price,
              isAr: isAr,
              currencyCode: property.currency,
            ),
          ),
          _kv(
            context,
            isAr,
            isAr ? 'المساحة' : 'Area',
            isAr
                ? '${property.area.toStringAsFixed(2)} مترًا مربعًا'
                : '${property.area.toStringAsFixed(2)} m²',
          ),
          if ((property.city).trim().isNotEmpty)
            _kv(
              context,
              isAr,
              isAr ? 'المدينة' : 'City',
              property.city.trim(),
              copyText: property.city.trim(),
            ),
          if ((property.region ?? '').trim().isNotEmpty)
            _kv(
              context,
              isAr,
              isAr ? 'المنطقة' : 'Region',
              property.region!.trim(),
            ),
          if ((property.location ?? '').trim().isNotEmpty)
            _kv(
              context,
              isAr,
              isAr ? 'الحي / الموقع' : 'District / location',
              property.location!.trim(),
            ),
          if ((property.addressLine ?? '').trim().isNotEmpty)
            _kv(
              context,
              isAr,
              isAr ? 'العنوان' : 'Address',
              property.addressLine!.trim(),
            ),
        ],
      ),
      if (!omitDeedSection)
        _section(
          context,
          title: isAr ? 'الصك والملكية' : 'Deed & ownership',
          rows: [
            if ((property.deedNumber ?? '').trim().isNotEmpty)
              _kv(
                context,
                isAr,
                isAr ? 'رقم الصك' : 'Deed number',
                property.deedNumber!.trim(),
                copyText: property.deedNumber!.trim(),
                icon: Icons.description_outlined,
              ),
            if (property.deedDate != null)
              _kv(
                context,
                isAr,
                isAr ? 'تاريخ الصك' : 'Deed date',
                property.deedDate!.toIso8601String().substring(0, 10),
                icon: Icons.event_outlined,
              ),
            if ((property.deedIssuer ?? '').trim().isNotEmpty)
              _kv(
                context,
                isAr,
                isAr ? 'جهة إصدار الصك' : 'Deed issuer',
                property.deedIssuer!.trim(),
                icon: Icons.account_balance_outlined,
              ),
            if ((property.buildingNumber ?? '').trim().isNotEmpty)
              _kv(
                context,
                isAr,
                isAr ? 'رقم المبنى' : 'Building number',
                property.buildingNumber!.trim(),
                icon: Icons.apartment_outlined,
              ),
          ],
        )
      else if ((property.buildingNumber ?? '').trim().isNotEmpty)
        _section(
          context,
          title: isAr ? 'الملكية' : 'Ownership',
          rows: [
            _kv(
              context,
              isAr,
              isAr ? 'رقم المبنى' : 'Building number',
              property.buildingNumber!.trim(),
              icon: Icons.apartment_outlined,
            ),
          ],
        ),
      _section(
        context,
        title: isAr ? 'التفاصيل والمرافق' : 'Details & amenities',
        rows: [
          if (property.bedrooms != null)
            _kv(
              context,
              isAr,
              isAr ? 'غرف النوم' : 'Bedrooms',
              '${property.bedrooms}',
            ),
          if (property.bathrooms != null)
            _kv(
              context,
              isAr,
              isAr ? 'دورات المياه' : 'Bathrooms',
              '${property.bathrooms}',
            ),
          if (property.parkingSpots != null)
            _kv(
              context,
              isAr,
              isAr ? 'مواقف' : 'Parking',
              '${property.parkingSpots}',
            ),
          if (property.furnished != null)
            _kv(
              context,
              isAr,
              isAr ? 'مفروش' : 'Furnished',
              property.furnished == true
                  ? (isAr ? 'نعم' : 'Yes')
                  : (isAr ? 'لا' : 'No'),
            ),
          if (property.floor != null)
            _kv(
              context,
              isAr,
              isAr ? 'الدور' : 'Floor',
              '${property.floor}',
            ),
          if (property.totalFloors != null)
            _kv(
              context,
              isAr,
              isAr ? 'إجمالي الأدوار' : 'Total floors',
              '${property.totalFloors}',
            ),
          if (property.yearBuilt != null)
            _kv(
              context,
              isAr,
              isAr ? 'سنة البناء' : 'Year built',
              '${property.yearBuilt}',
            ),
          ..._amenityRows(context, property, isAr),
        ],
      ),
      _section(
        context,
        title: isAr ? 'الوصف' : 'Description',
        rows: [
          _kv(
            context,
            isAr,
            isAr ? 'نص الوصف' : 'Description text',
            property.description.trim().isEmpty
                ? (isAr ? '—' : '—')
                : property.description.trim(),
            copyText: property.description.trim().isEmpty
                ? null
                : property.description.trim(),
            icon: Icons.notes_rounded,
          ),
        ],
      ),
      if (_snapshotPairs(property, isAr).isNotEmpty)
        _section(
          context,
          title: isAr
              ? 'بيانات الترخيص والهيئة (إن وُجدت)'
              : 'License / authority data',
          rows: _snapshotPairs(property, isAr)
              .map(
                (e) => _kv(
                  context,
                  isAr,
                  e.$1,
                  e.$2,
                  copyText: e.$2,
                ),
              )
              .toList(),
        ),
    ];

    final body = twoCol
        ? Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  children: sections
                      .take((sections.length + 1) ~/ 2)
                      .toList(),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  children: sections.skip((sections.length + 1) ~/ 2).toList(),
                ),
              ),
            ],
          )
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: sections,
          );

    return Padding(
      padding: padding,
      child: DefaultTextStyle.merge(
        style: theme.textTheme.bodyMedium?.copyWith(fontSize: 13),
        child: body,
      ),
    );
  }

  static List<Widget> _amenityRows(
    BuildContext context,
    Property property,
    bool isAr,
  ) {
    final map = property.amenities;
    if (map == null || map.isEmpty) return const [];
    final on = map.entries
        .where((e) => e.value == true)
        .map((e) => e.key.trim())
        .where((k) => k.isNotEmpty)
        .toList();
    if (on.isEmpty) return const [];
    final labels = on
        .map((k) => _amenityLabel(k, isAr))
        .join(isAr ? '، ' : ', ');
    return [
      _kv(
        context,
        isAr,
        isAr ? 'المرافق' : 'Amenities',
        labels,
        icon: Icons.checklist_rtl_rounded,
      ),
    ];
  }

  static String _amenityLabel(String key, bool isAr) {
    switch (key) {
      case 'elevator':
        return isAr ? 'مصعد' : 'Elevator';
      case 'pool':
        return isAr ? 'مسبح' : 'Pool';
      case 'garden':
        return isAr ? 'حديقة' : 'Garden';
      case 'maid_room':
        return isAr ? 'غرفة خادمة' : 'Maid room';
      case 'driver_room':
        return isAr ? 'غرفة سائق' : 'Driver room';
      case 'kitchen':
        return isAr ? 'مطبخ' : 'Kitchen';
      case 'ac':
        return isAr ? 'تكييف' : 'AC';
      case 'balcony':
        return isAr ? 'شرفة' : 'Balcony';
      case 'security':
        return isAr ? 'حراسة' : 'Security';
      case 'parking':
        return isAr ? 'موقف' : 'Parking';
      default:
        return key.replaceAll('_', ' ');
    }
  }

  static List<(String, String)> _snapshotPairs(Property p, bool isAr) {
    final snap = p.marketingLicenseSnapshot;
    if (snap == null || snap.isEmpty) return const [];
    const keys = <String>[
      'ad_license_number',
      'fal_license_number',
      'fal_broker_full_name',
      'fal_broker_name',
      'brokerage_name',
      'fal_entity_name',
      'deed_number',
      'plan_number',
      'parcel_number',
      'district',
      'city',
      'region',
    ];
    final labelsAr = <String, String>{
      'ad_license_number': 'رقم ترخيص الإعلان',
      'fal_license_number': 'رقم رخصة الوساطة والتسويق',
      'fal_broker_full_name': 'اسم المسوّق',
      'fal_broker_name': 'اسم المسوّق',
      'brokerage_name': 'اسم المنشأة',
      'fal_entity_name': 'الجهة المرخّصة',
      'deed_number': 'رقم الصك',
      'plan_number': 'رقم المخطط',
      'parcel_number': 'رقم الأرض',
      'district': 'الحي',
      'city': 'المدينة',
      'region': 'المنطقة',
    };
    final labelsEn = <String, String>{
      'ad_license_number': 'Ad license number',
      'fal_license_number': 'FAL marketing license',
      'fal_broker_full_name': 'Marketer name',
      'fal_broker_name': 'Marketer name',
      'brokerage_name': 'Brokerage name',
      'fal_entity_name': 'Licensed entity',
      'deed_number': 'Deed number',
      'plan_number': 'Plan number',
      'parcel_number': 'Parcel number',
      'district': 'District',
      'city': 'City',
      'region': 'Region',
    };
    final labels = isAr ? labelsAr : labelsEn;
    final out = <(String, String)>[];
    for (final k in keys) {
      final v = (snap[k] ?? '').toString().trim();
      if (v.isEmpty) continue;
      out.add((labels[k] ?? k, v));
    }
    return out;
  }

  static Widget _section(
    BuildContext context, {
    required String title,
    required List<Widget> rows,
  }) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: cs.primary.withValues(alpha: 0.45)),
          color: cs.surfaceContainerHighest.withValues(alpha: 0.35),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                title,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w900,
                      color: cs.primary,
                    ),
              ),
              const SizedBox(height: 10),
              ...rows,
            ],
          ),
        ),
      ),
    );
  }

  static Widget _kv(
    BuildContext context,
    bool isAr,
    String label,
    String value, {
    String? copyText,
    IconData? icon,
  }) {
    final cs = Theme.of(context).colorScheme;
    final canCopy =
        (copyText ?? '').trim().isNotEmpty && value.trim().isNotEmpty;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.55)),
          color: cs.surface.withValues(alpha: 0.55),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 8, 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                icon ?? Icons.info_outline_rounded,
                size: 16,
                color: cs.primary,
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 5,
                child: Text(
                  label,
                  maxLines: 2,
                  softWrap: true,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 12.5,
                    height: 1.3,
                    color: cs.onSurfaceVariant,
                    fontFamily: 'Cairo',
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 7,
                child: Text(
                  value,
                  maxLines: 6,
                  softWrap: true,
                  overflow: TextOverflow.ellipsis,
                  textAlign: isAr ? TextAlign.right : TextAlign.left,
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 13,
                    height: 1.35,
                    color: cs.onSurface,
                    fontFamily: 'Cairo',
                  ),
                ),
              ),
              if (canCopy) ...[
                const SizedBox(width: 2),
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () async {
                    await Clipboard.setData(
                      ClipboardData(text: (copyText ?? value).trim()),
                    );
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        behavior: SnackBarBehavior.floating,
                        content: Text(isAr ? 'تم النسخ' : 'Copied'),
                      ),
                    );
                  },
                  child: IconButton(
                    tooltip: isAr ? 'نسخ' : 'Copy',
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints:
                        const BoxConstraints(minWidth: 36, minHeight: 36),
                    icon: Icon(Icons.copy_rounded, size: 16, color: cs.primary),
                    onPressed: () async {
                      await Clipboard.setData(
                        ClipboardData(text: (copyText ?? value).trim()),
                      );
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          behavior: SnackBarBehavior.floating,
                          content: Text(isAr ? 'تم النسخ' : 'Copied'),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
