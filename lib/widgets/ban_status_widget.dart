import 'package:flutter/material.dart';

import '../main.dart' show langNotifier;

/// تفاصيل حظر المنصّة (سبب، نوع، تاريخ).
class BanStatusWidget extends StatelessWidget {
  const BanStatusWidget({
    super.key,
    required this.ban,
    required this.child,
  });

  final Map<String, dynamic> ban;
  final Widget child;

  bool get _isAr => langNotifier.value != 'en';

  @override
  Widget build(BuildContext context) {
    final reason = '${ban['ban_reason'] ?? ''}'.trim();
    final type = '${ban['ban_type'] ?? ''}'.trim();
    final until = ban['ban_until'];

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (reason.isNotEmpty)
          Text(
            '${_isAr ? 'السبب' : 'Reason'}: $reason',
            textAlign: TextAlign.center,
          ),
        if (type.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            '${_isAr ? 'نوع التعطيل' : 'Ban type'}: $type',
            textAlign: TextAlign.center,
          ),
        ],
        if (until != null && '$until'.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            '${_isAr ? 'حتى' : 'Until'}: $until',
            textAlign: TextAlign.center,
          ),
        ],
        const SizedBox(height: 8),
        Text(
          _isAr
              ? 'لا يمكنك استخدام خدمات التطبيق حالياً بموجب سياسات المنصّة.'
              : 'You cannot use app services while this platform restriction is active.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 20),
        child,
      ],
    );
  }
}
