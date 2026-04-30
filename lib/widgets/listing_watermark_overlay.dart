import 'package:flutter/material.dart';

/// طبقة ردع بسيطة ضد الالتقاط السريع — ليست تشفيراً ولا حماية كاملة.
class ListingWatermarkOverlay extends StatelessWidget {
  const ListingWatermarkOverlay({
    super.key,
    required this.traceId,
    this.isAr = true,
    /// عند التعيين يُستبدل عنوان «موثوق العقاري» (مثلاً لطلبات التسوّق).
    this.headline,
  });

  /// آخر أحرف من معرف الإعلان أو نص قصير للتمييز.
  final String traceId;
  final bool isAr;
  final String? headline;

  @override
  Widget build(BuildContext context) {
    final t = traceId.trim();
    final head = (headline ?? '').trim();
    final base = head.isNotEmpty
        ? head
        : (isAr ? 'موثوق العقاري' : 'Verified listing');
    final label = t.isEmpty ? base : '$base · $t';

    return Positioned.fill(
      child: IgnorePointer(
        child: ClipRect(
          child: CustomPaint(
            painter: _DiagonalWatermarkPainter(
              text: label,
              isAr: isAr,
            ),
          ),
        ),
      ),
    );
  }
}

class _DiagonalWatermarkPainter extends CustomPainter {
  _DiagonalWatermarkPainter({
    required this.text,
    required this.isAr,
  });

  final String text;
  final bool isAr;

  @override
  void paint(Canvas canvas, Size size) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: Colors.white.withValues(alpha: 0.36),
          fontSize: 16,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.6,
          shadows: const [
            Shadow(
              offset: Offset(0, 1),
              blurRadius: 2,
              color: Color(0x66000000),
            ),
          ],
        ),
      ),
      textDirection: isAr ? TextDirection.rtl : TextDirection.ltr,
      textAlign: TextAlign.center,
    )..layout(maxWidth: size.width);

    canvas.save();
    canvas.translate(size.width * 0.5, size.height * 0.5);
    canvas.rotate(-0.42);
    canvas.translate(-size.width * 0.5, -size.height * 0.5);

    for (double y = -size.height; y < size.height * 2; y += 72) {
      for (double x = -size.width; x < size.width * 2; x += 220) {
        tp.paint(canvas, Offset(x, y));
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _DiagonalWatermarkPainter oldDelegate) {
    return oldDelegate.text != text || oldDelegate.isAr != isAr;
  }
}
