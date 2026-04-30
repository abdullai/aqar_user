import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// لون الحبر الموحّد للتوقيعات (عقود / ملف) — يظهر كقلم أزرق.
const int kSignatureInkR = 13;
const int kSignatureInkG = 71;
const int kSignatureInkB = 161;

/// يحوّل أي صورة توقيع (رفع من الجهاز) إلى طبقة حبر أزرق على خلفية بيضاء.
/// لا يمنع التزوير كريبتغرافياً؛ الهدف توحيد الشكل القانوني للعرض والطباعة.
Uint8List? applySignatureBlueInkStyle(Uint8List input) {
  try {
    final decoded = img.decodeImage(input);
    if (decoded == null) return null;

    final w = decoded.width;
    final h = decoded.height;
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final p = decoded.getPixel(x, y);
        if (p.aNormalized < 0.04) {
          decoded.setPixelRgb(x, y, 255, 255, 255);
          continue;
        }
        final ln = p.luminanceNormalized.toDouble();
        if (ln > 0.935) {
          decoded.setPixelRgb(x, y, 255, 255, 255);
        } else {
          final strength = ((1.0 - ln) * 255).round().clamp(35, 255);
          decoded.setPixelRgba(
            x,
            y,
            kSignatureInkR,
            kSignatureInkG,
            kSignatureInkB,
            strength,
          );
        }
      }
    }
    return Uint8List.fromList(img.encodePng(decoded));
  } catch (_) {
    return null;
  }
}
