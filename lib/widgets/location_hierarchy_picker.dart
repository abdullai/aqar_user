// lib/widgets/location_hierarchy_picker.dart
//
// مختار هرمي للمنطقة → المحافظة → المدينة → الحي. يعمل فوق
// [LocationHierarchyService] (التي تقرأ ملفات JSON الموجودة) ويعرض كل مستوى
// كقائمة قابلة للبحث مع «فتات» (breadcrumbs) أعلى الورقة. مدعوم من اليمين
// لليسار تلقائياً وفق [Directionality].
//
// الاستخدام:
// ```dart
// final result = await showLocationHierarchyPicker(
//   context: context,
//   isAr: isAr,
//   initialRegion: ...,
//   initialGovernorate: ...,
//   initialCity: ...,
//   initialDistrict: ...,
//   pickDistrict: true,
// );
// if (result != null) {
//   // result.region, .governorate, .city, .district
// }
// ```

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:aqar_user/widgets/aqar_text_field.dart';

import '../services/location_hierarchy_service.dart';

/// نتيجة الاختيار النهائي من [LocationHierarchyPicker].
class LocationHierarchySelection {
  const LocationHierarchySelection({
    required this.region,
    required this.governorate,
    required this.city,
    this.district,
  });

  final String region;
  final String governorate;
  final String city;
  final String? district;

  bool get hasDistrict =>
      (district ?? '').trim().isNotEmpty;

  @override
  String toString() {
    return [
      region,
      governorate,
      city,
      if (hasDistrict) district!,
    ].join(' › ');
  }
}

Future<LocationHierarchySelection?> showLocationHierarchyPicker({
  required BuildContext context,
  required bool isAr,
  String? initialRegion,
  String? initialGovernorate,
  String? initialCity,
  String? initialDistrict,
  bool pickDistrict = true,
}) {
  return showModalBottomSheet<LocationHierarchySelection?>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    isDismissible: true,
    enableDrag: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
    ),
    builder: (ctx) {
      return LocationHierarchyPicker(
        isAr: isAr,
        initialRegion: initialRegion,
        initialGovernorate: initialGovernorate,
        initialCity: initialCity,
        initialDistrict: initialDistrict,
        pickDistrict: pickDistrict,
      );
    },
  );
}

class LocationHierarchyPicker extends StatefulWidget {
  const LocationHierarchyPicker({
    super.key,
    required this.isAr,
    this.initialRegion,
    this.initialGovernorate,
    this.initialCity,
    this.initialDistrict,
    this.pickDistrict = true,
  });

  final bool isAr;
  final String? initialRegion;
  final String? initialGovernorate;
  final String? initialCity;
  final String? initialDistrict;
  final bool pickDistrict;

  @override
  State<LocationHierarchyPicker> createState() =>
      _LocationHierarchyPickerState();
}

enum _PickerStep { region, governorate, city, district }

class _LocationHierarchyPickerState extends State<LocationHierarchyPicker> {
  late _PickerStep _step;
  String? _region;
  String? _governorate;
  String? _city;
  String? _district;

  bool _loading = false;
  List<String> _items = const [];
  String _searchQuery = '';
  late final TextEditingController _searchCtrl;

  bool get _isAr => widget.isAr;

  @override
  void initState() {
    super.initState();
    _searchCtrl = TextEditingController();
    _region = (widget.initialRegion ?? '').trim().isEmpty
        ? null
        : widget.initialRegion!.trim();
    _governorate = (widget.initialGovernorate ?? '').trim().isEmpty
        ? null
        : widget.initialGovernorate!.trim();
    _city = (widget.initialCity ?? '').trim().isEmpty
        ? null
        : widget.initialCity!.trim();
    _district = (widget.initialDistrict ?? '').trim().isEmpty
        ? null
        : widget.initialDistrict!.trim();

    if (_city != null && widget.pickDistrict) {
      _step = _PickerStep.district;
    } else if (_governorate != null) {
      _step = _PickerStep.city;
    } else if (_region != null) {
      _step = _PickerStep.governorate;
    } else {
      _step = _PickerStep.region;
    }
    _loadCurrentStep();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadCurrentStep() async {
    setState(() {
      _loading = true;
      _items = const [];
      _searchQuery = '';
      _searchCtrl.clear();
    });
    final svc = LocationHierarchyService.instance;
    List<String> items = const [];
    try {
      switch (_step) {
        case _PickerStep.region:
          items = await svc.regions(isAr: _isAr);
          break;
        case _PickerStep.governorate:
          items =
              await svc.governoratesIn(region: _region ?? '', isAr: _isAr);
          break;
        case _PickerStep.city:
          items = await svc.citiesIn(
            region: _region ?? '',
            governorate: _governorate ?? '',
            isAr: _isAr,
          );
          break;
        case _PickerStep.district:
          items = await svc.districtsIn(city: _city ?? '');
          break;
      }
    } catch (_) {
      items = const [];
    }
    if (!mounted) return;
    setState(() {
      _items = items;
      _loading = false;
    });
  }

  void _goTo(_PickerStep next) {
    setState(() => _step = next);
    _loadCurrentStep();
  }

  void _pickItem(String value) {
    switch (_step) {
      case _PickerStep.region:
        _region = value;
        _governorate = null;
        _city = null;
        _district = null;
        _goTo(_PickerStep.governorate);
        break;
      case _PickerStep.governorate:
        _governorate = value;
        _city = null;
        _district = null;
        _goTo(_PickerStep.city);
        break;
      case _PickerStep.city:
        _city = value;
        _district = null;
        if (widget.pickDistrict) {
          _goTo(_PickerStep.district);
        } else {
          _finish();
        }
        break;
      case _PickerStep.district:
        _district = value;
        _finish();
        break;
    }
  }

  /// انتهاء الاختيار — يُرجع الحالة الحالية. حتى لو لم يُكمل المستخدم لمستوى
  /// الحي، نعيد الاختيار جزئياً (مفيد عندما لا توجد أحياء لتلك المدينة).
  void _finish() {
    if ((_region ?? '').isEmpty ||
        (_governorate ?? '').isEmpty ||
        (_city ?? '').isEmpty) {
      Navigator.of(context).pop();
      return;
    }
    Navigator.of(context).pop(
      LocationHierarchySelection(
        region: _region!,
        governorate: _governorate!,
        city: _city!,
        district: (_district ?? '').trim().isEmpty ? null : _district!.trim(),
      ),
    );
  }

  String _stepTitle() {
    switch (_step) {
      case _PickerStep.region:
        return _isAr ? 'اختر المنطقة' : 'Pick a region';
      case _PickerStep.governorate:
        return _isAr ? 'اختر المحافظة' : 'Pick a governorate';
      case _PickerStep.city:
        return _isAr ? 'اختر المدينة' : 'Pick a city';
      case _PickerStep.district:
        return _isAr ? 'اختر الحيّ (اختياري)' : 'Pick a district (optional)';
    }
  }

  IconData _stepIcon() {
    switch (_step) {
      case _PickerStep.region:
        return Icons.public_outlined;
      case _PickerStep.governorate:
        return Icons.account_balance_outlined;
      case _PickerStep.city:
        return Icons.location_city_outlined;
      case _PickerStep.district:
        return Icons.holiday_village_outlined;
    }
  }

  List<String> get _filteredItems {
    final q = _searchQuery.trim().toLowerCase();
    if (q.isEmpty) return _items;
    return _items
        .where((e) => e.toLowerCase().contains(q))
        .toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final td = _isAr ? TextDirection.rtl : TextDirection.ltr;
    final cs = Theme.of(context).colorScheme;
    final h = MediaQuery.sizeOf(context).height;
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;

    return Directionality(
      textDirection: td,
      child: SizedBox(
        height: math.max(h * 0.78, 460),
        child: Padding(
          padding: EdgeInsets.only(bottom: bottomInset),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 12, 8),
                child: Row(
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: cs.primaryContainer.withValues(alpha: 0.6),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(_stepIcon(), color: cs.primary),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _stepTitle(),
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontWeight: FontWeight.w900),
                      ),
                    ),
                    if (_step == _PickerStep.district)
                      TextButton(
                        onPressed: _finish,
                        child: Text(_isAr ? 'تخطّي' : 'Skip'),
                      ),
                    IconButton(
                      tooltip: _isAr ? 'إغلاق' : 'Close',
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
              ),
              _Breadcrumbs(
                isAr: _isAr,
                region: _region,
                governorate: _governorate,
                city: _city,
                district: _district,
                currentStep: _step,
                onJumpToStep: (s) => _goTo(s),
              ),
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: AqarTextField(
                  controller: _searchCtrl,
                  onChanged: (v) => setState(() => _searchQuery = v),
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.search_rounded),
                    hintText: _isAr ? 'ابحث…' : 'Search…',
                    filled: true,
                    fillColor: cs.surfaceContainerHighest.withValues(alpha: 0.4),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
              Expanded(
                child: _loading
                    ? const Center(
                        child: CircularProgressIndicator(strokeWidth: 2.5),
                      )
                    : _filteredItems.isEmpty
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(24),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.search_off_rounded,
                                    color: cs.outline,
                                    size: 56,
                                  ),
                                  const SizedBox(height: 10),
                                  Text(
                                    _step == _PickerStep.district
                                        ? (_isAr
                                            ? 'لا توجد أحياء مسجّلة لهذه المدينة بعد — يمكنك التخطّي.'
                                            : 'No districts on file for this city — you can skip.')
                                        : (_isAr
                                            ? 'لا توجد نتائج مطابقة.'
                                            : 'No matches.'),
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color: cs.onSurfaceVariant,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  if (_step == _PickerStep.district) ...[
                                    const SizedBox(height: 14),
                                    FilledButton.tonalIcon(
                                      onPressed: _finish,
                                      icon: const Icon(Icons.check_rounded),
                                      label: Text(_isAr ? 'استخدم المدينة' : 'Use city'),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.fromLTRB(8, 4, 8, 16),
                            itemCount: _filteredItems.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 2),
                            itemBuilder: (context, i) {
                              final v = _filteredItems[i];
                              final selectedAtStep = (_step ==
                                          _PickerStep.region &&
                                      _region == v) ||
                                  (_step == _PickerStep.governorate &&
                                      _governorate == v) ||
                                  (_step == _PickerStep.city && _city == v) ||
                                  (_step == _PickerStep.district &&
                                      _district == v);
                              return Material(
                                color: selectedAtStep
                                    ? cs.primaryContainer.withValues(alpha: 0.45)
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(12),
                                child: ListTile(
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  leading: CircleAvatar(
                                    backgroundColor: cs.surfaceContainerHighest,
                                    foregroundColor: cs.primary,
                                    radius: 18,
                                    child: Icon(
                                      _stepIcon(),
                                      size: 18,
                                    ),
                                  ),
                                  title: Text(
                                    v,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  trailing: Icon(
                                    _isAr
                                        ? Icons.chevron_left_rounded
                                        : Icons.chevron_right_rounded,
                                    color: cs.outline,
                                  ),
                                  onTap: () => _pickItem(v),
                                ),
                              );
                            },
                          ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Breadcrumbs extends StatelessWidget {
  const _Breadcrumbs({
    required this.isAr,
    required this.region,
    required this.governorate,
    required this.city,
    required this.district,
    required this.currentStep,
    required this.onJumpToStep,
  });

  final bool isAr;
  final String? region;
  final String? governorate;
  final String? city;
  final String? district;
  final _PickerStep currentStep;
  final ValueChanged<_PickerStep> onJumpToStep;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final entries = <_BreadcrumbEntry>[
      _BreadcrumbEntry(
        step: _PickerStep.region,
        label: isAr ? 'المنطقة' : 'Region',
        value: region,
      ),
      _BreadcrumbEntry(
        step: _PickerStep.governorate,
        label: isAr ? 'المحافظة' : 'Governorate',
        value: governorate,
      ),
      _BreadcrumbEntry(
        step: _PickerStep.city,
        label: isAr ? 'المدينة' : 'City',
        value: city,
      ),
      _BreadcrumbEntry(
        step: _PickerStep.district,
        label: isAr ? 'الحيّ' : 'District',
        value: district,
      ),
    ];

    return SizedBox(
      height: 56,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        scrollDirection: Axis.horizontal,
        itemCount: entries.length,
        separatorBuilder: (_, __) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Icon(
            isAr ? Icons.chevron_left_rounded : Icons.chevron_right_rounded,
            color: cs.outline,
            size: 18,
          ),
        ),
        itemBuilder: (context, i) {
          final e = entries[i];
          final selected = currentStep == e.step;
          final hasValue = (e.value ?? '').trim().isNotEmpty;
          final enabled = hasValue || selected || i == 0 ||
              (entries[i - 1].value ?? '').trim().isNotEmpty;
          return InkWell(
            borderRadius: BorderRadius.circular(999),
            onTap: enabled ? () => onJumpToStep(e.step) : null,
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 8,
              ),
              decoration: BoxDecoration(
                color: selected
                    ? cs.primary.withValues(alpha: 0.14)
                    : cs.surfaceContainerHighest.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: selected
                      ? cs.primary.withValues(alpha: 0.5)
                      : cs.outlineVariant.withValues(alpha: 0.4),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    e.label,
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      color: selected ? cs.primary : cs.onSurfaceVariant,
                      fontSize: 11.5,
                    ),
                  ),
                  if (hasValue) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: selected
                            ? cs.primary.withValues(alpha: 0.18)
                            : cs.surface,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        e.value!,
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 11.5,
                          color: cs.onSurface,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _BreadcrumbEntry {
  const _BreadcrumbEntry({
    required this.step,
    required this.label,
    required this.value,
  });

  final _PickerStep step;
  final String label;
  final String? value;
}
