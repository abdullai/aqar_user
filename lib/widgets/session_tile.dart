import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../core/security/device_display_labels.dart';

/// صف جلسة في السجل — تسميات حسب لغة الواجهة.
class SessionTile extends StatelessWidget {
  const SessionTile({
    super.key,
    required this.isArabic,
    required this.session,
    required this.isCurrent,
  });

  final bool isArabic;
  final Map<String, dynamic> session;
  final bool isCurrent;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final active = session['is_active'] == true;
    final device = DeviceDisplayLabels.device(
      '${session['device_info'] ?? ''}',
      isAr: isArabic,
    );
    final browser = DeviceDisplayLabels.browser(
      '${session['browser_info'] ?? ''}',
      isAr: isArabic,
    );
    final os = DeviceDisplayLabels.os(
      '${session['os_info'] ?? ''}',
      isAr: isArabic,
    );
    final loc = '${session['location'] ?? ''}'.trim();
    final loginAtRaw = '${session['login_at'] ?? ''}';
    final loginAt = _formatTs(loginAtRaw, isArabic);
    final method = DeviceDisplayLabels.loginMethod(
      '${session['login_method'] ?? ''}',
      isAr: isArabic,
    );
    final line1 = [device, os].where((e) => e.isNotEmpty).join(' · ');
    final line2 = [browser, loc].where((e) => e.isNotEmpty).join(' · ');

    final border = active ? cs.primary : cs.outlineVariant;

    return Card(
      elevation: active ? 2 : 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: border, width: active ? 2 : 1),
      ),
      child: ListTile(
        title: Text(
          line1.isEmpty ? '—' : line1,
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (line2.isNotEmpty)
              Text(
                line2,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: cs.onSurfaceVariant,
                ),
              ),
            Text(
              '${isArabic ? 'بدء' : 'Started'}: $loginAt'
              '${method.isNotEmpty ? (isArabic ? ' · الطريقة: ' : ' · Method: ') + method : ''}',
              style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
            ),
            if (isCurrent)
              Text(
                isArabic ? 'الجلسة الحالية' : 'Current session',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: cs.primary,
                ),
              ),
          ],
        ),
        trailing: Icon(
          active ? Icons.circle : Icons.circle_outlined,
          color: active ? cs.primary : cs.outline,
          size: 14,
        ),
      ),
    );
  }

  static String _formatTs(String raw, bool isAr) {
    final dt = DateTime.tryParse(raw);
    if (dt == null) return raw.isEmpty ? '—' : raw;
    final loc = isAr ? 'ar' : 'en';
    return DateFormat.yMMMd(loc).add_jm().format(dt.toLocal());
  }
}
