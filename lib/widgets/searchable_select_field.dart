import 'package:flutter/material.dart';
import 'package:aqar_user/widgets/aqar_text_field.dart';

/// حقل يبدو كحقل إدخال لكنه يفتح قائمة عمودية مع بحث داخل التمرير.
/// يُستخدم للمناطق/المحافظات/المدن عندما تكون الخيارات كثيرة.
class SearchableSelectField extends StatelessWidget {
  const SearchableSelectField({
    super.key,
    required this.label,
    required this.items,
    required this.selected,
    required this.onSelected,
    required this.isAr,
    this.enabled = true,
    this.allowClear = true,
    this.searchHint,
    this.emptyHint,
    this.onManualEntry,
    this.manualEntryLabel,
  });

  final String label;
  final List<String> items;
  final String? selected;
  final ValueChanged<String?> onSelected;
  final bool isAr;
  final bool enabled;
  final bool allowClear;
  final String? searchHint;
  final String? emptyHint;
  final VoidCallback? onManualEntry;
  final String? manualEntryLabel;

  static String _norm(String s) =>
      s.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

  Future<void> _openSheet(BuildContext context) async {
    if (!enabled) return;
    final cs = Theme.of(context).colorScheme;
    final q = ValueNotifier<String>('');
    final base = List<String>.from(items)..sort();
    try {
      await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.72,
          minChildSize: 0.45,
          maxChildSize: 0.95,
          builder: (ctx, scrollCtrl) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 10),
                  ValueListenableBuilder<String>(
                    valueListenable: q,
                    builder: (context, query, _) {
                      return AqarTextField(
                        autofocus: true,
                        decoration: InputDecoration(
                          hintText: searchHint ??
                              (isAr ? 'بحث…' : 'Search…'),
                          prefixIcon: const Icon(Icons.search, size: 22),
                          suffixIcon: query.isEmpty
                              ? null
                              : IconButton(
                                  icon: const Icon(Icons.clear, size: 20),
                                  onPressed: () => q.value = '',
                                ),
                        ),
                        onChanged: (v) => q.value = v,
                      );
                    },
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: ValueListenableBuilder<String>(
                      valueListenable: q,
                      builder: (context, query, _) {
                        final qq = _norm(query);
                        final filtered = qq.isEmpty
                            ? base
                            : base
                                .where((e) => _norm(e).contains(qq))
                                .toList();
                        if (filtered.isEmpty) {
                          return Center(
                            child: Text(
                              emptyHint ??
                                  (isAr
                                      ? 'لا توجد نتائج'
                                      : 'No matches'),
                              style: TextStyle(color: cs.onSurfaceVariant),
                            ),
                          );
                        }
                        return ListView.builder(
                          controller: scrollCtrl,
                          itemCount: filtered.length,
                          itemBuilder: (c, i) {
                            final e = filtered[i];
                            final sel = selected != null && selected == e;
                            return ListTile(
                              title: Text(e),
                              selected: sel,
                              trailing: sel
                                  ? Icon(Icons.check, color: cs.primary)
                                  : null,
                              onTap: () {
                                Navigator.pop(ctx);
                                onSelected(e);
                              },
                            );
                          },
                        );
                      },
                    ),
                  ),
                  if (allowClear && selected != null && selected!.isNotEmpty)
                    TextButton(
                      onPressed: () {
                        Navigator.pop(ctx);
                        onSelected(null);
                      },
                      child: Text(isAr ? 'مسح الاختيار' : 'Clear selection'),
                    ),
                  if (onManualEntry != null) ...[
                    const Divider(height: 20),
                    OutlinedButton.icon(
                      onPressed: () {
                        Navigator.pop(ctx);
                        onManualEntry!();
                      },
                      icon: const Icon(Icons.edit_note_outlined, size: 20),
                      label: Text(
                        manualEntryLabel ??
                            (isAr
                                ? 'إدخال يدوي (غير موجود في القائمة)'
                                : 'Manual entry (not in list)'),
                      ),
                    ),
                  ],
                ],
              ),
            );
          },
        );
      },
    );
    } finally {
      q.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final display = (selected ?? '').trim();
    return InkWell(
      onTap: enabled ? () => _openSheet(context) : null,
      borderRadius: BorderRadius.circular(12),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          suffixIcon: Icon(
            Icons.arrow_drop_down_rounded,
            color: enabled ? cs.onSurfaceVariant : cs.outline,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.only(top: 2, bottom: 10),
          child: Text(
            display.isEmpty
                ? (isAr ? 'اضغط للاختيار' : 'Tap to choose')
                : display,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: display.isEmpty
                  ? cs.onSurfaceVariant
                  : cs.onSurface,
            ),
          ),
        ),
      ),
    );
  }
}
