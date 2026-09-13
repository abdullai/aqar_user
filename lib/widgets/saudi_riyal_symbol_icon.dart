import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// الرسم الرسمي لرمز الريال السعودي (مسار SAMA) كأيقونة متجهة بجانب المبالغ.
///
/// [size] هو ارتفاع الرمز النهائي (نفس خط الرقم). العرض يُحسب من نسبة 1.2.
/// لا تضع هذا الودجت داخل [Text.rich]/[WidgetSpan] على الويب مع [ColorFilter].
class SaudiRiyalSymbolIcon extends StatelessWidget {
  final double size;
  final Color color;
  final EdgeInsetsGeometry? padding;

  const SaudiRiyalSymbolIcon({
    super.key,
    required this.size,
    required this.color,
    this.padding,
  });

  static const String assetPath = 'assets/currency/saudi_riyal_symbol.svg';

  /// نسبة viewBox الرسمية 1200×1000.
  static const double aspectRatio = 1200 / 1000;

  static ui.Picture? _picture;
  static Size? _pictureSize;
  static Future<void>? _loading;

  static Future<void> ensurePictureLoaded() {
    if (_picture != null) return Future<void>.value();
    return _loading ??= _loadPicture();
  }

  static Future<void> _loadPicture() async {
    try {
      final info = await vg.loadPicture(
        const SvgAssetLoader(assetPath),
        null,
      );
      _picture = info.picture;
      _pictureSize = info.size;
    } catch (_) {
      _loading = null;
    }
  }

  /// يرسم الرمز الرسمي على كانفاس الدبوس (بعد تحميل الصورة مرة واحدة).
  static void paintOnCanvas(
    Canvas canvas, {
    required Offset offset,
    required double height,
    required Color color,
  }) {
    final pic = _picture;
    final src = _pictureSize;
    if (pic == null || src == null || src.width <= 0 || src.height <= 0) {
      return;
    }
    final h = height.clamp(8.0, 96.0);
    final w = h * aspectRatio;
    canvas.save();
    canvas.translate(offset.dx, offset.dy);
    canvas.scale(w / src.width, h / src.height);
    final paint = Paint()
      ..colorFilter = ColorFilter.mode(color, BlendMode.srcIn)
      ..filterQuality = FilterQuality.high
      ..isAntiAlias = true;
    canvas.saveLayer(Rect.fromLTWH(0, 0, src.width, src.height), paint);
    canvas.drawPicture(pic);
    canvas.restore();
    canvas.restore();
  }

  static Size canvasSizeFor(double height) {
    final h = height.clamp(8.0, 96.0);
    return Size(h * aspectRatio, h);
  }

  @override
  Widget build(BuildContext context) {
    final h = size.clamp(8.0, 48.0);
    final w = h * aspectRatio;
    return Padding(
      padding: padding ?? EdgeInsets.zero,
      child: SizedBox(
        width: w,
        height: h,
        child: OverflowBox(
          maxWidth: w + 1,
          maxHeight: h + 1,
          alignment: Alignment.center,
          child: SvgPicture.asset(
            assetPath,
            width: w,
            height: h,
            fit: BoxFit.contain,
            colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
            semanticsLabel: 'SAR',
            placeholderBuilder: (_) => FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                kIsWeb ? '\u{FDFC}' : 'SAR',
                style: TextStyle(
                  fontSize: h * 0.82,
                  fontWeight: FontWeight.w800,
                  color: color,
                  height: 1.0,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
