import 'package:flutter/material.dart';

import 'aqar_text_field.dart';
import 'app_page_close_button.dart';
import 'stable_select_chip.dart';

/// تبويب تصفية أفقي لصندوق الإشعارات/المحادثات.
class InboxFilterTab {
  const InboxFilterTab({
    required this.label,
    required this.selected,
    required this.onTap,
    this.badge = 0,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final int badge;
}

class InboxOverflowAction {
  const InboxOverflowAction({
    required this.value,
    required this.icon,
    required this.label,
  });

  final String value;
  final IconData icon;
  final String label;
}

/// صف واحد: شرائح التصفية + أيقونات (بحث/المزيد) بلا صف أدوات مكرر.
class InboxSurfaceChrome extends StatelessWidget {
  const InboxSurfaceChrome({
    super.key,
    required this.filters,
    this.searchOpen = false,
    this.onToggleSearch,
    this.searchTooltip,
    this.trailing = const [],
    this.overflowActions = const [],
    this.onOverflowSelected,
    this.overflowTooltip,
  });

  final List<InboxFilterTab> filters;
  final bool searchOpen;
  final VoidCallback? onToggleSearch;
  final String? searchTooltip;
  final List<Widget> trailing;
  final List<InboxOverflowAction> overflowActions;
  final ValueChanged<String>? onOverflowSelected;
  final String? overflowTooltip;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: cs.surface,
      child: Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(4, 4, 2, 2),
        child: Row(
          children: [
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsetsDirectional.fromSTEB(4, 0, 4, 0),
                child: Row(
                  children: [
                    for (final tab in filters)
                      Padding(
                        padding: const EdgeInsetsDirectional.only(end: 6),
                        child: StableSelectChip(
                          exclusive: true,
                          showLeadingCheck: false,
                          label: tab.badge > 0
                              ? '${tab.label} (${tab.badge > 99 ? '99+' : tab.badge})'
                              : tab.label,
                          selected: tab.selected,
                          onSelected: (_) => tab.onTap(),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            if (onToggleSearch != null)
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: searchTooltip,
                onPressed: onToggleSearch,
                icon: Icon(
                  searchOpen ? Icons.search_off_rounded : Icons.search_rounded,
                ),
              ),
            ...trailing,
            if (overflowActions.isNotEmpty)
              PopupMenuButton<String>(
                tooltip: overflowTooltip,
                icon: const Icon(Icons.more_vert_rounded),
                onSelected: onOverflowSelected,
                itemBuilder: (ctx) => [
                  for (final a in overflowActions)
                    PopupMenuItem<String>(
                      value: a.value,
                      child: Row(
                        children: [
                          Icon(a.icon, size: 22),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              a.label,
                              style: const TextStyle(fontWeight: FontWeight.w700),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

/// حقل بحث ينزلق فوق شرائح التصفية.
class InboxSearchBar extends StatelessWidget {
  const InboxSearchBar({
    super.key,
    required this.controller,
    required this.hintText,
    required this.onChanged,
    required this.onClose,
    this.closeTooltip,
    this.localeScript,
    this.fieldBuilder,
  });

  final TextEditingController controller;
  final String hintText;
  final ValueChanged<String> onChanged;
  final VoidCallback onClose;
  final String? closeTooltip;
  final Object? localeScript;
  final Widget Function({
    required TextEditingController controller,
    required String hintText,
    required ValueChanged<String> onChanged,
  })? fieldBuilder;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final field = fieldBuilder?.call(
          controller: controller,
          hintText: hintText,
          onChanged: onChanged,
        ) ??
        AqarTextField(
          controller: controller,
          autofocus: true,
          onChanged: onChanged,
          decoration: InputDecoration(
            hintText: hintText,
            prefixIcon: const Icon(Icons.search_rounded),
            isDense: true,
            filled: true,
            fillColor: cs.surfaceContainerHighest.withValues(alpha: 0.45),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide.none,
            ),
          ),
        );

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Row(
        children: [
          Expanded(child: field),
          AppPageCloseButton(
            tooltip: closeTooltip,
            onPressed: onClose,
          ),
        ],
      ),
    );
  }
}
