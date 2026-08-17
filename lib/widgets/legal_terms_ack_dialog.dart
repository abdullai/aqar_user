import 'package:flutter/material.dart';

import '../core/compliance/platform_policy_copy.dart';
import '../l10n/app_localizations.dart';
import '../screens/platform_policies_screen.dart';

/// إقرار الشروط لمرة واحدة: مربع صح إلزامي + رابط يفتح السياسة كنافذة منبثقة.
/// لا يُغلق بالضغط خارجها ولا بزر موافقة قبل التأشير.
Future<bool> showLegalTermsAckDialog(
  BuildContext context, {
  required bool isAr,
}) async {
  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => _LegalTermsAckDialog(isAr: isAr),
  );
  return result == true;
}

class _LegalTermsAckDialog extends StatefulWidget {
  const _LegalTermsAckDialog({required this.isAr});

  final bool isAr;

  @override
  State<_LegalTermsAckDialog> createState() => _LegalTermsAckDialogState();
}

class _LegalTermsAckDialogState extends State<_LegalTermsAckDialog> {
  bool _acked = false;

  Future<void> _openTermsPopup() async {
    final size = MediaQuery.sizeOf(context);
    final narrow = size.width < 520;
    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        return Dialog(
          insetPadding: EdgeInsets.symmetric(
            horizontal: narrow ? 12 : 28,
            vertical: narrow ? 18 : 36,
          ),
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          child: SizedBox(
            width: (size.width * 0.92).clamp(320.0, 560.0),
            height: (size.height * 0.78).clamp(420.0, 720.0),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 4, 4, 0),
                  child: Row(
                    children: [
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          widget.isAr ? 'الشروط والأحكام' : 'Terms & Conditions',
                          style: const TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 16,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: widget.isAr ? 'إغلاق' : 'Close',
                        onPressed: () => Navigator.of(ctx).pop(),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: PlatformPoliciesScreen(
                    isAr: widget.isAr,
                    initialDoc: PlatformPolicyDoc.termsOfUse,
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
    final t = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final narrow = MediaQuery.sizeOf(context).width < 420;

    return PopScope(
      canPop: false,
      child: AlertDialog(
        insetPadding: EdgeInsets.symmetric(
          horizontal: narrow ? 16 : 24,
          vertical: 24,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          t.legalTermsCoachTitle,
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                t.legalTermsCoachBody,
                style: TextStyle(
                  color: cs.onSurfaceVariant,
                  height: 1.4,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 16),
              Material(
                color: cs.surfaceContainerHighest.withValues(alpha: 0.55),
                borderRadius: BorderRadius.circular(14),
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: () => setState(() => _acked = !_acked),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(8, 10, 12, 10),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Checkbox(
                          value: _acked,
                          onChanged: (v) =>
                              setState(() => _acked = v ?? false),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(6),
                          ),
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                        ),
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.only(top: 10),
                            child: Text.rich(
                              TextSpan(
                                style: TextStyle(
                                  color: cs.onSurface,
                                  fontWeight: FontWeight.w700,
                                  height: 1.4,
                                  fontSize: 14,
                                ),
                                children: [
                                  TextSpan(
                                    text: widget.isAr
                                        ? 'أقر بأنني اطلعت على '
                                        : 'I confirm that I have reviewed the ',
                                  ),
                                  WidgetSpan(
                                    alignment: PlaceholderAlignment.baseline,
                                    baseline: TextBaseline.alphabetic,
                                    child: GestureDetector(
                                      onTap: _openTermsPopup,
                                      child: Text(
                                        widget.isAr
                                            ? 'الشروط والأحكام'
                                            : 'Terms & Conditions',
                                        style: TextStyle(
                                          color: cs.primary,
                                          fontWeight: FontWeight.w900,
                                          decoration: TextDecoration.underline,
                                          decorationColor: cs.primary
                                              .withValues(alpha: 0.45),
                                        ),
                                      ),
                                    ),
                                  ),
                                  TextSpan(
                                    text: widget.isAr
                                        ? ' وأوافق على الالتزام بها.'
                                        : ' and agree to abide by them.',
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              if (!_acked) ...[
                const SizedBox(height: 10),
                Text(
                  widget.isAr
                      ? 'فعّل مربع الإقرار أعلاه للمتابعة.'
                      : 'Check the acknowledgment box above to continue.',
                  style: TextStyle(
                    color: cs.error,
                    fontWeight: FontWeight.w700,
                    fontSize: 12.5,
                  ),
                ),
              ],
            ],
          ),
        ),
        // زر المتابعة يظهر فقط بعد التأشير — لا إغلاق بدون إقرار.
        actions: [
          if (_acked)
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(t.legalTermsCoachOk),
            ),
        ],
      ),
    );
  }
}
