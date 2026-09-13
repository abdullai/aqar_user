import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// بصمة بيانات هذا الطلب فقط: شريط لوني + رمز قصير من الحقول المعروضة.
/// يتغيّر إن تغيّر السعر أو الصك أو الموقع — ليست بصمة جلسة ولا رمز تحقق.
class ListingDataFingerprintStrip extends StatelessWidget {
  const ListingDataFingerprintStrip({
    super.key,
    required this.isAr,
    required this.seed,
    required this.identityCard,
  });

  final bool isAr;
  final String seed;
  final String identityCard;

  static String digestHex(String seed) {
    final d = sha256.convert(utf8.encode(seed));
    return d.toString().substring(0, 10).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final hex = digestHex(seed);
    final bytes = sha256.convert(utf8.encode(seed)).bytes;
    final hues = List<Color>.generate(8, (i) {
      final h = (bytes[i] / 255.0) * 360.0;
      return HSLColor.fromAHSL(1, h, 0.42, 0.48).toColor();
    });

    return Material(
      color: cs.surface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: identityCard.trim().isEmpty
            ? null
            : () async {
                await Clipboard.setData(ClipboardData(text: identityCard.trim()));
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      isAr
                          ? 'نُسخت بطاقة هوية هذا العقار فقط'
                          : 'This listing’s identity card was copied',
                    ),
                  ),
                );
              },
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.85)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(Icons.verified_outlined, size: 18, color: cs.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      isAr ? 'بصمة بيانات هذا العقار' : 'This listing’s data seal',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 13,
                        color: cs.primary,
                        fontFamily: 'Cairo',
                      ),
                    ),
                  ),
                  Text(
                    hex,
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 12,
                      letterSpacing: 1.1,
                      color: cs.onSurface,
                      fontFamily: 'Cairo',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: SizedBox(
                  height: 8,
                  child: Row(
                    children: [
                      for (final c in hues)
                        Expanded(child: ColoredBox(color: c)),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                isAr
                    ? 'مرتبطة بهذا الطلب فقط. اضغط لنسخ بطاقة الهوية (العنوان والموقع والسعر الأساسي).'
                    : 'Tied to this request only. Tap to copy the identity card (headline, location, base price).',
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  height: 1.35,
                  fontWeight: FontWeight.w700,
                  color: cs.onSurfaceVariant,
                  fontFamily: 'Cairo',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
