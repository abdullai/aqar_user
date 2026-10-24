import 'package:flutter_test/flutter_test.dart';
import 'package:aqar_user/core/marketing/hub_card_rows.dart';

void main() {
  test('newestFirst orders by created_at desc, undated last', () {
    final out = HubCardRows.newestFirst([
      {'id': 'a', 'created_at': '2026-01-01T00:00:00Z'},
      {'id': 'x'},
      {'id': 'b', 'created_at': '2026-03-01T00:00:00Z'},
      {'id': 'c', 'created_at': '2026-02-01T00:00:00Z'},
    ]);
    expect(out.map((e) => e['id']), ['b', 'c', 'a', 'x']);
  });

  test('withOfferDeclined drops preview and moves empty request back', () {
    final out = HubCardRows.withOfferDeclined([
      {
        'id': 'r1',
        'status': 'offers_received',
        '_owner_pending_offers_count': 1,
        '_owner_pending_offers_preview': [
          {'id': 'o1'}
        ],
      },
      {'id': 'r2', '_owner_pending_offers_count': 2},
    ], offerId: 'o1', requestId: 'r1');
    expect(out[0]['_owner_pending_offers_count'], 0);
    expect(out[0]['_owner_pending_offers_preview'], isEmpty);
    expect(out[0]['status'], 'waiting_marketers');
    expect(out[1]['_owner_pending_offers_count'], 2);
  });

  test('withOfferAccepted removes pending card and advances its workflow', () {
    final out = HubCardRows.withOfferAccepted([
      {
        'id': 'r1',
        'status': 'offers_received',
        'workflow_stage': 'offers_received',
        '_owner_pending_offers_count': 1,
        '_owner_pending_offers_preview': [
          {'id': 'o1', 'marketer_id': 'm1'}
        ],
      },
      {'id': 'r2', '_owner_pending_offers_preview': []},
    ], 'o1');

    expect(out[0]['selected_offer_id'], 'o1');
    expect(out[0]['selected_marketer_id'], 'm1');
    expect(out[0]['workflow_stage'], 'marketer_selected');
    expect(out[0]['_owner_pending_offers_count'], 0);
    expect(out[0]['_owner_pending_offers_preview'], isEmpty);
    expect(out[1]['id'], 'r2');
  });

  test('withoutOfferId removes only the matching row', () {
    final out = HubCardRows.withoutOfferId([
      {'id': 'o1'},
      {'id': 'o2'},
    ], 'o1');
    expect(out.map((e) => e['id']), ['o2']);
  });
}
