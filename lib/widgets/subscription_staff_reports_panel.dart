import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/subscription_admin_report_service.dart';
import 'app_logo_loading.dart';

/// تقارير اشتراكات/مدفوعات لموظفي المنصة — تبويب «إدارتي» / التقارير.
class SubscriptionStaffReportsPanel extends StatefulWidget {
  const SubscriptionStaffReportsPanel({super.key, required this.isAr});

  final bool isAr;

  @override
  State<SubscriptionStaffReportsPanel> createState() =>
      _SubscriptionStaffReportsPanelState();
}

class _SubscriptionStaffReportsPanelState
    extends State<SubscriptionStaffReportsPanel> {
  final _svc = SubscriptionAdminReportService(Supabase.instance.client);
  bool _loading = true;
  bool _staff = false;
  List<Map<String, dynamic>> _billing = [];
  List<Map<String, dynamic>> _lifecycle = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final staff = await _svc.isPlatformStaff();
    if (!staff) {
      if (mounted) {
        setState(() {
          _staff = false;
          _loading = false;
        });
      }
      return;
    }
    final b = await _svc.fetchBillingSuccess();
    final l = await _svc.fetchLifecycleEvents();
    if (!mounted) return;
    setState(() {
      _staff = true;
      _billing = b;
      _lifecycle = l;
      _loading = false;
    });
  }

  Future<void> _printBillingPdf() async {
    final doc = pw.Document();
    final rows = _billing.take(60).toList();
    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        build: (ctx) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              widget.isAr ? 'مدفوعات ناجحة (ملخص)' : 'Successful payments (summary)',
              style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 12),
            pw.Table(
              border: pw.TableBorder.all(width: 0.4),
              children: [
                pw.TableRow(
                  children: (widget.isAr
                          ? ['مبلغ', 'طريقة', 'أُكمل']
                          : ['Amount', 'Method', 'Completed'])
                      .map((h) => pw.Padding(
                            padding: const pw.EdgeInsets.all(4),
                            child: pw.Text(
                              h,
                              style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                            ),
                          ))
                      .toList(),
                ),
                ...rows.map(
                  (r) => pw.TableRow(
                    children: [
                      '${r['amount'] ?? ''}',
                      '${r['payment_method'] ?? ''}',
                      '${r['completed_at'] ?? ''}',
                    ]
                        .map(
                          (c) => pw.Padding(
                            padding: const pw.EdgeInsets.all(4),
                            child: pw.Text(
                              c,
                              style: const pw.TextStyle(fontSize: 9),
                            ),
                          ),
                        )
                        .toList(),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
    await Printing.layoutPdf(onLayout: (_) async => doc.save());
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: AppLogoLoading()),
      );
    }
    if (!_staff) {
      return const SizedBox.shrink();
    }
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.payments_outlined, color: cs.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    widget.isAr
                        ? 'اشتراكات ومدفوعات (موظفو المنصة)'
                        : 'Subscriptions & payments (platform staff)',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
                IconButton(
                  tooltip: widget.isAr ? 'تحديث' : 'Refresh',
                  onPressed: _load,
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.tonalIcon(
                  onPressed: _billing.isEmpty
                      ? null
                      : () => _svc.exportBillingSuccessExcel(
                            rows: _billing,
                            isAr: widget.isAr,
                          ),
                  icon: const Icon(Icons.table_chart_outlined),
                  label: Text(
                    widget.isAr ? 'تصدير مدفوعات Excel' : 'Export billing Excel',
                  ),
                ),
                FilledButton.tonalIcon(
                  onPressed: _lifecycle.isEmpty
                      ? null
                      : () => _svc.exportLifecycleExcel(
                            rows: _lifecycle,
                            isAr: widget.isAr,
                          ),
                  icon: const Icon(Icons.history_edu_outlined),
                  label: Text(
                    widget.isAr ? 'تصدير أحداث Excel' : 'Export lifecycle Excel',
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: _billing.isEmpty ? null : _printBillingPdf,
                  icon: const Icon(Icons.print_outlined),
                  label: Text(widget.isAr ? 'طباعة ملخص' : 'Print summary'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              widget.isAr ? 'آخر المدفوعات الناجحة' : 'Latest successful payments',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: cs.primary,
              ),
            ),
            SizedBox(
              height: 200,
              child: Scrollbar(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SingleChildScrollView(
                    child: DataTable(
                      columns: [
                        DataColumn(
                          label: Text(widget.isAr ? 'المبلغ' : 'Amount'),
                        ),
                        DataColumn(
                          label: Text(widget.isAr ? 'الطريقة' : 'Method'),
                        ),
                        DataColumn(
                          label: Text(widget.isAr ? 'التاريخ' : 'Completed'),
                        ),
                      ],
                      rows: _billing.take(40).map((r) {
                        return DataRow(
                          cells: [
                            DataCell(Text('${r['amount'] ?? ''}')),
                            DataCell(Text('${r['payment_method'] ?? ''}')),
                            DataCell(Text('${r['completed_at'] ?? ''}')),
                          ],
                        );
                      }).toList(),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              widget.isAr ? 'أحداث دورة الاشتراك' : 'Subscription lifecycle',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: cs.primary,
              ),
            ),
            SizedBox(
              height: 160,
              child: SingleChildScrollView(
                child: DataTable(
                  columns: [
                    DataColumn(
                      label: Text(widget.isAr ? 'الحدث' : 'Event'),
                    ),
                    DataColumn(
                      label: Text(widget.isAr ? 'الوقت' : 'Time'),
                    ),
                  ],
                  rows: _lifecycle.take(25).map((r) {
                    return DataRow(
                      cells: [
                        DataCell(Text('${r['event_type'] ?? ''}')),
                        DataCell(Text('${r['created_at'] ?? ''}')),
                      ],
                    );
                  }).toList(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
