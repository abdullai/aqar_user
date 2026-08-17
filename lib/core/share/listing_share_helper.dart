import 'listing_share_helper_stub.dart'
    if (dart.library.io) 'listing_share_helper_io.dart' as _impl;

Future<void> shareListingRich({
  required String text,
  String? imageHttpUrl,
  String? subject,
}) =>
    _impl.shareListingRich(
      text: text,
      imageHttpUrl: imageHttpUrl,
      subject: subject,
    );
