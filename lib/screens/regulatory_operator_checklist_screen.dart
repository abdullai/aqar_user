import 'package:flutter/material.dart';

import '../core/compliance/platform_policy_copy.dart';

/// قائمة تحضيرية للمشغّل (ترخيص الهيئة العامة للعقار — مرجع داخلي).
class RegulatoryOperatorChecklistScreen extends StatelessWidget {
  const RegulatoryOperatorChecklistScreen({super.key, required this.isAr});

  final bool isAr;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Directionality(
      textDirection: isAr ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        appBar: AppBar(
          title: Text(isAr ? 'متطلبات الترخيص (مرجع)' : 'Licensing checklist (reference)'),
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
          child: SelectableText(
            RegulatoryOperatorChecklistCopy.full(isAr),
            style: TextStyle(
              height: 1.45,
              fontWeight: FontWeight.w600,
              fontSize: 14,
              color: cs.onSurface.withValues(alpha: 0.92),
            ),
          ),
        ),
      ),
    );
  }
}
