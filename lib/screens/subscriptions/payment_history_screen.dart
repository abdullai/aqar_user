import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:aqar_user/widgets/aqar_text_field.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/branding/app_branding.dart';
import '../../core/utils/app_money.dart';
import '../../l10n/app_localizations.dart';
import '../../services/billing_transaction_repository.dart';
import '../../services/invoice_service.dart';
import '../../widgets/app_logo_loading.dart';
import '../../widgets/aqar_primary_scroll_scope.dart';

/// تبويبات سجل المدفوعات — 3 فقط (بدون «الكل»).
enum PaymentTab { success, pending, failed }

class PaymentHistoryScreen extends StatefulWidget {
  const PaymentHistoryScreen({super.key, required this.lang});

  final String lang;

  @override
  State<PaymentHistoryScreen> createState() => _PaymentHistoryScreenState();
}

class _PaymentHistoryScreenState extends State<PaymentHistoryScreen>
    with SingleTickerProviderStateMixin {
  late final BillingTransactionRepository _repo;
  late final InvoiceService _invoices;
  late final TabController _tabs;
  final _search = TextEditingController();

  bool _loading = true;
  bool _exporting = false;
  String _dateFilter = 'all';
  final Map<PaymentTab, List<Map<String, dynamic>>> _rowsByTab = {};

  bool get _isAr => widget.lang.toLowerCase() != 'en';

  @override
  void initState() {
    super.initState();
    final sb = Supabase.instance.client;
    _repo = BillingTransactionRepository(sb);
    _invoices = InvoiceService(repository: _repo, isAr: _isAr, supabase: sb);
    _tabs = TabController(length: 3, vsync: this);
    _tabs.addListener(() {
      if (mounted && !_tabs.indexIsChanging) setState(() {});
    });
    _loadAll();
    unawaited(_invoices.loadPayerInfo());
  }

  String _formatLatinDate(DateTime? date) {
    if (date == null) return '';
    return InvoiceService.formatLatinDateTime(date.toLocal());
  }

  @override
  void dispose() {
    _tabs.dispose();
    _search.dispose();
    super.dispose();
  }

  Future<void> _loadAll() async {
    if (!mounted) return;
    setState(() => _loading = true);
    final search = _search.text.trim().isEmpty ? null : _search.text.trim();
    final results = await Future.wait([
      _repo.listTransactions(
        status: 'success',
        search: search,
        dateFilter: _dateFilter,
      ),
      _repo.listTransactions(
        status: 'pending',
        search: search,
        dateFilter: _dateFilter,
      ),
      _repo.listTransactions(
        status: 'failed',
        search: search,
        dateFilter: _dateFilter,
      ),
    ]);
    if (!mounted) return;
    setState(() {
      _rowsByTab[PaymentTab.success] = results[0];
      _rowsByTab[PaymentTab.pending] = results[1];
      _rowsByTab[PaymentTab.failed] = results[2];
      _loading = false;
    });
  }

  String _latinRef(Map<String, dynamic> row) =>
      BillingTransactionRepository.latinReference(row);

  String _tabLabel(PaymentTab tab) {
    final t = AppLocalizations.of(context)!;
    final n = _rowsByTab[tab]?.length ?? 0;
    final label = switch (tab) {
      PaymentTab.success =>
        _isAr ? 'المكتملة' : t.subscriptionsFilterSuccess,
      PaymentTab.pending =>
        _isAr ? 'قيد المعالجة' : t.subscriptionsFilterPending,
      PaymentTab.failed => _isAr ? 'الفاشلة' : t.subscriptionsFilterFailed,
    };
    return '$label ($n)';
  }

  IconData _tabIcon(PaymentTab tab) => switch (tab) {
        PaymentTab.success => Icons.check_circle_outline,
        PaymentTab.pending => Icons.hourglass_top_outlined,
        PaymentTab.failed => Icons.error_outline,
      };

  Color _tabColor(PaymentTab tab) => switch (tab) {
        PaymentTab.success => const Color(0xFF1B873F),
        PaymentTab.pending => const Color(0xFFCC8400),
        PaymentTab.failed => const Color(0xFFC62828),
      };

  String _statusLabel(Map<String, dynamic> row) {
    switch (BillingTransactionRepository.normalizedStatus(row)) {
      case 'success':
        return _isAr ? 'مكتملة' : 'Completed';
      case 'pending':
        return _isAr ? 'قيد المعالجة' : 'Pending';
      case 'failed':
        return _isAr ? 'فاشلة' : 'Failed';
      default:
        return _isAr ? 'غير معروف' : 'Unknown';
    }
  }

  String _amountFor(Map<String, dynamic> row) {
    final raw = row['amount'];
    final v =
        raw is num ? raw.toDouble() : double.tryParse('${raw ?? ''}') ?? 0.0;
    return AppMoney.formatWithCurrencyCode(
      v,
      isAr: _isAr,
      currencyCode: '${row['currency'] ?? 'SAR'}'.toUpperCase(),
      maxFractionDigits: 2,
    );
  }

  String _titleFor(Map<String, dynamic> row) =>
      AppBranding.billingTitleFromRow(row, isAr: _isAr);

  PaymentTab get _currentTab => PaymentTab.values[_tabs.index];

  List<Map<String, dynamic>> _rowsForTab(PaymentTab tab) =>
      _rowsByTab[tab] ?? const <Map<String, dynamic>>[];

  List<Map<String, dynamic>> get _currentTabRows => _rowsForTab(_currentTab);

  String _tabExportTitle(PaymentTab tab) => switch (tab) {
        PaymentTab.success => _isAr ? 'فواتير مكتملة' : 'Completed invoices',
        PaymentTab.pending => _isAr ? 'فواتير قيد المعالجة' : 'Pending invoices',
        PaymentTab.failed => _isAr ? 'فواتير فاشلة' : 'Failed invoices',
      };

  String _paymentMethodLabel(String raw) {
    final m = raw.trim().toLowerCase();
    if (m.isEmpty) return '';
    switch (m) {
      case 'card':
        return _isAr ? 'بطاقة' : 'Card';
      case 'mada_pay':
        return _isAr ? 'مدى' : 'mada';
      case 'google_pay':
        return 'Google Pay';
      case 'apple_pay':
        return 'Apple Pay';
      default:
        return raw;
    }
  }

  Future<void> _exportCsv() async {
    await _exportDelimited(mimeType: 'text/csv', extension: 'csv');
  }

  Future<void> _exportExcel() async {
    setState(() => _exporting = true);
    try {
      final rows = _currentTabRows;
      if (rows.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_isAr ? 'لا توجد بيانات للتصدير' : 'No data to export'),
          ),
        );
        return;
      }
      final bytes = await _invoices.exportAllExcel(
        rows,
        sectionTitle: _tabExportTitle(_currentTab),
      );
      final name =
          '${_currentTab.name}_${DateTime.now().millisecondsSinceEpoch}.xlsx';
      await Share.shareXFiles([
        XFile.fromData(
          bytes,
          mimeType:
              'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
          name: name,
        ),
      ]);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_isAr ? 'تم تصدير Excel' : 'Excel exported'),
        ),
      );
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _exportTabPdf() async {
    setState(() => _exporting = true);
    try {
      final rows = _currentTabRows;
      if (rows.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_isAr ? 'لا توجد بيانات للتصدير' : 'No data to export'),
          ),
        );
        return;
      }
      await _invoices.printAll(
        rows,
        tabTitleAr: _tabExportTitle(_currentTab),
        tabTitleEn: _tabExportTitle(_currentTab),
      );
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _exportDelimited({
    required String mimeType,
    required String extension,
    bool excelStyle = false,
  }) async {
    setState(() => _exporting = true);
    try {
      final rows = _currentTabRows;
      if (rows.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_isAr ? 'لا توجد بيانات للتصدير' : 'No data to export'),
          ),
        );
        return;
      }
      final csv = await _invoices.exportAllCsv(
        rows,
        sectionTitle: _tabExportTitle(_currentTab),
      );
      final bytes = InvoiceService.csvUtf8BomBytes(csv);
      final name =
          '${_currentTab.name}_${DateTime.now().millisecondsSinceEpoch}.$extension';
      await Share.shareXFiles([
        XFile.fromData(bytes, mimeType: mimeType, name: name),
      ]);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            excelStyle
                ? (_isAr ? 'تم تصدير Excel' : 'Excel exported')
                : (_isAr ? 'تم تصدير CSV' : 'CSV exported'),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _printAll() async {
    await _invoices.printAll(
      _currentTabRows,
      tabTitleAr: _tabExportTitle(_currentTab),
      tabTitleEn: _tabExportTitle(_currentTab),
    );
  }

  Future<void> _printPdf(Map<String, dynamic> row) async {
    try {
      await _invoices.printInvoice(row);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_isAr ? 'فشلت الطباعة' : 'Print failed')),
      );
    }
  }

  Future<void> _downloadPdf(Map<String, dynamic> row) async {
    try {
      await _invoices.downloadOrShare(row);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_isAr ? 'تم تحميل الفاتورة' : 'Invoice ready'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_isAr ? 'فشل التحميل' : 'Download failed')),
      );
    }
  }

  Future<void> _deleteInvoice(Map<String, dynamic> row) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(_isAr ? 'حذف الفاتورة؟' : 'Delete invoice?'),
        content: Text(
          _isAr
              ? 'سيُحذف السجل نهائياً من قائمتك.'
              : 'This record will be permanently removed.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(_isAr ? 'إلغاء' : 'Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(_isAr ? 'حذف' : 'Delete'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final res = await _repo.deleteTransaction('${row['id']}');
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          res['ok'] == true
              ? (_isAr ? 'تم الحذف' : 'Deleted')
              : (_isAr ? 'تعذّر الحذف' : 'Delete failed'),
        ),
      ),
    );
    if (res['ok'] == true) await _loadAll();
  }

  void _showInvoiceActions(Map<String, dynamic> row) {
    final cs = Theme.of(context).colorScheme;

    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                _isAr ? 'خيارات الفاتورة' : 'Invoice options',
                style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
              const SizedBox(height: 6),
              Text(
                _titleFor(row),
                style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: _invoiceActionButton(
                      icon: Icons.print_outlined,
                      label: _isAr ? 'طباعة' : 'Print',
                      color: cs.primary,
                      onTap: () {
                        Navigator.pop(ctx);
                        unawaited(_printPdf(row));
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _invoiceActionButton(
                      icon: Icons.picture_as_pdf_outlined,
                      label: 'PDF',
                      color: const Color(0xFF1B873F),
                      onTap: () {
                        Navigator.pop(ctx);
                        unawaited(_downloadPdf(row));
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _invoiceActionButton(
                      icon: Icons.table_chart_outlined,
                      label: _isAr ? 'Excel' : 'Excel',
                      color: const Color(0xFF1565C0),
                      onTap: () {
                        Navigator.pop(ctx);
                        unawaited(_exportSingleRowExcel(row));
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: _invoiceActionButton(
                      icon: Icons.delete_outline,
                      label: _isAr ? 'حذف' : 'Delete',
                      color: cs.error,
                      onTap: () {
                        Navigator.pop(ctx);
                        unawaited(_deleteInvoice(row));
                      },
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _exportSingleRowExcel(Map<String, dynamic> row) async {
    try {
      final bytes = await _invoices.exportAllExcel(
        [row],
        sectionTitle: _titleFor(row),
      );
      final name = 'invoice_${_latinRef(row)}.xlsx';
      await Share.shareXFiles([
        XFile.fromData(
          bytes,
          mimeType:
              'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
          name: name,
        ),
      ]);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_isAr ? 'فشل التصدير' : 'Export failed')),
      );
    }
  }

  Widget _invoiceActionButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Material(
      color: color.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withValues(alpha: 0.25)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: color, size: 26),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  color: color,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildList(PaymentTab tab) {
    final rows = _rowsByTab[tab] ?? const <Map<String, dynamic>>[];
    final color = _tabColor(tab);

    return AqarPrimaryScrollScope(
      child: RefreshIndicator(
        onRefresh: _loadAll,
        child: rows.isEmpty
            ? ListView(
                children: [
                  const SizedBox(height: 72),
                  Icon(_tabIcon(tab), color: color, size: 48),
                  const SizedBox(height: 12),
                  Center(
                    child: Text(
                      _isAr ? 'لا توجد فواتير' : 'No invoices',
                      style: TextStyle(color: Theme.of(context).hintColor),
                    ),
                  ),
                ],
              )
            : ListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: rows.length,
                itemBuilder: (_, i) {
                  final row = rows[i];
                  final ref = _latinRef(row);
                  final date = DateTime.tryParse('${row['created_at']}');
                  final dateStr = _formatLatinDate(date);
                  final method = _paymentMethodLabel(
                    '${row['payment_method'] ?? ''}'.trim(),
                  );
                  return Card(
                    margin: const EdgeInsets.only(bottom: 10),
                    elevation: 1,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      leading: Icon(_tabIcon(tab), color: color),
                      title: Text(
                        _titleFor(row),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            method.isNotEmpty ? '$method · #$ref' : '#$ref',
                            style: const TextStyle(fontSize: 12),
                          ),
                          Text(
                            dateStr,
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ],
                      ),
                      trailing: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            _amountFor(row),
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                            ),
                          ),
                          Text(
                            _statusLabel(row),
                            style: TextStyle(fontSize: 11, color: color),
                          ),
                        ],
                      ),
                      onTap: () => _showInvoiceActions(row),
                    ),
                  );
                },
              ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    if (_loading) {
      return const Center(child: AppLogoLoading());
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Column(
            children: [
              AqarTextField(
                controller: _search,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: _isAr ? 'بحث عن فاتورة...' : 'Search invoice...',
                  labelText: t.subscriptionsSearch,
                  prefixIcon: const Icon(Icons.search),
                  border: const OutlineInputBorder(
                    borderRadius: BorderRadius.all(Radius.circular(12)),
                  ),
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.refresh),
                    onPressed: _loadAll,
                  ),
                ),
                onSubmitted: (_) => unawaited(_loadAll()),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  PopupMenuButton<String>(
                    icon: const Icon(Icons.filter_list),
                    tooltip: _isAr ? 'فلتر التاريخ' : 'Date filter',
                    onSelected: (v) {
                      setState(() => _dateFilter = v);
                      unawaited(_loadAll());
                    },
                    itemBuilder: (_) => [
                      PopupMenuItem(
                        value: 'all',
                        child: Text(_isAr ? 'كل الفترات' : 'All time'),
                      ),
                      PopupMenuItem(
                        value: 'today',
                        child: Text(_isAr ? 'اليوم' : 'Today'),
                      ),
                      PopupMenuItem(
                        value: 'week',
                        child: Text(_isAr ? 'هذا الأسبوع' : 'This week'),
                      ),
                      PopupMenuItem(
                        value: 'month',
                        child: Text(_isAr ? 'هذا الشهر' : 'This month'),
                      ),
                    ],
                  ),
                  IconButton(
                    tooltip: _isAr ? 'تصدير CSV' : 'Export CSV',
                    onPressed: _exporting ? null : _exportCsv,
                    icon: _exporting
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.upload_file_outlined),
                  ),
                  IconButton(
                    tooltip: _isAr ? 'تصدير Excel' : 'Export Excel',
                    onPressed: _exporting ? null : _exportExcel,
                    icon: const Icon(Icons.table_view_outlined),
                  ),
                  IconButton(
                    tooltip: _isAr ? 'تصدير PDF' : 'Export PDF',
                    onPressed: _exporting ? null : _exportTabPdf,
                    icon: const Icon(Icons.picture_as_pdf_outlined),
                  ),
                  IconButton(
                    tooltip: _isAr ? 'طباعة التبويب' : 'Print tab',
                    onPressed: _printAll,
                    icon: const Icon(Icons.print_outlined),
                  ),
                  if (_dateFilter != 'all')
                    TextButton(
                      onPressed: () {
                        setState(() => _dateFilter = 'all');
                        unawaited(_loadAll());
                      },
                      child: Text(_isAr ? 'مسح الفلتر' : 'Clear'),
                    ),
                ],
              ),
            ],
          ),
        ),
        TabBar(
          controller: _tabs,
          isScrollable: true,
          tabs: PaymentTab.values.map((tab) {
            return Tab(
              icon: Icon(_tabIcon(tab), color: _tabColor(tab), size: 18),
              child: Text(_tabLabel(tab), style: const TextStyle(fontSize: 12)),
            );
          }).toList(),
        ),
        Expanded(
          child: TabBarView(
            controller: _tabs,
            children: PaymentTab.values.map(_buildList).toList(),
          ),
        ),
      ],
    );
  }
}
