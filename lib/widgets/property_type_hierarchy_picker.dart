import 'package:flutter/material.dart';

import '../core/listing/property_type_catalog.dart';
import '../core/listing/property_type_custom_registry.dart';

/// اختيار نوع العقار: مجموعة + فرعي + بحث + إضافة نوع مخصص (بدون تكرار بعد التطبيع).
class PropertyTypeHierarchyPicker extends StatefulWidget {
  final String value;
  final ValueChanged<String> onChanged;
  final bool isAr;
  final bool saving;

  const PropertyTypeHierarchyPicker({
    super.key,
    required this.value,
    required this.onChanged,
    required this.isAr,
    required this.saving,
  });

  @override
  State<PropertyTypeHierarchyPicker> createState() =>
      _PropertyTypeHierarchyPickerState();
}

class _PropertyTypeHierarchyPickerState
    extends State<PropertyTypeHierarchyPicker> {
  late String _groupId;
  final _searchCtrl = TextEditingController();
  final _customAr = TextEditingController();
  final _customEn = TextEditingController();
  bool _ready = false;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _groupId = PropertyTypeCatalog.groupIdForCode(widget.value);
    _load();
  }

  Future<void> _load() async {
    await PropertyTypeCustomRegistry.ensureLoaded();
    if (!mounted) return;
    setState(() {
      _ready = true;
      _groupId = PropertyTypeCatalog.groupIdForCode(widget.value);
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _customAr.dispose();
    _customEn.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(PropertyTypeHierarchyPicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) {
      final g = PropertyTypeCatalog.groupIdForCode(widget.value);
      if (g != _groupId) {
        setState(() => _groupId = g);
      }
    }
  }

  String _label(Map<String, String> item) =>
      widget.isAr ? (item['ar'] ?? '') : (item['en'] ?? '');

  bool _itemMatchesSearch(Map<String, String> item) {
    if (_searchQuery.isEmpty) return true;
    final q = _searchQuery.trim().toLowerCase();
    final ar = (item['ar'] ?? '').toLowerCase();
    final en = (item['en'] ?? '').toLowerCase();
    return ar.contains(q) || en.contains(q);
  }

  bool _groupVisible(PropertyTypeGroup g) {
    if (_searchQuery.trim().isEmpty) return true;
    final gl = (widget.isAr ? g.ar : g.en).toLowerCase();
    if (gl.contains(_searchQuery.trim().toLowerCase())) return true;
    final items = PropertyTypeCatalog.entriesForGroupMerged(g.id);
    return items.any(_itemMatchesSearch);
  }

  void _setGroup(String id) {
    if (widget.saving) return;
    if (id == _groupId) return;
    final list = PropertyTypeCatalog.entriesForGroupMerged(id);
    if (list.isEmpty) return;
    final filtered = list.where(_itemMatchesSearch).toList();
    final use = filtered.isNotEmpty ? filtered : list;
    setState(() => _groupId = id);
    widget.onChanged(use.first['code']!);
  }

  Future<void> _addCustom() async {
    if (widget.saving) return;
    await PropertyTypeCustomRegistry.ensureLoaded();
    final ar = PropertyTypeCustomRegistry.normalizeLabel(_customAr.text);
    final en = PropertyTypeCustomRegistry.normalizeLabel(
      _customEn.text.isNotEmpty ? _customEn.text : _customAr.text,
    );
    if (ar.isEmpty && en.isEmpty) return;
    final code = await PropertyTypeCustomRegistry.addCustom(
      labelAr: ar.isNotEmpty ? ar : en,
      labelEn: en.isNotEmpty ? en : ar,
      groupId: _groupId,
    );
    if (!mounted || code == null) return;
    _customAr.clear();
    _customEn.clear();
    setState(() {});
    widget.onChanged(code);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    if (!_ready) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: LinearProgressIndicator(),
      );
    }

    InputDecoration deco(String label) => InputDecoration(labelText: label);

    var items = PropertyTypeCatalog.entriesForGroupMerged(_groupId);
    if (_searchQuery.trim().isNotEmpty) {
      items = items.where(_itemMatchesSearch).toList();
    }

    final current = PropertyTypeCatalog.normalize(widget.value);
    String? dropdownValue;
    if (items.isNotEmpty) {
      final match = items.any(
        (e) => PropertyTypeCatalog.normalize(e['code']) == current,
      );
      dropdownValue = match
          ? widget.value
          : items.first['code']!;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _searchCtrl,
          enabled: !widget.saving,
          onChanged: (v) => setState(() => _searchQuery = v),
          decoration: InputDecoration(
            labelText: widget.isAr
                ? 'بحث في أنواع العقار'
                : 'Search property types',
            prefixIcon: const Icon(Icons.search),
            suffixIcon: _searchQuery.isEmpty
                ? null
                : IconButton(
                    tooltip: widget.isAr ? 'مسح' : 'Clear',
                    onPressed: widget.saving
                        ? null
                        : () {
                            _searchCtrl.clear();
                            setState(() => _searchQuery = '');
                          },
                    icon: const Icon(Icons.clear),
                  ),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          widget.isAr ? 'تصنيف النوع' : 'Type category',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w800,
            color: cs.primary,
          ),
        ),
        const SizedBox(height: 8),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: PropertyTypeCatalog.typeGroups
                .where(_groupVisible)
                .map((g) {
              final sel = _groupId == g.id;
              return Padding(
                padding: const EdgeInsetsDirectional.only(end: 8),
                child: ChoiceChip(
                  label: Text(widget.isAr ? g.ar : g.en),
                  selected: sel,
                  onSelected:
                      widget.saving ? null : (_) => _setGroup(g.id),
                  selectedColor: const Color(0xFF0F766E).withValues(alpha: 0.2),
                  labelStyle: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: sel ? const Color(0xFF0F766E) : cs.onSurface,
                  ),
                ),
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 12),
        if (items.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              widget.isAr
                  ? 'لا نتائج للبحث — امسح البحث أو غيّر التصنيف.'
                  : 'No matches — clear search or switch category.',
              style: TextStyle(
                color: cs.onSurfaceVariant,
                fontWeight: FontWeight.w700,
              ),
            ),
          )
        else
          DropdownButtonFormField<String>(
            value: dropdownValue,
            items: items
                .map(
                  (e) => DropdownMenuItem<String>(
                    value: e['code'],
                    child: Text(_label(e)),
                  ),
                )
                .toList(),
            onChanged: widget.saving
                ? null
                : (v) {
                    if (v != null) widget.onChanged(v);
                  },
            decoration: deco(
              widget.isAr ? 'النوع الفرعي' : 'Subtype',
            ),
          ),
        const SizedBox(height: 14),
        Text(
          widget.isAr
              ? 'نوع غير مُدرج؟ (يُضاف للقائمة بدون تكرار)'
              : 'Custom type (deduplicated)',
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w800,
            color: cs.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: _customAr,
          enabled: !widget.saving,
          textInputAction: TextInputAction.next,
          decoration: InputDecoration(
            labelText: widget.isAr ? 'اسم النوع (عربي)' : 'Type name (Arabic)',
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _customEn,
          enabled: !widget.saving,
          textInputAction: TextInputAction.done,
          decoration: InputDecoration(
            labelText: widget.isAr
                ? 'اسم النوع (إنجليزي — اختياري)'
                : 'Type name (English, optional)',
          ),
        ),
        const SizedBox(height: 8),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: FilledButton.icon(
            onPressed: widget.saving ? null : () => _addCustom(),
            icon: const Icon(Icons.add_circle_outline),
            label: Text(widget.isAr ? 'إضافة للقائمة' : 'Add to list'),
          ),
        ),
      ],
    );
  }
}
