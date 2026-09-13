/// خارج الويب: لا تاريخ متصفح.
void installWebInAppHistory({
  required void Function({required bool isForward, required bool leavingOrigin})
      onTraverse,
}) {}

void disposeWebInAppHistory() {}

void webInAppHistoryPushEntry() {}

void webInAppHistoryGoBack() {}

void webInAppHistoryTrapLeaving() {}

void webInAppHistoryHold() {}

void webInAppHistoryRelease() {}

void webInAppHistorySealAuth({String hash = '#/login'}) {}
