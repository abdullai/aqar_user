/// حرف أو رمز لعرضه داخل دائرة بدون صورة (دردشة، عروض، إلخ).
String chatAvatarInitialLetter(String displayName) {
  final t = displayName.trim();
  if (t.isEmpty) return '?';
  return t.substring(0, 1).toUpperCase();
}
