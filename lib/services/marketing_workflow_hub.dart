import 'package:flutter/foundation.dart';

/// Lightweight hook so screens outside the dashboard can ask for a marketer
/// bucket refresh after actions such as submitting an offer.
abstract final class MarketingWorkflowHub {
  static final ValueNotifier<int> bucketsRevision = ValueNotifier<int>(0);

  /// يُضبط عند فتح إشعار لتمييز بطاقة الطلب في «صفحتي» لفترة قصيرة.
  static final ValueNotifier<String?> hubHighlightRequestId =
      ValueNotifier<String?>(null);

  static void notifyBucketsChanged() {
    bucketsRevision.value = bucketsRevision.value + 1;
  }

  static void requestHubHighlight(String? requestId) {
    final t = (requestId ?? '').trim();
    hubHighlightRequestId.value = t.isEmpty ? null : t;
  }
}
