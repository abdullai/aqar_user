import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/utils/app_money.dart';
import '../core/utils/display_ids.dart';
import '../core/listing/property_type_catalog.dart';

/// لوحة جداول (عنوان | قيمة) لصف طلب تسويق / معاينة من `listing_requests`.
/// تُظهر الصك والمرافق وكل الحقول المتاحة لنقلها للجهات الرسمية.
class ListingRequestSpecPanel extends StatelessWidget {
  const ListingRequestSpecPanel({
    super.key,
    required this.row,
    required this.isAr,
    this.padding = EdgeInsets.zero,
  });

  final Map<String, dynamic> row;
  final bool isAr;
  final EdgeInsetsGeometry padding;

  Map<String, dynamic> get _merged {
    final out = Map<String, dynamic>.from(row);
    final raw = row['payload_json'] ?? row['request_payload'] ?? row['payload'];
    Map<String, dynamic>? m;
    if (raw is Map) {
      m = Map<String, dynamic>.from(raw);
    } else if (raw is String && raw.trim().startsWith('{')) {
      try {
        final d = jsonDecode(raw);
        if (d is Map) m = Map<String, dynamic>.from(d);
      } catch (_) {}
    }
    if (m != null) {
      m.forEach((k, v) {
        if (v == null) return;
        final s = v.toString().trim();
        if (s.isEmpty || s == 'null') return;
        if (!out.containsKey(k) ||
            (out[k] == null) ||
            out[k].toString().trim().isEmpty) {
          out[k] = v;
        }
      });
    }
    return out;
  }

  String _s(String k) => (_merged[k] ?? '').toString().trim();

  num? _n(String k) {
    final v = _merged[k];
    if (v is num) return v;
    return num.tryParse('$v');
  }

  @override
  Widget build(BuildContext context) {
    final m = _merged;
    final codeRaw = _s('listing_request_public_code').isNotEmpty
        ? _s('listing_request_public_code')
        : (_s('preview_listing_public_code').isNotEmpty
            ? _s('preview_listing_public_code')
            : _s('listing_public_code'));
    final code = codeRaw.length == 10 && RegExp(r'^[0-9]{10}$').hasMatch(codeRaw)
        ? DisplayIds.tenDigit(codeRaw)
        : codeRaw;

    final typeKey = _s('preview_property_type').isNotEmpty
        ? _s('preview_property_type')
        : (_s('property_type').isNotEmpty
            ? _s('property_type')
            : _s('listing_type_key'));
    final purpose = _s('preview_purpose').isNotEmpty
        ? _s('preview_purpose')
        : _s('purpose');
    final price = _n('preview_price') ?? _n('price');
    final area = _n('preview_area') ?? _n('area');
    final deed = _s('deed_number').isNotEmpty
        ? _s('deed_number')
        : _s('preview_deed_number');
    final deedDate = _s('deed_date').isNotEmpty
        ? _s('deed_date')
        : _s('preview_deed_date');
    final deedIssuer = _s('deed_issuer');
    final city = _s('preview_city').isNotEmpty ? _s('preview_city') : _s('city');
    final region =
        _s('preview_region').isNotEmpty ? _s('preview_region') : _s('region');
    final district = _s('preview_district').isNotEmpty
        ? _s('preview_district')
        : (_s('location').isNotEmpty ? _s('location') : _s('district'));
    final address = _s('address_line').isNotEmpty
        ? _s('address_line')
        : _s('preview_address');
    final title =
        _s('preview_title').isNotEmpty ? _s('preview_title') : _s('title');
    final desc = _s('description').isNotEmpty
        ? _s('description')
        : _s('preview_description');

    final amenities = <String>[];
    final am = m['amenities'] ?? m['preview_amenities'];
    if (am is Map) {
      am.forEach((k, v) {
        if (v == true) amenities.add(k.toString());
      });
    } else if (am is List) {
      for (final e in am) {
        amenities.add(e.toString());
      }
    }

    return _GenericSpecPanel(
      isAr: isAr,
      padding: padding,
      sections: [
        (
          isAr ? 'معلومات أساسية' : 'Basic information',
          [
            if (code.isNotEmpty)
              (isAr ? 'رقم الإعلان/الطلب' : 'Listing/request no.', code, code),
            if (title.isNotEmpty)
              (isAr ? 'العنوان' : 'Title', title, null),
            if (typeKey.isNotEmpty)
              (
                isAr ? 'نوع العقار' : 'Property type',
                PropertyTypeCatalog.label(typeKey, isAr),
                null,
              ),
            if (purpose.isNotEmpty)
              (isAr ? 'الغرض' : 'Purpose', purpose, null),
            if (price != null && price > 0)
              (
                isAr ? 'السعر' : 'Price',
                AppMoney.formatWithCurrencyCode(
                  price.toDouble(),
                  isAr: isAr,
                  currencyCode: 'SAR',
                ),
                null,
              ),
            if (area != null && area > 0)
              (
                isAr ? 'المساحة' : 'Area',
                isAr
                    ? '${area.toStringAsFixed(2)} م²'
                    : '${area.toStringAsFixed(2)} m²',
                null,
              ),
          ],
        ),
        (
          isAr ? 'الموقع' : 'Location',
          [
            if (region.isNotEmpty) (isAr ? 'المنطقة' : 'Region', region, null),
            if (city.isNotEmpty) (isAr ? 'المدينة' : 'City', city, null),
            if (district.isNotEmpty)
              (isAr ? 'الحي / الموقع' : 'District', district, null),
            if (address.isNotEmpty)
              (isAr ? 'العنوان' : 'Address', address, null),
          ],
        ),
        (
          isAr ? 'الصك والملكية' : 'Deed & ownership',
          [
            if (deed.isNotEmpty)
              (isAr ? 'رقم الصك' : 'Deed number', deed, deed),
            if (deedDate.isNotEmpty)
              (isAr ? 'تاريخ الصك' : 'Deed date', deedDate, null),
            if (deedIssuer.isNotEmpty)
              (isAr ? 'جهة إصدار الصك' : 'Deed issuer', deedIssuer, null),
            if (_s('building_number').isNotEmpty)
              (
                isAr ? 'رقم المبنى' : 'Building number',
                _s('building_number'),
                null,
              ),
            if (_s('plan_number').isNotEmpty)
              (isAr ? 'رقم المخطط' : 'Plan number', _s('plan_number'), null),
            if (_s('parcel_number').isNotEmpty)
              (isAr ? 'رقم القطعة' : 'Parcel number', _s('parcel_number'), null),
          ],
        ),
        (
          isAr ? 'التفاصيل والمرافق' : 'Details & amenities',
          [
            if (_n('bedrooms') != null)
              (isAr ? 'غرف النوم' : 'Bedrooms', '${_n('bedrooms')}', null),
            if (_n('bathrooms') != null)
              (isAr ? 'دورات المياه' : 'Bathrooms', '${_n('bathrooms')}', null),
            if (_n('parking_spots') != null || _n('parking') != null)
              (
                isAr ? 'مواقف' : 'Parking',
                '${_n('parking_spots') ?? _n('parking')}',
                null,
              ),
            if (amenities.isNotEmpty)
              (
                isAr ? 'المرافق' : 'Amenities',
                amenities.map(_amenityLabel).join(isAr ? '، ' : ', '),
                null,
              ),
            if (desc.isNotEmpty)
              (isAr ? 'الوصف' : 'Description', desc, null),
          ],
        ),
      ],
    );
  }

  String _amenityLabel(String key) {
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
}

class _GenericSpecPanel extends StatelessWidget {
  const _GenericSpecPanel({
    required this.isAr,
    required this.sections,
    this.padding = EdgeInsets.zero,
  });

  final bool isAr;
  final EdgeInsetsGeometry padding;
  final List<(String, List<(String, String, String?)>)> sections;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final visible = sections
        .where((s) => s.$2.any((r) => r.$2.trim().isNotEmpty))
        .toList();
    if (visible.isEmpty) {
      return Padding(
        padding: padding,
        child: Text(
          isAr ? 'لا توجد بيانات تفصيلية بعد.' : 'No detailed data yet.',
          style: TextStyle(
            fontWeight: FontWeight.w700,
            color: cs.onSurfaceVariant,
          ),
        ),
      );
    }
    return Padding(
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final sec in visible) ...[
            Text(
              sec.$1,
              style: TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 14,
                color: cs.primary,
                fontFamily: 'Cairo',
              ),
            ),
            const SizedBox(height: 8),
            DecoratedBox(
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: cs.outlineVariant.withValues(alpha: 0.55),
                ),
              ),
              child: Column(
                children: [
                  for (var i = 0; i < sec.$2.length; i++) ...[
                    if (sec.$2[i].$2.trim().isEmpty)
                      const SizedBox.shrink()
                    else ...[
                      if (i > 0)
                        Divider(
                          height: 1,
                          color: cs.outlineVariant.withValues(alpha: 0.35),
                        ),
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              flex: 2,
                              child: Text(
                                sec.$2[i].$1,
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 12.5,
                                  color: cs.onSurfaceVariant,
                                  fontFamily: 'Cairo',
                                  height: 1.3,
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              flex: 3,
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: Text(
                                      sec.$2[i].$2,
                                      softWrap: true,
                                      style: TextStyle(
                                        fontWeight: FontWeight.w900,
                                        fontSize: 13,
                                        color: cs.onSurface,
                                        fontFamily: 'Cairo',
                                        height: 1.35,
                                      ),
                                    ),
                                  ),
                                  if ((sec.$2[i].$3 ?? '').trim().isNotEmpty)
                                    IconButton(
                                      visualDensity: VisualDensity.compact,
                                      tooltip: isAr ? 'نسخ' : 'Copy',
                                      onPressed: () async {
                                        await Clipboard.setData(
                                          ClipboardData(
                                            text: sec.$2[i].$3!.trim(),
                                          ),
                                        );
                                      },
                                      icon: Icon(
                                        Icons.copy_rounded,
                                        size: 16,
                                        color: cs.primary,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ],
              ),
            ),
            const SizedBox(height: 14),
          ],
        ],
      ),
    );
  }
}
