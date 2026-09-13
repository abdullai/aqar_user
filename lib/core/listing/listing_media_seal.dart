import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// ختم سلامة للوسائط: تجزئة SHA-256 دون إعادة ضغط البكسل.
/// لا تُرسم بيانات العقار داخل الصورة/الفيديو.
abstract final class ListingMediaSeal {
  static ListingSealedBytes preserve(Uint8List input, {String name = ''}) {
    final bytes = Uint8List.fromList(input);
    return ListingSealedBytes(
      bytes: bytes,
      sha256Hex: sha256.convert(bytes).toString(),
      mime: mimeFromBytes(bytes, name),
      ext: extFromMime(mimeFromBytes(bytes, name), name),
    );
  }

  static String mimeFromBytes(Uint8List b, String name) {
    if (b.length >= 3 && b[0] == 0xFF && b[1] == 0xD8 && b[2] == 0xFF) {
      return 'image/jpeg';
    }
    if (b.length >= 8 &&
        b[0] == 0x89 &&
        b[1] == 0x50 &&
        b[2] == 0x4E &&
        b[3] == 0x47) {
      return 'image/png';
    }
    if (b.length >= 12 &&
        b[0] == 0x52 &&
        b[1] == 0x49 &&
        b[2] == 0x46 &&
        b[3] == 0x46 &&
        b[8] == 0x57 &&
        b[9] == 0x45 &&
        b[10] == 0x42 &&
        b[11] == 0x50) {
      return 'image/webp';
    }
    if (b.length >= 6 &&
        b[0] == 0x47 &&
        b[1] == 0x49 &&
        b[2] == 0x46) {
      return 'image/gif';
    }
    final n = name.toLowerCase();
    if (n.endsWith('.png')) return 'image/png';
    if (n.endsWith('.webp')) return 'image/webp';
    if (n.endsWith('.gif')) return 'image/gif';
    if (n.endsWith('.heic') || n.endsWith('.heif')) return 'image/heic';
    return 'image/jpeg';
  }

  static String extFromMime(String mime, String name) {
    switch (mime) {
      case 'image/png':
        return 'png';
      case 'image/webp':
        return 'webp';
      case 'image/gif':
        return 'gif';
      case 'image/heic':
      case 'image/heif':
        return 'heic';
      default:
        final n = name.toLowerCase();
        if (n.endsWith('.jpg') || n.endsWith('.jpeg')) return 'jpg';
        return 'jpg';
    }
  }

  static Map<String, dynamic> integrityPayload({
    required List<String> imageHashes,
    String? videoPath,
  }) {
    return {
      'alg': 'sha256',
      'images': imageHashes,
      if ((videoPath ?? '').trim().isNotEmpty) 'video_path': videoPath!.trim(),
      'sealed_at': DateTime.now().toUtc().toIso8601String(),
    };
  }

  static String shortFingerprint(String sha256Hex) {
    final h = sha256Hex.trim().toLowerCase();
    if (h.length < 8) return h;
    return h.substring(0, 8);
  }

  static String encodeIntegrityJson(Map<String, dynamic> map) => jsonEncode(map);
}

class ListingSealedBytes {
  const ListingSealedBytes({
    required this.bytes,
    required this.sha256Hex,
    required this.mime,
    required this.ext,
  });

  final Uint8List bytes;
  final String sha256Hex;
  final String mime;
  final String ext;
}
