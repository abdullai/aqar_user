import '../profile/publisher_identity_prefs.dart';

/// هوية المسوّق عند تقديم العرض (معتمد / مستعار) — تُحمَل داخل ملاحظات العرض
/// دون أعمدة SQL إضافية، وتُستخرج عند عرض العرض للمالك.
abstract final class OfferIdentityTag {
  static const _open = '⟦AQAR_ID:';
  static const _close = '⟧';

  static String wrap({
    required PublicNameSource source,
    required String displayName,
    required String notes,
  }) {
    final name = displayName.replaceAll('|', ' ').replaceAll(_close, '').trim();
    final tag = '$_open${source.name}|$name$_close';
    final n = notes.trim();
    return n.isEmpty ? tag : '$tag\n$n';
  }

  static OfferIdentityParsed parse(String raw) {
    final s = raw.trim();
    if (!s.startsWith(_open)) {
      return OfferIdentityParsed(notes: s);
    }
    final end = s.indexOf(_close);
    if (end <= _open.length) {
      return OfferIdentityParsed(notes: s);
    }
    final inner = s.substring(_open.length, end);
    final pipe = inner.indexOf('|');
    final srcRaw = (pipe >= 0 ? inner.substring(0, pipe) : inner).trim();
    final name = (pipe >= 0 ? inner.substring(pipe + 1) : '').trim();
    final rest = s.substring(end + _close.length).trim();
    return OfferIdentityParsed(
      source: srcRaw == PublicNameSource.display.name
          ? PublicNameSource.display
          : PublicNameSource.official,
      displayName: name,
      notes: rest,
    );
  }
}

class OfferIdentityParsed {
  const OfferIdentityParsed({
    this.source,
    this.displayName = '',
    this.notes = '',
  });

  final PublicNameSource? source;
  final String displayName;
  final String notes;
}
