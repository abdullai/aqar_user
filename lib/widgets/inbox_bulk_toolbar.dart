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
    this.showArchive = true,
  });

  final bool isAr;
  final int selectedCount;
  final int totalCount;
  final VoidCallback onSelectAll;
  final VoidCallback onClearSelection;
  final VoidCallback onArchive;
  final VoidCallback onDelete;
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

/// زر فرز + أرشيف + قراءة الكل لصناديق الوارد.
class InboxActionsBar extends StatelessWidget {
  const InboxActionsBar({
    super.key,
    required this.isAr,
    required this.sortLabel,
    required this.onSortTap,
    required this.onMarkAllRead,
    this.onToggleArchive,
    this.showArchiveToggle = false,
    this.archiveActive = false,
    this.onToggleSelectMode,
    this.selectMode = false,
  });

  final bool isAr;
  final String sortLabel;
  final VoidCallback onSortTap;
  final VoidCallback onMarkAllRead;
  final VoidCallback? onToggleArchive;
  final bool showArchiveToggle;
  final bool archiveActive;
  final VoidCallback? onToggleSelectMode;
  final bool selectMode;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            TextButton.icon(
              onPressed: onMarkAllRead,
              icon: const Icon(Icons.mark_email_read_outlined, size: 18),
              label: Text(
                isAr ? 'قراءة الكل' : 'Mark all read',
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
              ),
            ),
            TextButton.icon(
              onPressed: onSortTap,
              icon: const Icon(Icons.sort_rounded, size: 18),
              label: Text(
                sortLabel,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                  color: cs.primary,
                ),
              ),
            ),
            if (showArchiveToggle && onToggleArchive != null)
              TextButton.icon(
                onPressed: onToggleArchive,
                icon: Icon(
                  archiveActive ? Icons.inbox : Icons.archive_outlined,
                  size: 18,
                ),
                label: Text(
                  archiveActive
                      ? (isAr ? 'الوارد' : 'Inbox')
                      : (isAr ? 'الأرشيف' : 'Archive'),
                  style:
                      const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                ),
              ),
            if (onToggleSelectMode != null)
              TextButton.icon(
                onPressed: onToggleSelectMode,
                icon: Icon(
                  selectMode ? Icons.close_rounded : Icons.checklist_rounded,
                  size: 18,
                ),
                label: Text(
                  selectMode
                      ? (isAr ? 'إنهاء' : 'Done')
                      : (isAr ? 'تحديد' : 'Select'),
                  style:
                      const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
