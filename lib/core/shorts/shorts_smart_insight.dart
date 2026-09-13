import '../../models/property.dart';
import '../../models/market_property_request_row.dart';
import '../listing/property_type_catalog.dart';
import '../utils/app_money.dart';
import 'shorts_feed_logic.dart';

/// مطابقة محلية سريعة (بدون خدمة خارجية) لجذب المستخدم لنقطة قرار.
abstract final class ShortsSmartInsight {
  static String line({
    required bool isAr,
    Property? property,
    MarketPropertyRequestRow? request,
    required int comments,
    required bool seen,
    int views = 0,
  }) {
    if (property != null) {
      final hours = DateTime.now().difference(property.displayDate).inHours;
      if (hours >= 0 && hours <= 8) {
        return isAr
            ? 'ذكاء موثوق: نزل حديثاً — فرصة مبكرة قبل ازدحام المشاهدات'
            : 'Mawthuq AI: Just listed — early look before views pile up';
      }
      if (property.isFeatured == true) {
        return isAr
            ? 'ذكاء موثوق: إعلان مميّز — أولوية في الظهور'
            : 'Mawthuq AI: Featured listing — higher visibility';
      }
      if (views >= 35 && comments == 0) {
        return isAr
            ? 'ذكاء موثوق: مشاهدات عالية بلا نقاش — اسأل من داخل موثوق فقط'
            : 'Mawthuq AI: High views, quiet thread — ask in-app only';
      }
      if (property.area > 10 && property.price > 0) {
        final per = (property.price / property.area).round();
        return isAr
            ? 'ذكاء موثوق: نحو ${AppMoney.sarPhrase('$per', isAr: true)}/م² — راجع التفاصيل قبل الصفقة'
            : 'Mawthuq AI: about ${AppMoney.sarPhrase('$per', isAr: false)}/m² — review details before a deal';
      }
      final t = PropertyTypeCatalog.label(property.listingTypeKey, isAr);
      if (comments >= 3) {
        return isAr
            ? 'ذكاء موثوق: $t عليه نقاش نشط داخل المنصة فقط'
            : 'Mawthuq AI: Active in-app discussion on this $t';
      }
      if (seen) {
        return isAr
            ? 'شاهدته سابقاً — لا يزال متاحاً حسب حالة السوق'
            : 'You saw this before — still listed if the status is live';
      }
      return isAr
          ? 'ذكاء موثوق: أكمل الصفقة داخل موثوق ولا تشارك أرقام تواصل'
          : 'Mawthuq AI: Close the deal in-app — never share phone numbers';
    }
    final r = request;
    if (r != null) {
      if (r.isInstantPaid) {
        return isAr
            ? 'ذكاء موثوق: طلب فوري — قدّم العرض من داخل التطبيق'
            : 'Mawthuq AI: Instant request — submit the offer in-app';
      }
      if (ShortsFeedLogic.purposeIsRent(r.purpose)) {
        return isAr
            ? 'ذكاء موثوق: طلب إيجار — طابق المواصفات قبل العرض'
            : 'Mawthuq AI: Rent request — match specs before offering';
      }
      return isAr
          ? 'ذكاء موثوق: قدّم عرضك عبر المنصة ليبقى التواصل موثّقاً'
          : 'Mawthuq AI: Send your offer in-app so contact stays logged';
    }
    return '';
  }
}
