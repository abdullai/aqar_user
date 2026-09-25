import 'package:flutter_test/flutter_test.dart';
import 'package:aqar_user/services/subscription_service.dart';

void main() {
  test('photographer paid catalog includes live plans 31 through 33 only', () {
    final rows = [
      {'user_type': 'photographer', 'sort_order': 0, 'is_trial_plan': true},
      {'user_type': 'photographer', 'sort_order': 31, 'is_trial_plan': false},
      {'user_type': 'photographer', 'sort_order': 32, 'is_trial_plan': false},
      {'user_type': 'photographer', 'sort_order': 33, 'is_trial_plan': false},
      {'user_type': 'marketer', 'sort_order': 1, 'is_trial_plan': false},
    ];

    expect(
      SubscriptionService.allowedSortOrdersForAccountType('photographer'),
      [31, 32, 33],
    );
    expect(
      SubscriptionService.filterCatalogPlansForAccountType(
        rows,
        'photographer',
      ).map((plan) => plan['sort_order']),
      [31, 32, 33],
    );
  });
}
