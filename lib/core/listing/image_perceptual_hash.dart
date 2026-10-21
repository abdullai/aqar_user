import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart' as foundation;
import 'package:image/image.dart' as img;

/// بصمات إدراكية متعددة تقاوم تغيير الحجم والضغط والإضاءة والقص المركزي والقلب الأفقي.
/// الصيغة: "h:<hex16>" لعائلة dHash (كاملة/مقلوبة/مقصوصة)، و"d:<hex16>" لعائلة DCT.
abstract final class ImagePerceptualHash {
  static List<String> computeAll(Uint8List bytes) {
    try {
      final decoded = img.decodeImage(bytes);
      if (decoded == null) return const [];
      final out = <String>[];

      void addH(img.Image src) {
        final h = _dHash(src);
        if (_usable(h)) out.add('h:$h');
      }

      void addD(img.Image src) {
        final d = _dctHash(src);
        if (_usable(d)) out.add('d:$d');
      }

      addH(decoded);
      addD(decoded);

      final w = decoded.width, h = decoded.height;
      if (w >= 64 && h >= 64) {
        final cw = (w * 0.8).round(), ch = (h * 0.8).round();
        addH(
          img.copyCrop(
            decoded,
            x: (w - cw) ~/ 2,
            y: (h - ch) ~/ 2,
            width: cw,
            height: ch,
          ),
        );
      }

      final mirrored = img.flipHorizontal(decoded.clone());
      addH(mirrored);
      addD(mirrored);

      // الصور المدارة (جوال بوضع خاطئ أو تدوير متعمد).
      for (final angle in const [90, 180, 270]) {
        addD(img.copyRotate(decoded, angle: angle));
      }

      return out.toSet().toList();
    } catch (_) {
      return const [];
    }
  }

  static Future<List<String>> computeAsync(Uint8List bytes) =>
      foundation.compute(ImagePerceptualHash.computeAll, bytes);

  /// صور شبه فارغة/موحّدة اللون تعطي بصمات متشابهة بلا معنى؛ نتجاهلها.
  static bool _usable(String hex) {
    var ones = 0;
    for (var i = 0; i < hex.length; i++) {
      var x = int.parse(hex[i], radix: 16);
      while (x != 0) {
        ones += x & 1;
        x >>= 1;
      }
    }
    return ones >= 8 && ones <= 56;
  }

  static List<double> _grayGrid(img.Image src, int w, int h) {
    final small = img.copyResize(
      src,
      width: w,
      height: h,
      interpolation: img.Interpolation.average,
    );
    return List<double>.generate(w * h, (i) {
      final p = small.getPixel(i % w, i ~/ w);
      return 0.299 * p.r + 0.587 * p.g + 0.114 * p.b;
    });
  }

  static String _bitsToHex(List<bool> bits) {
    final sb = StringBuffer();
    for (var i = 0; i < bits.length; i += 4) {
      var n = 0;
      for (var j = 0; j < 4; j++) {
        n = (n << 1) | (bits[i + j] ? 1 : 0);
      }
      sb.write(n.toRadixString(16));
    }
    return sb.toString();
  }

  static String _dHash(img.Image src) {
    final g = _grayGrid(src, 9, 8);
    final bits = <bool>[];
    for (var y = 0; y < 8; y++) {
      for (var x = 0; x < 8; x++) {
        bits.add(g[y * 9 + x] > g[y * 9 + x + 1]);
      }
    }
    return _bitsToHex(bits);
  }

  /// pHash: DCT على شبكة 32×32 ثم أخذ الترددات المنخفضة 8×8 ومقارنتها بالوسيط.
  static String _dctHash(img.Image src) {
    const n = 32;
    final g = _grayGrid(src, n, n);
    // صورة شبه موحّدة: لا معلومات كافية، والوسيط سيعطي بتات عشوائية.
    if (g.reduce(math.max) - g.reduce(math.min) < 12) return '';
    final cosT = List.generate(
      8,
      (u) => List.generate(
        n,
        (x) => math.cos((2 * x + 1) * u * math.pi / (2 * n)),
      ),
    );
    final tmp = List.generate(n, (_) => List<double>.filled(8, 0));
    for (var y = 0; y < n; y++) {
      for (var u = 0; u < 8; u++) {
        var s = 0.0;
        for (var x = 0; x < n; x++) {
          s += g[y * n + x] * cosT[u][x];
        }
        tmp[y][u] = s;
      }
    }
    final coef = <double>[];
    for (var v = 0; v < 8; v++) {
      for (var u = 0; u < 8; u++) {
        var s = 0.0;
        for (var y = 0; y < n; y++) {
          s += tmp[y][u] * cosT[v][y];
        }
        coef.add(s);
      }
    }
    final sorted = coef.sublist(1)..sort();
    final median = sorted[sorted.length ~/ 2];
    return _bitsToHex([for (final c in coef) c > median]);
  }

  static int hamming(String a, String b) {
    if (a.length != b.length) return 64;
    var d = 0;
    for (var i = 0; i < a.length; i++) {
      var x = int.parse(a[i], radix: 16) ^ int.parse(b[i], radix: 16);
      while (x != 0) {
        d += x & 1;
        x >>= 1;
      }
    }
    return d;
  }
}
