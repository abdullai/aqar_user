import 'package:aqar_user/core/branding/branding_pdf.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final ar in [true, false]) {
    test('letterhead builds without layout errors ar=$ar', () async {
      final data = await rootBundle.load('assets/fonts/arabic_pdf_regular.ttf');
      final f = pw.Font.ttf(data);
      final doc = pw.Document();
      doc.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          build: (_) => brandingPdfHeader(
            base: f,
            bold: f,
            logo: null,
            isAr: ar,
            docTitle: ar ? 'فاتورة ضريبية' : 'Tax invoice',
            subtitle: '2026-11-10',
            invoiceLayout: true,
            fontFallback: [f],
          ),
        ),
      );
      final bytes = await doc.save();
      expect(bytes.length, greaterThan(1000));
    });
  }
}
