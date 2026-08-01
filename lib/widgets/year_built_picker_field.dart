import 'package:flutter/material.dart';
import 'package:aqar_user/widgets/aqar_text_field.dart';

/// اختيار سنة البناء: قائمة قابلة للتمرير + بحث.
/// [maxYear] الافتراضي = السنة الميلادية الحالية (لا تُضاف السنة القادمة قبل رأس السنة).
class YearBuiltPickerField extends StatelessWidget {
  final int? value;
  final ValueChanged<int?> onChanged;
  final bool enabled;
  final bool isAr;
  final int minYear;
  final int maxYear;
  final bool requiredField;

  YearBuiltPickerField({
    super.key,
    required this.value,
    required this.onChanged,
    required this.enabled,
    required this.isAr,
    this.minYear = 1900,
    int? maxYear,
    this.requiredField = false,
  }) : maxYear = maxYear ?? DateTime.now().year;

  Future<void> _openSheet(BuildContext context) async {
    if (!enabled) return;
    final years = List.generate(
      maxYear - minYear + 1,
      (i) => maxYear - i,
    );
    var filter = '';

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModal) {
            final q = filter.trim();
            final filtered = q.isEmpty
                ? years
                : years.where((y) => y.toString().contains(q)).toList();

            return SafeArea(
              child: Padding(
                padding: EdgeInsets.only(
                  left: 16,
                  right: 16,
                  bottom: MediaQuery.paddingOf(ctx).bottom + 12,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      isAr ? 'سنة البناء' : 'Year built',
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 8),
                    AqarTextField(
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        prefixIcon: const Icon(Icons.search),
                        hintText: isAr ? 'بحث عن سنة…' : 'Search year…',
                      ),
                      onChanged: (s) => setModal(() => filter = s),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 280,
                      child: filtered.isEmpty
                          ? Center(
                              child: Text(
                                isAr ? 'لا توجد نتيجة' : 'No match',
                              ),
                            )
                          : ListView.separated(
                              itemCount: filtered.length,
                              separatorBuilder: (_, __) =>
                                  const Divider(height: 1),
                              itemBuilder: (_, i) {
                                final y = filtered[i];
                                final sel = value == y;
                                return ListTile(
                                  title: Text(
                                    '$y',
                                    style: TextStyle(
                                      fontWeight: sel
                                          ? FontWeight.w900
                                          : FontWeight.w600,
                                      color: sel
                                          ? Theme.of(ctx).colorScheme.primary
                                          : null,
                                    ),
                                  ),
                                  trailing: sel
                                      ? Icon(
                                          Icons.check_circle,
                                          color: Theme.of(ctx)
                                              .colorScheme
                                              .primary,
                                        )
                                      : null,
                                  onTap: () {
                                    onChanged(y);
                                    Navigator.pop(ctx);
                                  },
                                );
                              },
                            ),
                    ),
                    Row(
                      children: [
                        if (!requiredField)
                          TextButton(
                            onPressed: () {
                              onChanged(null);
                              Navigator.pop(ctx);
                            },
                            child: Text(isAr ? 'بدون سنة' : 'Clear'),
                          ),
                        const Spacer(),
                        TextButton(
                          onPressed: () => Navigator.pop(ctx),
                          child: Text(isAr ? 'إغلاق' : 'Close'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final label = value == null
        ? (requiredField
            ? (isAr ? 'سنة البناء (مطلوب)' : 'Year built (required)')
            : (isAr ? 'سنة البناء (اختياري)' : 'Year built (optional)'))
        : (isAr ? 'سنة البناء: $value' : 'Year built: $value');

    return InkWell(
      onTap: enabled ? () => _openSheet(context) : null,
      borderRadius: BorderRadius.circular(12),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: isAr ? 'سنة البناء' : 'Year built',
          suffixIcon: const Icon(Icons.edit_calendar_outlined),
          errorText: requiredField && value == null && enabled
              ? (isAr ? 'مطلوب' : 'Required')
              : null,
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Text(
            label,
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: enabled ? cs.onSurface : cs.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }
}
