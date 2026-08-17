import 'package:http/http.dart' as http;

import 'supabase_http_auth_bridge.dart';

/// يُمرَّر إلى [Supabase.initialize] كـ `httpClient` الداخلي.
///
/// عميل Supabase الافتراضي يضع عند غياب جلسة المستخدم:
/// `Authorization: Bearer <sb_publishable_…>` — وهذا **ليس** JWT ويسبب **401**
/// على `/rest/v1/*`.
///
/// كذلك JWT منتهٍ أو قديم في `localStorage` يُرسل كـ `Bearer eyJ…` فيسبب 401
/// رغم أن القراءة العامة يجب أن تعتمد على `apikey` فقط.
class SupabasePublishableHttpLayer extends http.BaseClient {
  SupabasePublishableHttpLayer({http.Client? inner}) : _inner = inner ?? http.Client();

  final http.Client _inner;

  static bool _isInvalidPublishableBearer(String? authorization, String apiKey) {
    if (authorization == null || authorization.isEmpty) return false;
    if (!apiKey.startsWith('sb_publishable_')) return false;
    final bearer = authorization.trim();
    if (bearer == 'Bearer $apiKey') return true;
    if (bearer.contains('sb_publishable_')) return true;
    return false;
  }

  static bool _shouldStripAuthorization(String? authorization, String apiKey) {
    if (authorization == null || authorization.isEmpty) return false;
    if (!authorization.startsWith('Bearer ')) return false;
    final token = authorization.substring(7).trim();
    if (token.isEmpty) return true;

    if (_isInvalidPublishableBearer(authorization, apiKey)) return true;

    // مفتاح anon JWT في Authorization مع apikey → 401 على REST.
    if (token == apiKey.trim()) return true;

    // JWT (eyJ…) بدون جلسة نشطة → 401 (اختبرناه على المشروع).
    if (token.startsWith('eyJ')) {
      final active = SupabaseHttpAuthBridge.activeAccessToken();
      if (active == null || active.isEmpty || token != active) return true;
    }

    final active = SupabaseHttpAuthBridge.activeAccessToken();
    if (active == null || active.isEmpty) return true;
    return token != active;
  }

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final apiKey = request.headers['apikey'] ?? '';
    final auth = request.headers['Authorization'];
    if (_shouldStripAuthorization(auth, apiKey)) {
      request.headers.remove('Authorization');
    }
    return _inner.send(request);
  }

  @override
  void close() => _inner.close();
}
