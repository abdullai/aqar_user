/// متى تُفتح المراسلة في «صفقاتي»: بعد موافقة مالك الطلب/الإعلان فقط.
abstract final class DealMessagingGate {
  static bool offerApprovedByOwner(String? status) {
    switch ((status ?? '').trim().toLowerCase()) {
      case 'accepted':
      case 'approved':
      case 'selected':
      case 'owner_accepted':
        return true;
      default:
        return false;
    }
  }

  static bool reservationApprovedByOwner(String? status) {
    switch ((status ?? '').trim().toLowerCase()) {
      case 'accepted':
        return true;
      default:
        return false;
    }
  }
}
