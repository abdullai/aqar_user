import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:aqar_user/services/user_listing_preferences_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('unscoped legacy hidden IDs are not inherited by a new session',
      () async {
    SharedPreferences.setMockInitialValues({
      'user_hidden_property_ids_v1': '["property-from-previous-account"]',
      'user_hidden_market_request_ids_v1': '["request-from-previous-account"]',
    });

    expect(await UserListingPreferencesService.hiddenPropertyIds(), isEmpty);
    expect(
        await UserListingPreferencesService.hiddenMarketRequestIds(), isEmpty);
  });
}
