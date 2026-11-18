import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:aqar_user/core/subscription/app_subscription_gate.dart';

class _SignedInSubscriptionGate extends AppSubscriptionGate {
  _SignedInSubscriptionGate(super._sb);

  @override
  bool get isGuest => false;
}

void main() {
  test('unsubscribed marketing accounts can add listings and requests', () {
    final client = SupabaseClient('http://localhost', 'test-key');
    final gate = _SignedInSubscriptionGate(client)
      ..accountType = 'company'
      ..marketingFeatureAccess = false
      ..loaded = true;

    expect(gate.isMarketingAccount, isTrue);
    expect(gate.canAddPropertyListing, isTrue);
    expect(gate.canAddMarketPropertyRequest, isTrue);

    gate.dispose();
  });
}
