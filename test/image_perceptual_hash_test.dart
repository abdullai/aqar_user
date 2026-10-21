import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'package:aqar_user/core/listing/image_perceptual_hash.dart';

Uint8List _scene({int w = 240, int h = 180}) {
  final im = img.Image(width: w, height: h);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final v = ((x * 255 / w) * 0.6 + (y * 255 / h) * 0.2).round();
      im.setPixelRgb(x, y, v, v ~/ 2 + 30, 255 - v);
    }
  }
  img.fillRect(im,
      x1: 30, y1: 20, x2: 120, y2: 90, color: img.ColorRgb8(240, 20, 20));
  img.fillRect(im,
      x1: 130, y1: 100, x2: 210, y2: 160, color: img.ColorRgb8(10, 10, 10));
  img.fillCircle(im,
      x: 170, y: 50, radius: 25, color: img.ColorRgb8(250, 250, 40));
  return Uint8List.fromList(img.encodePng(im));
}

int _best(List<String> a, List<String> b) {
  var best = 64;
  for (final x in a) {
    for (final y in b) {
      if (x[0] != y[0]) continue;
      final d = ImagePerceptualHash.hamming(x.substring(2), y.substring(2));
      if (d < best) best = d;
    }
  }
  return best;
}

void main() {
  final base = ImagePerceptualHash.computeAll(_scene());
  final src = img.decodeImage(_scene())!;

  test('يولّد بصمات من العائلتين', () {
    expect(base.any((e) => e.startsWith('h:')), isTrue);
    expect(base.any((e) => e.startsWith('d:')), isTrue);
  });

  test('يقاوم القلب الأفقي', () {
    final m = img.flipHorizontal(src.clone());
    final h = ImagePerceptualHash.computeAll(
      Uint8List.fromList(img.encodePng(m)),
    );
    expect(_best(base, h), lessThanOrEqualTo(5));
  });

  test('يقاوم القص المركزي وتغيير الحجم', () {
    final c = img.copyCrop(src, x: 12, y: 9, width: 216, height: 162);
    final r = img.copyResize(c, width: 120);
    final h = ImagePerceptualHash.computeAll(
      Uint8List.fromList(img.encodeJpg(r, quality: 70)),
    );
    expect(_best(base, h), lessThanOrEqualTo(6));
  });

  test('يقاوم تغيير السطوع والتباين', () {
    final b = img.adjustColor(src.clone(), brightness: 1.2, contrast: 1.15);
    final h = ImagePerceptualHash.computeAll(
      Uint8List.fromList(img.encodePng(b)),
    );
    expect(_best(base, h), lessThanOrEqualTo(6));
  });

  test('يقاوم الدوران', () {
    final r = img.copyRotate(src, angle: 90);
    final h = ImagePerceptualHash.computeAll(
      Uint8List.fromList(img.encodePng(r)),
    );
    expect(_best(base, h), lessThanOrEqualTo(5));
  });

  test('الصورة المختلفة بعيدة', () {
    final other = img.Image(width: 240, height: 180);
    for (var y = 0; y < 180; y++) {
      for (var x = 0; x < 240; x++) {
        final v = ((x ~/ 20 + y ~/ 20) % 2 == 0) ? 255 : 0;
        other.setPixelRgb(x, y, v, v, v);
      }
    }
    final h = ImagePerceptualHash.computeAll(
      Uint8List.fromList(img.encodePng(other)),
    );
    expect(_best(base, h), greaterThan(10));
  });

  test('الصور الموحّدة اللون تُتجاهل', () {
    final flat = img.Image(width: 100, height: 100);
    img.fill(flat, color: img.ColorRgb8(255, 255, 255));
    expect(
      ImagePerceptualHash.computeAll(Uint8List.fromList(img.encodePng(flat))),
      isEmpty,
    );
  });
}
