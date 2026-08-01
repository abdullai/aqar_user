import 'package:flutter/material.dart';

import '../core/presence/presence_display_prefs.dart';
import '../screens/settings_page.dart';

/// زر تعجب بجانب شارة الظهور يشرح الميزة ويفتح إعدادات العرض.
class PresenceFeatureInfoButton extends StatelessWidget {
  const PresenceFeatureInfoButton({
    super.key,
    required this.isAr,
    this.compact = true,
  });

  final bool isAr;
  final bool compact;

  Future<void> _open(BuildContext context) async {
    final prefs = PresenceDisplayPrefs.instance;
    await prefs.ensureLoaded();
    if (!context.mounted) return;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Icon(Icons.info_outline_rounded, color: cs.primary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        isAr
                            ? 'متصل الآن وآخر ظهور'
                            : 'Online & last seen',
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 16,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  isAr
                      ? 'تظهر حالة الطرف الآخر على بطاقات الإعلانات والطلبات والدردشة بشكل لحظي. يمكنك إظهارها أو إخفاءها حسب نوع البطاقة، أو إخفاءها مؤقتاً حتى وقت تحدده. إخفاء ظهورك أنت للآخرين يُضبط من إعدادات الخصوصية في ملفك.'
                      : 'Peer online/last-seen appears on listing cards, request cards, and chat in near real time. You can show or hide it per surface, or hide it temporarily until a time you choose. Hiding your own last seen from others is under profile privacy settings.',
                  style: TextStyle(
                    height: 1.45,
                    fontWeight: FontWeight.w600,
                    color: cs.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: () {
                    Navigator.of(ctx).pop();
                    // نفس منطق لوحة التحكم: تضمين الشريط عند العرض العريض لتفادي سهمي رجوع.
                    final embed =
                        MediaQuery.sizeOf(context).width >= 580;
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        settings: const RouteSettings(
                          name: '/dashboard/settings',
                        ),
                        builder: (_) => SettingsPage(
                          embedAppBar: embed,
                          focusPresenceDisplay: true,
                        ),
                      ),
                    );
                  },
                  icon: const Icon(Icons.settings_outlined),
                  label: Text(
                    isAr
                        ? 'فتح إعدادات عرض الظهور'
                        : 'Open presence display settings',
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      constraints: BoxConstraints(
        minWidth: compact ? 28 : 34,
        minHeight: compact ? 28 : 34,
      ),
      tooltip: isAr ? 'شرح ميزة الظهور' : 'About presence',
      onPressed: () => _open(context),
      icon: Icon(
        Icons.error_outline_rounded,
        size: compact ? 16 : 18,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    );
  }
}
