import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/haptics/app_haptics.dart';
import '../main.dart' show langNotifier;
import '../services/report_service.dart';
import '../widgets/app_readable_qr.dart';

class ReportPreviewScreen extends StatelessWidget {
  const ReportPreviewScreen({
    super.key,
    required this.config,
    this.lang,
  });

  final ReportConfig config;
  final String? lang;

  bool get _isAr => (lang ?? langNotifier.value).toLowerCase() != 'en';

  String _qrPayload() {
    final b = StringBuffer(config.title);
    if (config.filtersDescription.isNotEmpty) {
      b.write('\n${config.filtersDescription}');
    }
    b.write('\n${config.id}');
    return b.toString();
  }

  String _pdfShareName() {
    final raw = config.id.replaceAll(RegExp(r'[^\w\-]'), '_');
    final base = raw.isEmpty ? 'report' : raw;
    return '${base}_report.pdf';
  }

  @override
  Widget build(BuildContext context) {
    final svc = ReportService(Supabase.instance.client);
    return Scaffold(
      appBar: AppBar(
        title: Text(_isAr ? 'معاينة التقرير' : 'Report preview'),
      ),
      body: Directionality(
        textDirection: _isAr ? TextDirection.rtl : TextDirection.ltr,
        child: ListView(
          padding: const EdgeInsets.all(12),
          children: [
            Text(
              config.title,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            if (config.filtersDescription.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  '${_isAr ? 'الفلاتر' : 'Filters'}: ${config.filtersDescription}',
                ),
              ),
            const SizedBox(height: 12),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              reverse: _isAr,
              child: DataTable(
                columns: [
                  for (final c in config.columns) DataColumn(label: Text(c)),
                ],
                rows: [
                  for (final r in config.rows)
                    DataRow(
                      cells: [
                        for (var i = 0; i < config.columns.length; i++)
                          DataCell(
                            Text(i < r.length ? r[i] : ''),
                          ),
                      ],
                    ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 320),
                child: AppReadableQr(
                  data: _qrPayload(),
                  isAr: _isAr,
                  size: 180,
                  caption: config.id,
                  title: _isAr
                      ? 'مرجع التقرير (QR)'
                      : 'Report reference (QR)',
                ),
              ),
            ),
            const SizedBox(height: 20),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton(
                  onPressed: () async {
                    try {
                      final bytes = await svc.exportToPdf(config, isAr: _isAr);
                      await Share.shareXFiles(
                        [
                          XFile.fromData(
                            bytes,
                            mimeType: 'application/pdf',
                            name: _pdfShareName(),
                          ),
                        ],
                        text: _isAr ? 'تقرير — PDF' : 'Report — PDF',
                      );
                      if (!context.mounted) return;
                      AppHaptics.light();
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            _isAr
                                ? 'تم تجهيز PDF — يمكنك المشاركة أو الحفظ'
                                : 'PDF ready — share or save from the sheet',
                          ),
                        ),
                      );
                    } catch (e) {
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(e.toString())),
                      );
                    }
                  },
                  child: Text(_isAr ? 'PDF / مشاركة' : 'PDF / Share'),
                ),
                FilledButton.tonal(
                  onPressed: () async {
                    await svc.exportToExcel(config, 'report', isAr: _isAr);
                    if (!context.mounted) return;
                    AppHaptics.light();
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          _isAr ? 'تم حفظ ملف Excel' : 'Excel file saved',
                        ),
                      ),
                    );
                  },
                  child: const Text('Excel'),
                ),
                OutlinedButton(
                  onPressed: () async {
                    await svc.exportToCsv(config, 'report', isAr: _isAr);
                    if (!context.mounted) return;
                    AppHaptics.light();
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          _isAr ? 'تم حفظ CSV' : 'CSV saved',
                        ),
                      ),
                    );
                  },
                  child: Text(_isAr ? 'CSV' : 'CSV'),
                ),
                OutlinedButton(
                  onPressed: () async {
                    await svc.exportToWord(config, 'report', isAr: _isAr);
                    if (!context.mounted) return;
                    AppHaptics.light();
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          _isAr
                              ? 'تم حفظ Word كملف CSV'
                              : 'Word export saved as CSV',
                        ),
                      ),
                    );
                  },
                  child: Text(_isAr ? 'Word (CSV)' : 'Word (CSV)'),
                ),
                OutlinedButton(
                  onPressed: () async {
                    await svc.printReport(config, isAr: _isAr);
                  },
                  child: Text(_isAr ? 'طباعة' : 'Print'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
