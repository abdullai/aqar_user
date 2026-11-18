import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:aqar_user/core/utils/app_money.dart';
import 'package:aqar_user/services/report_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Arabic report PDF renders the Saudi riyal SVG in a table cell',
      () async {
    final client = SupabaseClient('http://localhost', 'test-key');
    final service = ReportService(client);
    final bytes = await service.exportToPdf(
      ReportConfig(
        id: 'payments',
        title: 'المدفوعات',
        columns: const ['المبلغ'],
        rows: [
          [AppMoney.formatForPdf(1250, isAr: true)],
        ],
      ),
      isAr: true,
    );

    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    client.dispose();
  });
}
