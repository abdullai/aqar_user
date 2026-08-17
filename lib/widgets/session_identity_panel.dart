import 'package:flutter/material.dart';

/// بطاقة هوية مرتبة بصفوف جدول — تتقلص حسب العرض دون التفاف مزعج.
class SessionIdentityPanel extends StatelessWidget {
  const SessionIdentityPanel({
    super.key,
    required this.isAr,
    required this.displayName,
    required this.maskedId,
    this.statusLabel,
    this.headline,
    this.accent = const Color(0xFF0F766E),
    this.compact = false,
    /// بدون حرف أفاتار — جدول بيانات نظيف تحت الشعار.
    this.tableOnly = false,
  });

  final bool isAr;
  final String displayName;
  final String maskedId;
  final String? statusLabel;
  /// عنوان أعلى الاسم — افتراضي: جلسة مقفلة (شاشة PIN).
  final String? headline;
  final Color accent;
  final bool compact;
  final bool tableOnly;

  String get _initial {
    final t = displayName.trim();
    if (t.isEmpty) return '?';
    return String.fromCharCode(t.runes.first).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = cs.brightness == Brightness.dark;
    final border = accent.withValues(alpha: isDark ? 0.35 : 0.28);
    final fill = accent.withValues(alpha: isDark ? 0.10 : 0.06);
    final pad = compact ? 10.0 : 14.0;
    final avatar = compact ? 40.0 : 48.0;

    final name = displayName.trim().isEmpty
        ? (isAr ? '…' : '…')
        : displayName.trim();
    final id = maskedId.trim();
    final status = (statusLabel ?? '').trim();
    final head = (headline ?? '').trim().isNotEmpty
        ? headline!.trim()
        : (isAr ? 'جلسة مقفلة' : 'Session locked');

    Widget row({
      required String label,
      required String value,
      required IconData icon,
      bool emphasize = false,
    }) {
      return Container(
        width: double.infinity,
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 10 : 14,
          vertical: compact ? 9 : 11,
        ),
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(color: border.withValues(alpha: 0.55)),
          ),
        ),
        child: Row(
          children: [
            Icon(icon, size: compact ? 16 : 18, color: accent),
            const SizedBox(width: 10),
            SizedBox(
              width: compact ? 76 : 92,
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: compact ? 11.5 : 12.5,
                  fontWeight: FontWeight.w800,
                  color: cs.onSurfaceVariant,
                ),
              ),
            ),
            Expanded(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: AlignmentDirectional.centerStart,
                child: Text(
                  value,
                  maxLines: 1,
                  softWrap: false,
                  style: TextStyle(
                    fontSize: emphasize
                        ? (compact ? 14.5 : 16)
                        : (compact ? 13 : 14.5),
                    fontWeight: FontWeight.w900,
                    color: cs.onSurface,
                    height: 1.1,
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    if (tableOnly) {
      return Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: fill,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: border, width: 1.15),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            row(
              label: isAr ? 'الحالة' : 'Status',
              value: head,
              icon: Icons.lock_outline_rounded,
            ),
            if (displayName.trim().isNotEmpty)
              row(
                label: isAr ? 'الاسم' : 'Name',
                value: name,
                icon: Icons.person_outline_rounded,
                emphasize: true,
              ),
            if (id.isNotEmpty)
              row(
                label: isAr ? 'الهوية' : 'ID',
                value: id,
                icon: Icons.badge_outlined,
              ),
            if (status.isNotEmpty)
              row(
                label: isAr ? 'الجهاز' : 'Device',
                value: status,
                icon: Icons.verified_user_outlined,
              ),
          ],
        ),
      );
    }

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: border, width: 1.2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(pad, pad, pad, compact ? 8 : 10),
            child: Row(
              children: [
                Container(
                  width: avatar,
                  height: avatar,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: isDark ? 0.22 : 0.14),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: border),
                  ),
                  child: Text(
                    _initial,
                    style: TextStyle(
                      fontSize: avatar * 0.42,
                      fontWeight: FontWeight.w900,
                      color: accent,
                      height: 1,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: AlignmentDirectional.centerStart,
                        child: Text(
                          head,
                          maxLines: 1,
                          softWrap: false,
                          style: TextStyle(
                            fontSize: compact ? 12 : 13,
                            fontWeight: FontWeight.w800,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ),
                      const SizedBox(height: 2),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: AlignmentDirectional.centerStart,
                        child: Text(
                          name,
                          maxLines: 1,
                          softWrap: false,
                          style: TextStyle(
                            fontSize: compact ? 15 : 17,
                            fontWeight: FontWeight.w900,
                            color: cs.onSurface,
                            height: 1.15,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (id.isNotEmpty)
            row(
              label: isAr ? 'الهوية' : 'ID',
              value: id,
              icon: Icons.badge_outlined,
            ),
          if (status.isNotEmpty)
            row(
              label: isAr ? 'الحالة' : 'Status',
              value: status,
              icon: ((headline ?? '').contains('مفعّل') ||
                      (headline ?? '').toLowerCase().contains('active'))
                  ? Icons.verified_user_outlined
                  : Icons.lock_outline_rounded,
            ),
        ],
      ),
    );
  }
}
