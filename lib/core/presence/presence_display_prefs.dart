import 'dart:async' show unawaited;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// أسطح عرض حالة الظهور (متصل / آخر ظهور).
enum PresenceDisplaySurface {
  listingCards,
  requestCards,
  chat,
}

/// تفضيلات المشاهد لعرض الظهور على البطاقات والدردشة.
/// منفصلة عن إخفاء «آخر ظهور» الخاص بالحساب (chat_last_seen_hidden على الخادم).
class PresenceDisplayPrefs extends ChangeNotifier {
  PresenceDisplayPrefs._();
  static final PresenceDisplayPrefs instance = PresenceDisplayPrefs._();

  static const _kListing = 'presence_view_listing_cards_v1';
  static const _kRequest = 'presence_view_request_cards_v1';
  static const _kChat = 'presence_view_chat_v1';
  static const _kHideUntilMs = 'presence_view_hide_until_ms_v1';

  bool _loaded = false;
  bool showOnListingCards = true;
  bool showOnRequestCards = true;
  bool showOnChat = true;
  DateTime? hideUntil;

  bool get isLoaded => _loaded;

  Future<void> ensureLoaded() async {
    if (_loaded) return;
    await reload();
  }

  Future<void> reload() async {
    final p = await SharedPreferences.getInstance();
    showOnListingCards = p.getBool(_kListing) ?? true;
    showOnRequestCards = p.getBool(_kRequest) ?? true;
    showOnChat = p.getBool(_kChat) ?? true;
    final until = p.getInt(_kHideUntilMs);
    if (until != null && until > 0) {
      final dt = DateTime.fromMillisecondsSinceEpoch(until);
      hideUntil = dt.isAfter(DateTime.now()) ? dt : null;
      if (hideUntil == null) {
        await p.remove(_kHideUntilMs);
      }
    } else {
      hideUntil = null;
    }
    _loaded = true;
    notifyListeners();
  }

  bool get isTemporarilyHidden {
    final u = hideUntil;
    if (u == null) return false;
    if (DateTime.now().isBefore(u)) return true;
    hideUntil = null;
    unawaited(_persistHideUntil(null));
    return false;
  }

  bool isVisible(PresenceDisplaySurface surface) {
    if (!_loaded) return true;
    if (isTemporarilyHidden) return false;
    switch (surface) {
      case PresenceDisplaySurface.listingCards:
        return showOnListingCards;
      case PresenceDisplaySurface.requestCards:
        return showOnRequestCards;
      case PresenceDisplaySurface.chat:
        return showOnChat;
    }
  }

  Future<void> setShowOnListingCards(bool v) async {
    showOnListingCards = v;
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kListing, v);
    notifyListeners();
  }

  Future<void> setShowOnRequestCards(bool v) async {
    showOnRequestCards = v;
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kRequest, v);
    notifyListeners();
  }

  Future<void> setShowOnChat(bool v) async {
    showOnChat = v;
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kChat, v);
    notifyListeners();
  }

  Future<void> setHideUntil(DateTime? until) async {
    hideUntil = until;
    await _persistHideUntil(until);
    notifyListeners();
  }

  Future<void> clearTemporaryHide() => setHideUntil(null);

  Future<void> _persistHideUntil(DateTime? until) async {
    final p = await SharedPreferences.getInstance();
    if (until == null) {
      await p.remove(_kHideUntilMs);
    } else {
      await p.setInt(_kHideUntilMs, until.millisecondsSinceEpoch);
    }
  }
}
