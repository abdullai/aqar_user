import 'web_user_agent_stub.dart'
    if (dart.library.html) 'web_user_agent_web.dart' as impl;

String readWebUserAgentImpl() => impl.readWebUserAgent();
