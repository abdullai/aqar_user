import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../main.dart' show themeModeNotifier;

/// عرض نسخة الشروط النشطة وطلب الموافقة (رفض = لا دخول).
class LegalTermsAcceptanceScreen extends StatelessWidget {
  final String lang;
  final Map<String, dynamic> legal;
  final Future<void> Function(String version) onAccept;
  final VoidCallback onDecline;

  const LegalTermsAcceptanceScreen({
    super.key,
    required this.lang,
    required this.legal,
    required this.onAccept,
    required this.onDecline,
  });

  bool get _isAr => lang.toLowerCase() != 'en';

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final version = (legal['version'] ?? '').toString();
    final title = _isAr
        ? (legal['title_ar'] ?? t.legalTermsTitle).toString()
        : (legal['title_en'] ?? t.legalTermsTitle).toString();
    final body = _isAr
        ? (legal['body_ar'] ?? '').toString()
        : (legal['body_en'] ?? '').toString();
    final fallback = t.legalTermsFallbackBody;
    final displayBody =
        body.trim().isEmpty ? fallback : body;

    return Directionality(
      textDirection: _isAr ? TextDirection.rtl : TextDirection.ltr,
      child: ValueListenableBuilder<ThemeMode>(
        valueListenable: themeModeNotifier,
        builder: (context, mode, _) {
          final isLight = mode == ThemeMode.light;
          final bg = isLight ? const Color(0xFFF5F7FA) : const Color(0xFF0E0F13);
          final fg = isLight ? const Color(0xFF0B1220) : Colors.white;
          return PopScope(
            canPop: false,
            child: Scaffold(
            backgroundColor: bg,
            appBar: AppBar(
              automaticallyImplyLeading: false,
              title: Text(t.legalTermsTitle),
            ),
            body: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        color: fg,
                      ),
                    ),
                    if (version.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        '${_isAr ? 'الإصدار' : 'Version'}: $version',
                        style: TextStyle(
                          color: fg.withValues(alpha: 0.65),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    Expanded(
                      child: SingleChildScrollView(
                        child: Text(
                          displayBody,
                          style: TextStyle(
                            height: 1.45,
                            fontWeight: FontWeight.w600,
                            color: fg.withValues(alpha: 0.92),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: version.isEmpty
                          ? null
                          : () async {
                              await onAccept(version);
                            },
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF0F766E),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: Text(t.legalAccept),
                    ),
                    const SizedBox(height: 10),
                    OutlinedButton(
                      onPressed: onDecline,
                      child: Text(t.legalDecline),
                    ),
                  ],
                ),
              ),
            ),
          ),
          );
        },
      ),
    );
  }
}
