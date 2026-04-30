import 'package:share_plus/share_plus.dart';

Future<void> shareListingRich({
  required String text,
  String? imageHttpUrl,
  String? subject,
}) async {
  await Share.share(
    text,
    subject: subject,
  );
}
