import 'package:flutter_test/flutter_test.dart';

import 'package:aqar_user/core/government/wathq_models.dart';

void main() {
  test('parses Wathq commercial status and dates from the API response', () {
    final registration = CommercialRegistrationData.fromJson({
      'crNumber': '1010711252',
      'crNationalNumber': '7001272475',
      'name': 'Test company',
      'status': {'id': 1, 'name': 'Active'},
      'issueDateGregorian': '2002-10-05',
      'issueDateHijri': '28-07-1423',
      'confirmationDate': {
        'gregorian': '2003-10-05',
        'hijri': '28-07-1424',
      },
    });

    expect(registration.status, 'Active');
    expect(registration.issueDate, DateTime(2002, 10, 5));
    expect(registration.issueHijriDate, '28-07-1423');
    expect(registration.confirmationDate, DateTime(2003, 10, 5));
    expect(registration.toJson()['issueHijriDate'], '28-07-1423');

    final restored = CommercialRegistrationData.fromJson(registration.toJson());
    expect(restored.status, registration.status);
    expect(restored.issueDate, registration.issueDate);
    expect(restored.issueHijriDate, registration.issueHijriDate);
    expect(restored.confirmationDate, registration.confirmationDate);
  });

  test('accepts a string status and confirmation date', () {
    final registration = CommercialRegistrationData.fromJson({
      'crNumber': '1010711252',
      'crNationalNumber': '7001272475',
      'name': 'Test company',
      'status': 'Active',
      'confirmationDate': '2003-10-05',
    });

    expect(registration.status, 'Active');
    expect(registration.confirmationDate, DateTime(2003, 10, 5));
  });
}
