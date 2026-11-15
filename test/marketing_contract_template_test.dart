import 'package:aqar_user/core/contracts/marketing_contract_template.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('contract formats Saudi Riyal according to the selected language', () {
    String build({required bool isAr}) => MarketingContractTemplate.build(
          isAr: isAr,
          requestId: 'request-1',
          listingTitle: 'Listing',
          city: 'Riyadh',
          marketingFee: 5000,
          currency: 'SAR',
          listingEnteredPrice: 100000,
          listingPriceIncludesVat: true,
        );

    final arabic = build(isAr: true);
    expect(arabic, contains('أتعاب التسويق المتفق عليها: 5,000 ﷼'));
    expect(arabic, contains('السعر الذي أدخله المعلن: 100,000 ﷼'));
    expect(arabic, isNot(contains('SAR')));

    final english = build(isAr: false);
    expect(english, contains('Agreed marketing fee: 5,000 SAR'));
    expect(english, contains('Advertiser-entered total: 100,000 SAR'));
    expect(english, isNot(contains('﷼')));
  });
}
