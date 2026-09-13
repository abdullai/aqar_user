import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/payment/invoice_copy.dart';
import '../core/utils/app_money.dart';
import '../core/utils/date_helper.dart';
import '../services/report_service.dart';
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
    final b = await _svc.fetchBilling();
    final l = await _svc.fetchLifecycleEvents();
    if (!mounted) return;
    setState(() {
      _staff = true;
      _billing = b;
      _lifecycle = l;
      _loading = false;
    });
  }

  double _amt(Map<String, dynamic> r) {
    final raw = r['amount'];
    if (raw is num) return raw.toDouble();
    return double.tryParse('${raw ?? ''}') ?? 0.0;
  }

  String _amountLabel(Map<String, dynamic> r) =>
      AppMoney.formatForExport(_amt(r), isAr: widget.isAr, maxFractionDigits: 2);

  Future<void> _printBillingPdf() async {
    final isAr = widget.isAr;
    final cfg = ReportConfig(
      id: 'staff_billing',
      title: isAr ? 'مدفوعات المنصة' : 'Platform billing',
      columns: isAr
          ? const ['المبلغ', 'الطريقة', 'الحالة', 'الغرض', 'أُكمل']
          : const ['Amount', 'Method', 'Status', 'Purpose', 'Completed'],
      rows: _billing
          .take(80)
          .map(
            (r) => [
              _amountLabel(r),
              InvoiceCopy.methodLabel(
                '${r['payment_method'] ?? ''}',
                isAr: isAr,
              ),
              '${r['status'] ?? ''}',
              InvoiceCopy.purposeLabel(
                InvoiceCopy.purposeFromRow(r),
                isAr: isAr,
              ),
              DateHelper.fmtCivilDateTimeRaw(
                r['completed_at'] ?? r['created_at'],
                isAr: isAr,
              ),
            ],
          )
          .toList(),
      filtersDescription: isAr
          ? 'يشمل المكتمل والمسترد والمعلّق'
          : 'Includes success, refunded, and pending',
    );
    final bytes =
        await ReportService(Supabase.instance.client).exportToPdf(cfg, isAr: isAr);
    await Printing.layoutPdf(onLayout: (_) async => bytes);
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
              widget.isAr ? 'آخر العمليات (كل الحالات)' : 'Latest billing (all statuses)',
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
                          label: Text(widget.isAr ? 'الحالة' : 'Status'),
                        ),
                        DataColumn(
                          label: Text(widget.isAr ? 'التاريخ' : 'Completed'),
                        ),
                      ],
                      rows: _billing.take(40).map((r) {
                        return DataRow(
                          cells: [
                            DataCell(Text(_amountLabel(r))),
                            DataCell(
                              Text(
                                InvoiceCopy.methodLabel(
                                  '${r['payment_method'] ?? ''}',
                                  isAr: widget.isAr,
                                ),
                              ),
                            ),
                            DataCell(Text('${r['status'] ?? ''}')),
                            DataCell(
                              Text(
                                DateHelper.fmtCivilDateTimeRaw(
                                  r['completed_at'] ?? r['created_at'],
                                  isAr: widget.isAr,
                                ),
                              ),
                            ),
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
                        DataCell(
                          Text(
                            DateHelper.fmtCivilDateTimeRaw(
                              r['created_at'],
                              isAr: widget.isAr,
                            ),
                          ),
                        ),
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
