part of 'user_dashboard.dart';

String _marketRequestPriorityL10nLabel(
  AppLocalizations t,
  MarketPropertyRequestPriority p,
) {
  switch (p) {
    case MarketPropertyRequestPriority.flexible:
      return t.marketRequestPriorityFlexible;
    case MarketPropertyRequestPriority.standard:
      return t.marketRequestPriorityStandard;
    case MarketPropertyRequestPriority.priority:
      return t.marketRequestPriorityPriority;
    case MarketPropertyRequestPriority.urgent:
      return t.marketRequestPriorityUrgent;
    case MarketPropertyRequestPriority.immediate:
      return t.marketRequestPriorityImmediate;
  }
}
