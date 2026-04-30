import 'package:flutter/foundation.dart';

/// Lightweight hook so screens outside the dashboard can ask for a marketer
/// bucket refresh after actions such as submitting an offer.
abstract final class MarketingWorkflowHub {
  static final ValueNotifier<int> bucketsRevision = ValueNotifier<int>(0);

  static void notifyBucketsChanged() {
    bucketsRevision.value = bucketsRevision.value + 1;
  }
}
