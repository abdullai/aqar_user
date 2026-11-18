import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('market insights UI and share summary omit personal profile data', () {
    final page =
        File('lib/screens/market_insights_page.dart').readAsStringSync();
    final shareStart = page.indexOf('String _shareBody(');
    final shareEnd = page.indexOf('Future<void> _shareSummary', shareStart);
    final model =
        File('lib/models/market_insights_snapshot.dart').readAsStringSync();

    expect(shareStart, isNonNegative);
    expect(shareEnd, greaterThan(shareStart));
    final shareBody = page.substring(shareStart, shareEnd);
    expect(shareBody.contains('registeredProfiles'), isFalse);
    expect(shareBody.contains('viewer'), isFalse);
    expect(page.contains('_MarketInsightsCommunityTab'), isFalse);
    expect(model.contains('MarketViewer'), isFalse);
    expect(model.contains('MarketLeaderboardEntry'), isFalse);
    expect(model.contains('MarketInsightsExtras'), isFalse);
  });

  test('public market snapshot RPC returns only aggregate fields', () {
    final migration = File(
      'supabase/migrations/20261118010000_market_insights_privacy_snapshot.sql',
    ).readAsStringSync();
    final manualSql =
        File('supabase/sql/20260408_market_insights_snapshot_rpc.sql')
            .readAsStringSync();
    final manualSanitizerStart =
        manualSql.indexOf('-- Replace the historical response above');

    expect(migration.contains("'user_id'"), isFalse);
    expect(migration.contains("'display_name'"), isFalse);
    expect(migration.contains("'registered_profiles'"), isFalse);
    expect(migration.contains("'top_publishers'"), isFalse);
    expect(migration.contains("'viewer'"), isFalse);
    expect(manualSanitizerStart, isNonNegative);
    final activeManualSql = manualSql.substring(manualSanitizerStart);
    expect(activeManualSql.contains("'user_id'"), isFalse);
    expect(activeManualSql.contains("'display_name'"), isFalse);
    expect(activeManualSql.contains("'registered_profiles'"), isFalse);
    expect(activeManualSql.contains("'top_publishers'"), isFalse);
  });

  test('organization desk does not duplicate subscriptions tab', () {
    final desk =
        File('lib/screens/my_organization_screen.dart').readAsStringSync();

    expect(desk.contains('subscriptionDesk'), isFalse);
    expect(desk.contains('SubscriptionOrgDeskTab'), isFalse);
  });
}
