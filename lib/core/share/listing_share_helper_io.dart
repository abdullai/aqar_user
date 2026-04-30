import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:share_plus/share_plus.dart';

Future<void> shareListingRich({
  required String text,
  String? imageHttpUrl,
  String? subject,
}) async {
  final u = imageHttpUrl?.trim();
  if (u != null && u.isNotEmpty) {
    try {
      final res = await http
          .get(Uri.parse(u))
          .timeout(const Duration(seconds: 25));
      if (res.statusCode == 200 && res.bodyBytes.isNotEmpty) {
        final dir = Directory.systemTemp;
        final f = File(
          '${dir.path}/aqar_share_${DateTime.now().millisecondsSinceEpoch}.jpg',
        );
        await f.writeAsBytes(res.bodyBytes, flush: true);
        await Share.shareXFiles(
          [XFile(f.path)],
          text: text,
          subject: subject,
        );
        return;
      }
    } catch (_) {}
  }
  await Share.share(text, subject: subject);
}
