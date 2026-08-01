import 'package:web/web.dart' as web;

Future<void> purgeWebAuthTokenKey(String key) async {
  web.window.localStorage.removeItem(key);
}
