/// حراسة روابط الوسائط والجولات في التصفح السريع.
abstract final class ShortsUrlGuard {
  static bool isSafeHttps(String raw) {
    final u = Uri.tryParse(raw.trim());
    if (u == null) return false;
    if (u.scheme != 'https') return false;
    if (u.host.isEmpty) return false;
    final h = u.host.toLowerCase();
    if (h == 'localhost' || h.endsWith('.local') || h == '127.0.0.1') {
      return false;
    }
    if (u.userInfo.isNotEmpty) return false;
    return true;
  }

  static bool isDownloadableMedia(String raw) {
    if (!isSafeHttps(raw)) return false;
    final u = Uri.parse(raw.trim());
    final path = u.path.toLowerCase();
    const ok = ['.jpg', '.jpeg', '.png', '.webp', '.gif', '.mp4', '.mov', '.webm'];
    if (ok.any(path.endsWith)) return true;
    final h = u.host.toLowerCase();
    return h.contains('supabase.co') ||
        h.contains('storage.googleapis.com') ||
        h.contains('firebasestorage') ||
        h.contains('mawthuq') ||
        h.contains('eaqar');
  }
}
