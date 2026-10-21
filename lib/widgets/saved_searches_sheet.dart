import 'package:flutter/material.dart';

import '../services/saved_search_service.dart';

/// قائمة عمليات البحث المحفوظة: تطبيق، تشغيل/إيقاف التنبيه، حذف.
Future<void> showSavedSearchesSheet(
  BuildContext context, {
  required bool arabic,
  required void Function(String query) onApply,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => _SavedSearchesBody(
        arabic: arabic,
        onApply: (q) {
          Navigator.of(ctx).pop();
          onApply(q);
        }),
  );
}

class _SavedSearchesBody extends StatefulWidget {
  const _SavedSearchesBody({required this.arabic, required this.onApply});
  final bool arabic;
  final void Function(String query) onApply;

  @override
  State<_SavedSearchesBody> createState() => _SavedSearchesBodyState();
}

class _SavedSearchesBodyState extends State<_SavedSearchesBody> {
  List<SavedPropertySearch>? _items;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final v = await SavedSearchService.list();
    if (mounted) setState(() => _items = v);
  }

  @override
  Widget build(BuildContext context) {
    final ar = widget.arabic;
    final cs = Theme.of(context).colorScheme;
    final items = _items;
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.75,
        ),
        child: Directionality(
          textDirection: ar ? TextDirection.rtl : TextDirection.ltr,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text(
                  ar ? 'عمليات بحثي المحفوظة' : 'My saved searches',
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              if (items == null)
                const Padding(
                  padding: EdgeInsets.all(32),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (items.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    ar
                        ? 'لا توجد عمليات بحث محفوظة. اكتب بحثك مثل «شقة للإيجار حتى 50 ألف الرياض» ثم اضغط «نبّهني».'
                        : 'No saved searches yet.',
                    style: TextStyle(color: cs.onSurfaceVariant),
                  ),
                )
              else
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                    itemCount: items.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (_, i) {
                      final s = items[i];
                      final parts = s.intent.describe(arabic: ar);
                      return Container(
                        decoration: BoxDecoration(
                          color:
                              cs.surfaceContainerHighest.withValues(alpha: .5),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: cs.outlineVariant.withValues(alpha: .6),
                          ),
                        ),
                        child: ListTile(
                          onTap: () => widget.onApply(s.queryText),
                          title: Text(
                            s.queryText.isEmpty
                                ? parts.join(' · ')
                                : s.queryText,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                          subtitle: parts.isEmpty
                              ? null
                              : Text(parts.join(' · '),
                                  style: const TextStyle(fontSize: 12)),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                tooltip: ar ? 'التنبيه' : 'Alerts',
                                icon: Icon(
                                  s.notify
                                      ? Icons.notifications_active_rounded
                                      : Icons.notifications_off_outlined,
                                  color: s.notify ? cs.primary : null,
                                ),
                                onPressed: () async {
                                  await SavedSearchService.setNotify(
                                      s.id, !s.notify);
                                  _load();
                                },
                              ),
                              IconButton(
                                tooltip: ar ? 'حذف' : 'Delete',
                                icon: const Icon(Icons.delete_outline_rounded),
                                onPressed: () async {
                                  await SavedSearchService.delete(s.id);
                                  _load();
                                },
                              ),
                            ],
                          ),
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
