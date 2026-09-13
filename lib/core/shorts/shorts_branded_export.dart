import 'dart:typed_data';
import 'dart:ui' show Rect;

import 'package:file_saver/file_saver.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as im;
import 'package:share_plus/share_plus.dart';

import '../branding/app_branding.dart';
import '../share/app_listing_links.dart';
import 'shorts_url_guard.dart';

/// تصدير موسوم بعلامة موثوق — لا يُحفظ الأصل الخام.
abstract final class ShortsBrandedExport {
  static const _maxBytes = 12 * 1024 * 1024;

  static Future<Uint8List?> fetchSafeImage(String url) async {
    if (!ShortsUrlGuard.isDownloadableMedia(url)) return null;
    try {
      final res = await http.get(Uri.parse(url)).timeout(
            const Duration(seconds: 20),
          );
      if (res.statusCode != 200) return null;
      final bytes = res.bodyBytes;
      if (bytes.isEmpty || bytes.length > _maxBytes) return null;
      final ct = (res.headers['content-type'] ?? '').toLowerCase();
      if (ct.contains('video') || ct.contains('html') || ct.contains('javascript')) {
        return null;
      }
      return Uint8List.fromList(bytes);
    } catch (_) {
      return null;
    }
  }

  static Uint8List stamp({
    required Uint8List raw,
    required String brandLine,
    required String idLine,
  }) {
    final decoded = im.decodeImage(raw);
    if (decoded == null) return raw;
    final w = decoded.width;
    final h = decoded.height;
    final bar = (h * 0.11).round().clamp(36, 96);
    final teal = im.ColorRgba8(13, 148, 136, 210);
    final ink = im.ColorRgba8(255, 255, 255, 230);
    final veil = im.ColorRgba8(0, 0, 0, 150);
    im.fillRect(
      decoded,
      x1: 0,
      y1: h - bar,
      x2: w,
      y2: h,
      color: veil,
    );
    im.fillRect(
      decoded,
      x1: 0,
      y1: h - bar,
      x2: 8,
      y2: h,
      color: teal,
    );
    final font = im.arial14;
    im.drawString(
      decoded,
      brandLine,
      font: font,
      x: 16,
      y: h - bar + 8,
      color: ink,
    );
    im.drawString(
      decoded,
      idLine,
      font: font,
      x: 16,
      y: h - bar + 22,
      color: ink,
    );
    return Uint8List.fromList(im.encodeJpg(decoded, quality: 88));
  }

  static Future<void> saveJpeg(Uint8List bytes, String name) async {
    await FileSaver.instance.saveFile(
      name: name,
      bytes: bytes,
      fileExtension: 'jpg',
      mimeType: MimeType.jpeg,
    );
  }

  static Future<void> shareStamped({
    required Uint8List jpeg,
    required String text,
    required String subject,
    Rect? shareOrigin,
  }) async {
    final origin = shareOrigin ?? const Rect.fromLTWH(0, 0, 1, 1);
    try {
      await Share.shareXFiles(
        [
          XFile.fromData(
            jpeg,
            mimeType: 'image/jpeg',
            name: 'mawthuq_line.jpg',
          ),
        ],
        text: text,
        subject: subject,
        sharePositionOrigin: origin,
      );
    } catch (_) {
      await Share.share(text, subject: subject, sharePositionOrigin: origin);
    }
  }

  static String listingText({
    required String title,
    required String id,
    required bool isAr,
    required bool isProperty,
  }) {
    final uri = isProperty
        ? AppListingLinks.listingWebUri(id, lang: isAr ? 'ar' : 'en')
        : AppListingLinks.marketRequestWebUri(id, lang: isAr ? 'ar' : 'en');
    final brand = AppBranding.shortName(isAr: isAr);
    return isAr
        ? '$title\n عبر $brand — المنصة فقط، بدون تواصل خارجي.\n$uri'
        : '$title\n via $brand — stay in-app, no off-platform contact.\n$uri';
  }
}
