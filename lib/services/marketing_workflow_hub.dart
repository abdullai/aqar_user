import 'package:flutter/foundation.dart';

/// Lightweight hook so screens outside the dashboard can ask for a marketer
/// bucket refresh after actions such as submitting an offer.
abstract final class MarketingWorkflowHub {
  static final ValueNotifier<int> bucketsRevision = ValueNotifier<int>(0);

  /// يُضبط عند فتح إشعار لتمييز بطاقة الطلب في «صفحتي» لفترة قصيرة.
  static final ValueNotifier<String?> hubHighlightRequestId =
      ValueNotifier<String?>(null);

  static int? _pendingMarketerTabIndex;

  static void notifyBucketsChanged() {
    bucketsRevision.value = bucketsRevision.value + 1;
  }

  /// بعد إرسال عرض من خارج «صفحتي» (تفاصيل الإعلان): افتح تبويب «عروضي».
  static void requestMarketerHubTab(int index) {
    if (index < 0) return;
    _pendingMarketerTabIndex = index;
  }

  static int? takePendingMarketerTab() {
    final v = _pendingMarketerTabIndex;
    _pendingMarketerTabIndex = null;
    return v;
  }

  static void requestHubHighlight(String? requestId) {
    final t = (requestId ?? '').trim();
    hubHighlightRequestId.value = t.isEmpty ? null : t;
  }
}
