import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';

import '../core/navigation/payment_overlay_route.dart';
import 'app_page_close_button.dart';

/// معاينة PDF داخل التطبيق؛ تمنع فتح تبويبات متصفح إضافية أثناء الطباعة.
class PdfPrintPreviewOverlay extends StatelessWidget {
  const PdfPrintPreviewOverlay({
    super.key,
    required this.title,
    required this.fileName,
    required this.onLayout,
  });

  final String title;
  final String fileName;
  final Future<Uint8List> Function(PdfPageFormat format) onLayout;

  static Future<void> show(
    BuildContext context, {
    required String title,
    required String fileName,
    required Future<Uint8List> Function(PdfPageFormat format) onLayout,
  }) {
    return PaymentOverlay.push<void>(
      context,
      name: '/documents/pdf-preview',
      page: PdfPrintPreviewOverlay(
        title: title,
        fileName: fileName,
        onLayout: onLayout,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        leading: const AppPageCloseButton(tooltip: 'Close'),
        title: Text(title),
      ),
      body: PdfPreview(
        build: onLayout,
        pdfFileName: fileName,
        canChangeOrientation: false,
        canChangePageFormat: false,
        allowPrinting: true,
        allowSharing: true,
        maxPageWidth: 900,
        loadingWidget: const Center(child: CircularProgressIndicator()),
      ),
    );
  }
}
