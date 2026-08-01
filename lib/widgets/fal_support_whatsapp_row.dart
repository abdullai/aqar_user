import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// تواصل الدعم الفني بخصوص رخصة فال (إصدار / تجديد / تحديث).
class FalSupportWhatsappRow extends StatelessWidget {
  const FalSupportWhatsappRow({
    super.key,
    required this.isAr,
    this.compact = false,
    this.inline = true,
  });

  static const String phoneE164 = '966500229909';
  static const String displayLocal = '0500229909';

  final bool isAr;
  final bool compact;
  /// سطر واحد مع أيقونة واتساب بجوار النص.
  final bool inline;

  static Future<void> openSupportChat() async {
    final uri = Uri.parse('https://wa.me/$phoneE164');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  String get _message => isAr
      ? 'في حال عدم وجود رخصة فال أو تجديدها أو تحديثها — تواصل مع الدعم الفني بالضغط على الأيقونة المجاورة'
      : 'If you need a FAL license, renewal, or update — contact technical support via the icon beside this text';

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textStyle = compact
        ? Theme.of(context).textTheme.bodySmall
        : Theme.of(context).textTheme.bodyMedium;

    if (inline) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Text(
              compact ? '• $_message' : _message,
              style: textStyle?.copyWith(height: 1.35),
            ),
          ),
          const SizedBox(width: 4),
          IconButton(
            tooltip: isAr
                ? 'واتساب الدعم · $displayLocal'
                : 'Support WhatsApp · $displayLocal',
            visualDensity: VisualDensity.compact,
            icon: Icon(
              Icons.chat_rounded,
              color: const Color(0xFF25D366),
              size: compact ? 22 : 26,
            ),
            onPressed: openSupportChat,
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(_message, style: textStyle?.copyWith(height: 1.35)),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: openSupportChat,
          icon: const Icon(Icons.chat_rounded, color: Color(0xFF25D366)),
          label: Text(
            isAr
                ? 'واتساب الدعم · $displayLocal'
                : 'Support WhatsApp · $displayLocal',
          ),
          style: OutlinedButton.styleFrom(
            foregroundColor: cs.primary,
            side: BorderSide(color: cs.outline.withValues(alpha: 0.6)),
          ),
        ),
      ],
    );
  }
}
