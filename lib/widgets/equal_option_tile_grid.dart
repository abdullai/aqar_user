import 'package:flutter/material.dart';

import '../core/listing/property_type_catalog.dart';

/// شبكة خيارات متساوية العرض/الارتفاع — علامة صح لا تضيّق النص.
class EqualOptionTileGrid extends StatelessWidget {
  const EqualOptionTileGrid({
    super.key,
    required this.children,
    this.columns,
    this.aspectRatio = 2.85,
  });

  final List<Widget> children;
  final int? columns;
  final double aspectRatio;

  static int columnsForWidth(double width) => width >= 340 ? 3 : 2;

  @override
  Widget build(BuildContext context) {
    if (children.isEmpty) return const SizedBox.shrink();
    return LayoutBuilder(
      builder: (context, constraints) {
        final cols = columns ?? columnsForWidth(constraints.maxWidth);
        return GridView.count(
          crossAxisCount: cols.clamp(2, 4),
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          childAspectRatio: aspectRatio,
          children: children,
        );
      },
    );
  }
}

class EqualSelectTile extends StatelessWidget {
  const EqualSelectTile({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.enabled = true,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final on = selected;
    return Material(
      color: on
          ? cs.primary.withValues(alpha: 0.16)
          : cs.surfaceContainerHighest.withValues(alpha: 0.42),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: on ? cs.primary.withValues(alpha: 0.55) : cs.outlineVariant,
          width: on ? 1.4 : 1,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: enabled ? onTap : null,
        excludeFromSemantics: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Row(
            children: [
              Icon(
                on ? Icons.check_circle_rounded : Icons.circle_outlined,
                size: 18,
                color: on ? cs.primary : cs.outline,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontFamily: 'Cairo',
                    fontSize: 12.5,
                    height: 1.1,
                    color: cs.onSurface,
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

/// مربعات مرافق متساوية ومفلترة حسب نوع العقار.
class AmenityEqualSelectGrid extends StatelessWidget {
  const AmenityEqualSelectGrid({
    super.key,
    required this.typeCode,
    required this.values,
    required this.isAr,
    required this.onToggle,
    this.enabled = true,
  });

  final String? typeCode;
  final Map<String, bool> values;
  final bool isAr;
  final void Function(String key, bool selected) onToggle;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final keys = values.keys
        .where((k) =>
            PropertyTypeCatalog.amenityKeyRelevantForType(typeCode, k))
        .toList();
    if (keys.isEmpty) {
      final cs = Theme.of(context).colorScheme;
      return Text(
        isAr
            ? 'لا توجد مرافق إضافية لهذا النوع.'
            : 'No extra amenities for this property type.',
        style: TextStyle(
          color: cs.onSurfaceVariant,
          fontWeight: FontWeight.w700,
          fontSize: 13,
        ),
      );
    }
    return EqualOptionTileGrid(
      children: [
        for (final k in keys)
          EqualSelectTile(
            label: PropertyTypeCatalog.amenityLabel(k, isAr),
            selected: values[k] == true,
            enabled: enabled,
            onTap: () => onToggle(k, values[k] != true),
          ),
      ],
    );
  }
}
