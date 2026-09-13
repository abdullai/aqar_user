/// صفقة وافق المالك على شريكها ولم تُتمَّ بعد (خارج التطبيق غالباً).
class OpenAcceptedDeal {
  const OpenAcceptedDeal({
    required this.kind,
    required this.id,
    required this.title,
    required this.role,
    this.propertyId,
    this.requestId,
    this.offerId,
  });

  /// `listing` | `market_request`
  final String kind;
  final String id;
  final String title;

  /// `owner` | `partner`
  final String role;
  final String? propertyId;
  final String? requestId;
  final String? offerId;

  bool get isListing => kind == 'listing';
  bool get isOwner => role == 'owner';

  factory OpenAcceptedDeal.fromJson(Map<String, dynamic> m) {
    return OpenAcceptedDeal(
      kind: (m['kind'] ?? '').toString().trim(),
      id: (m['id'] ?? '').toString().trim(),
      title: (m['title'] ?? '').toString().trim(),
      role: (m['role'] ?? '').toString().trim(),
      propertyId: _nz(m['property_id']),
      requestId: _nz(m['request_id'] ?? m['market_request_id']),
      offerId: _nz(m['offer_id']),
    );
  }

  static String? _nz(dynamic v) {
    final s = (v ?? '').toString().trim();
    return s.isEmpty ? null : s;
  }
}
