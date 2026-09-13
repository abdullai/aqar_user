import 'package:flutter/material.dart';

/// شريط أدوات التحديد الجماعي لصناديق الإشعارات/المحادثات.
class InboxBulkToolbar extends StatelessWidget {
  const InboxBulkToolbar({
    super.key,
    required this.isAr,
    required this.selectedCount,
    required this.totalCount,
    required this.onSelectAll,
    required this.onClearSelection,
    required this.onArchive,
    required this.onDelete,
    this.onMarkRead,
    this.showArchive = true,
  });

  final bool isAr;
  final int selectedCount;
  final int totalCount;
  final VoidCallback onSelectAll;
  final VoidCallback onClearSelection;
  final VoidCallback onArchive;
  final VoidCallback onDelete;
  final VoidCallback? onMarkRead;
  final bool showArchive;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final allSelected = totalCount > 0 && selectedCount >= totalCount;

    return Material(
      elevation: 2,
      color: cs.primaryContainer.withValues(alpha: 0.35),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              TextButton.icon(
                onPressed: allSelected ? onClearSelection : onSelectAll,
                icon: Icon(allSelected ? Icons.deselect : Icons.select_all),
                label: Text(
                  allSelected
                      ? (isAr ? 'إلغاء التحديد' : 'Clear')
                      : (isAr ? 'تحديد الكل' : 'Select all'),
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
              if (selectedCount > 0) ...[
                Text(
                  isAr ? '$selectedCount محدّد' : '$selectedCount selected',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: cs.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: 8),
                if (onMarkRead != null)
                  IconButton(
                    tooltip: isAr ? 'كمقروء' : 'Mark read',
                    onPressed: onMarkRead,
                    icon: const Icon(Icons.mark_email_read_outlined),
                  ),
                if (showArchive)
                  IconButton(
                    tooltip: isAr ? 'أرشفة' : 'Archive',
                    onPressed: onArchive,
                    icon: const Icon(Icons.archive_outlined),
                  ),
                IconButton(
                  tooltip: isAr ? 'حذف' : 'Delete',
                  onPressed: onDelete,
                  icon: Icon(Icons.delete_outline, color: cs.error),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
