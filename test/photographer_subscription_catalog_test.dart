import 'package:flutter_test/flutter_test.dart';
import 'package:aqar_user/core/payment/checkout_journey.dart';
import 'package:aqar_user/core/subscription/plan_display_copy.dart';
import 'package:aqar_user/services/subscription_service.dart';
import 'package:aqar_user/widgets/subscription/subscription_ui_helpers.dart';

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

  test('individual users can see their plans and deal top-ups only', () {
    final rows = [
      {'user_type': 'individual', 'sort_order': 1, 'is_trial_plan': false},
      {'user_type': 'individual', 'sort_order': 14, 'is_trial_plan': false},
      {'user_type': 'individual', 'sort_order': 15, 'is_trial_plan': false},
      {'user_type': 'individual', 'sort_order': 11, 'is_trial_plan': false},
      {'user_type': 'individual', 'sort_order': 13, 'is_trial_plan': false},
      {'user_type': 'individual', 'sort_order': 16, 'is_trial_plan': false},
      {'user_type': 'individual', 'sort_order': 12, 'is_trial_plan': false},
      {'user_type': 'individual', 'sort_order': 23, 'is_trial_plan': false},
      {'user_type': 'marketer', 'sort_order': 1, 'is_trial_plan': false},
      {'user_type': 'individual', 'sort_order': 0, 'is_trial_plan': true},
    ];

    expect(
      SubscriptionService.allowedSortOrdersForAccountType('owner_individual'),
      [1, 14, 11, 12, 15, 16, 23],
    );
    expect(
      SubscriptionService.filterCatalogPlansForAccountType(
        rows,
        'owner_individual',
      ).map((plan) => plan['sort_order']),
      [1, 11, 12, 14, 15, 16, 23],
    );
    expect(
      SubscriptionService.allowedSortOrdersForAccountType('owner_individual'),
      isNot(contains(13)),
    );
  });

  test('individual main lifetime plan remains visible beside recurring plans',
      () {
    final rows = [
      {
        'id': 'partner-monthly',
        'user_type': 'individual',
        'sort_order': 1,
        'plan_program': 'monthly',
      },
      {
        'id': 'partner-lifetime',
        'user_type': 'individual',
        'sort_order': 15,
        'plan_program': 'lifetime_one_time',
      },
    ];

    final visible = SubscriptionService.filterCatalogPlansForAccountType(
      rows,
      'user',
    );

    expect(visible.map((plan) => plan['id']), [
      'partner-monthly',
      'partner-lifetime',
    ]);
  });

  test('catalog deduplication preserves different programs at the same rank',
      () {
    final rows = [
      {
        'id': 'monthly',
        'user_type': 'individual',
        'sort_order': 1,
        'plan_program': 'monthly',
      },
      {
        'id': 'lifetime',
        'user_type': 'individual',
        'sort_order': 1,
        'plan_program': 'lifetime_one_time',
      },
    ];

    final visible = SubscriptionService.filterCatalogPlansForAccountType(
      rows,
      'user',
    );

    expect(visible.map((plan) => plan['id']), ['lifetime', 'monthly']);
  });

  test('subscription plans open on the current billing period', () {
    expect(
      SubscriptionUiHelpers.initialPlanPeriod({'period': 'yearly'}),
      'yearly',
    );
    expect(
      SubscriptionUiHelpers.initialPlanPeriod({'period': 'lifetime_one_time'}),
      'one_time',
    );
    expect(SubscriptionUiHelpers.initialPlanPeriod(null), 'monthly');
  });

  test('yearly subscribers can only upgrade to a yearly plan', () {
    final current = {
      'id': 'subscription-1',
      'plan_id': 'plan-1',
      'status': 'active',
      'period': 'yearly',
      'plan': {'sort_order': 1},
    };
    final higherTier = {'id': 'plan-2', 'sort_order': 4};

    bool canUpgrade(String targetPeriod) =>
        SubscriptionUiHelpers.showUpgradePlanButton(
          currentRow: current,
          targetPlan: higherTier,
          targetPeriod: targetPeriod,
          inPaidPeriod: (_) => true,
          planSortOrder: (plan) => plan['sort_order'] as int,
        );

    expect(canUpgrade('monthly'), isFalse);
    expect(canUpgrade('yearly'), isTrue);
  });

  test('one-time individual deal and request credits are standalone actions',
      () {
    final dealCredit = {
      'user_type': 'individual',
      'sort_order': 16,
      'plan_program': 'lifetime_one_time',
      'max_market_offers': 1,
      'max_listing_requests': 0,
    };
    final requestCredit = {
      'user_type': 'individual',
      'sort_order': 23,
      'plan_program': 'lifetime_one_time',
      'max_market_offers': 0,
      'max_listing_requests': 1,
    };

    expect(
      PlanDisplayCopy.aboutParagraph(
        dealCredit,
        lang: 'ar',
        planName: 'إضافة صفقة',
      ),
      contains('رصيد لإتمام صفقة واحدة'),
    );
    expect(
      PlanDisplayCopy.aboutParagraph(
        requestCredit,
        lang: 'ar',
        planName: 'طلب واحد',
      ),
      contains('طلب عقاري واحد'),
    );
    expect(
      PlanDisplayCopy.aboutParagraph(
        {
          'user_type': 'marketer',
          'sort_order': 23,
          'plan_program': 'lifetime_one_time',
          'max_listing_requests': 10,
        },
        lang: 'en',
        planName: 'Listing Requests',
      ),
      isNot(contains('One property-request credit')),
    );
    expect(CheckoutJourney.isAddOnPlan(dealCredit), isTrue);
    expect(CheckoutJourney.isAddOnPlan(requestCredit), isTrue);
    expect(
      CheckoutJourney.resolve(plan: dealCredit),
      SubscriptionCheckoutKind.oneTimeOperationCredit,
    );
    expect(
      CheckoutJourney.resolve(plan: requestCredit),
      SubscriptionCheckoutKind.oneTimeOperationCredit,
    );
  });

  test(
      'marketing operation credits are standalone without reusing legacy sort 23',
      () {
    final marketingDeal = {
      'user_type': 'marketer',
      'sort_order': 16,
      'plan_program': 'lifetime_one_time',
      'max_market_offers': 1,
    };
    final marketingRequest = {
      'user_type': 'marketer',
      'sort_order': 24,
      'plan_program': 'lifetime_one_time',
      'max_listing_requests': 1,
    };
    final legacyMarketingRequest = {
      'user_type': 'marketer',
      'sort_order': 23,
      'plan_program': 'lifetime_one_time',
      'max_listing_requests': 10,
    };
    final recurringDealTopup = {
      'user_type': 'marketer',
      'sort_order': 11,
      'plan_program': 'monthly',
      'max_market_offers': 10,
    };

    expect(
      SubscriptionService.allowedSortOrdersForAccountType('marketer'),
      [1, 4, 11, 12, 16, 21, 22, 24],
    );
    expect(
      SubscriptionService.allowedSortOrdersForAccountType('office'),
      [2, 4, 11, 12, 16, 21, 22, 24],
    );
    expect(
      SubscriptionService.allowedSortOrdersForAccountType('company'),
      [3, 4, 11, 12, 16, 24],
    );
    expect(CheckoutJourney.isStandaloneOperationCredit(marketingDeal), isTrue);
    expect(
      CheckoutJourney.isStandaloneOperationCredit(marketingRequest),
      isTrue,
    );
    expect(
      PlanDisplayCopy.aboutParagraph(
        marketingRequest,
        lang: 'en',
        planName: 'One Property Request Credit',
      ),
      contains('One property-request credit'),
    );
    expect(
      PlanDisplayCopy.marketOffersLine(marketingDeal, lang: 'en'),
      contains('Complete one deal'),
    );
    expect(
      PlanDisplayCopy.listingRequestsLine(marketingRequest, lang: 'en'),
      contains('Publish one property request'),
    );
    expect(
      CheckoutJourney.isStandaloneOperationCredit(legacyMarketingRequest),
      isFalse,
    );
    expect(
      CheckoutJourney.isStandaloneOperationCredit(recurringDealTopup),
      isFalse,
    );
  });
}
