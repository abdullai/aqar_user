import 'dart:async';

import 'package:flutter/material.dart';
import 'package:aqar_user/widgets/aqar_text_field.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/payment/invoice_copy.dart';
import '../../core/payment/invoice_document.dart';
import '../../core/utils/app_money.dart';
import '../../l10n/app_localizations.dart';
import '../../services/billing_transaction_repository.dart';
import '../../services/invoice_service.dart';
import '../../widgets/app_logo_loading.dart';
import '../../widgets/aqar_primary_scroll_scope.dart';
import 'invoice_detail_screen.dart';

/// تبويبات سجل المدفوعات حسب الحالة الحقيقية للعملية.
enum PaymentTab { success, oneTime, refunded, pending, failed }

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
  RealtimeChannel? _billingCh;

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
    _tabs = TabController(length: PaymentTab.values.length, vsync: this);
    _tabs.addListener(() {
      if (mounted && !_tabs.indexIsChanging) setState(() {});
    });
    _loadAll();
    unawaited(_invoices.loadPayerInfo());
    final uid = sb.auth.currentUser?.id;
    if (uid != null && uid.isNotEmpty) {
      _billingCh = sb.channel('billing_history_$uid');
      _billingCh!.onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'billing_transactions',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'user_id',
          value: uid,
        ),
        callback: (_) {
          if (mounted) unawaited(_loadAll());
        },
      );
      _billingCh!.subscribe();
    }
  }

  String _formatLatinDate(DateTime? date) {
    if (date == null) return '';
    return InvoiceService.formatLatinDateTime(date.toLocal());
  }

  @override
  void dispose() {
    try {
      _billingCh?.unsubscribe();
    } catch (_) {}
    _tabs.dispose();
    _search.dispose();
    super.dispose();
  }

  Future<void> _loadAll() async {
    if (!mounted) return;
    setState(() => _loading = true);
    final search = _search.text.trim().isEmpty ? null : _search.text.trim();
    final all = await _repo.listTransactions(
      search: search,
      dateFilter: _dateFilter,
      limit: 400,
    );
    PaymentTab tabFor(Map<String, dynamic> row) {
      final st = BillingTransactionRepository.normalizedStatus(row);
      if (st == 'refunded' || st == 'partially_refunded') {
        return PaymentTab.refunded;
      }
      if (st == 'pending') return PaymentTab.pending;
      if (st == 'failed') return PaymentTab.failed;
      if (InvoiceCopy.isOneTimeRow(row)) return PaymentTab.oneTime;
      return PaymentTab.success;
    }

    if (!mounted) return;
    setState(() {
      for (final tab in PaymentTab.values) {
        _rowsByTab[tab] = all.where((r) => tabFor(r) == tab).toList();
      }
      _loading = false;
    });
  }

  String _tabLabel(PaymentTab tab) {
    final t = AppLocalizations.of(context)!;
    final n = _rowsByTab[tab]?.length ?? 0;
    final label = switch (tab) {
      PaymentTab.success => _isAr ? 'مكتملة' : t.subscriptionsFilterSuccess,
      PaymentTab.oneTime => _isAr ? 'مرة واحدة' : 'One-time',
      PaymentTab.refunded => _isAr ? 'مسترجعة' : 'Refunded',
      PaymentTab.pending => _isAr ? 'معلقة' : t.subscriptionsFilterPending,
      PaymentTab.failed => _isAr ? 'فاشلة' : t.subscriptionsFilterFailed,
    };
    return '$label · $n';
  }

  IconData _tabIcon(PaymentTab tab) => switch (tab) {
        PaymentTab.success => Icons.check_circle_outline,
        PaymentTab.oneTime => Icons.bolt_outlined,
        PaymentTab.refunded => Icons.replay_outlined,
        PaymentTab.pending => Icons.hourglass_top_outlined,
        PaymentTab.failed => Icons.error_outline,
      };

  Color _tabColor(PaymentTab tab) => switch (tab) {
        PaymentTab.success => const Color(0xFF1B873F),
        PaymentTab.oneTime => const Color(0xFF0F766E),
        PaymentTab.refunded => const Color(0xFF6D28D9),
        PaymentTab.pending => const Color(0xFFCC8400),
        PaymentTab.failed => const Color(0xFFC62828),
      };

  Widget _amountWidget(Map<String, dynamic> row) {
    final raw = row['amount'];
    final v =
        raw is num ? raw.toDouble() : double.tryParse('${raw ?? ''}') ?? 0.0;
    return AppMoneyLine(
      amount: v,
      currencyCode: '${row['currency'] ?? 'SAR'}'.toUpperCase(),
      isAr: _isAr,
      maxFractionDigits: 2,
      style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15),
    );
  }

  PaymentTab get _currentTab => PaymentTab.values[_tabs.index];

  List<Map<String, dynamic>> _rowsForTab(PaymentTab tab) =>
      _rowsByTab[tab] ?? const <Map<String, dynamic>>[];

  List<Map<String, dynamic>> get _currentTabRows => _rowsForTab(_currentTab);

  String _tabExportTitle(PaymentTab tab) => switch (tab) {
        PaymentTab.success => _isAr ? 'فواتير مكتملة' : 'Completed invoices',
        PaymentTab.oneTime =>
          _isAr ? 'عمليات لمرة واحدة' : 'One-time payments',
        PaymentTab.refunded => _isAr ? 'عمليات مستردة' : 'Refunded payments',
        PaymentTab.pending => _isAr ? 'عمليات معلقة' : 'Pending payments',
        PaymentTab.failed => _isAr ? 'عمليات فاشلة' : 'Failed payments',
      };

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
          'Invoices_${DateTime.now().toUtc().year}-${DateTime.now().toUtc().month.toString().padLeft(2, '0')}.xlsx';
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

  void _openInvoice(Map<String, dynamic> row) {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => InvoiceDetailScreen(
          row: row,
          lang: widget.lang,
          invoices: _invoices,
          onDeleted: () async {
            final res = await _repo.hideFromLedger('${row['id']}');
            if (!mounted) return;
            if (res['ok'] == true) await _loadAll();
          },
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
                  final doc = InvoiceDocument.fromRow(row, isAr: _isAr);
                  final date = DateTime.tryParse(
                    '${row['paid_at'] ?? row['completed_at'] ?? row['created_at']}',
                  );
                  final dateStr = _formatLatinDate(date);
                  return Card(
                    margin: const EdgeInsets.only(bottom: 10),
                    elevation: 1,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                      leading: Icon(_tabIcon(tab), color: color),
                      title: Text(
                        doc.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          height: 1.3,
                        ),
                      ),
                      subtitle: Text(
                        [
                          if (doc.hasInvoiceNumber) doc.invoiceNumber,
                          dateStr,
                          doc.methodLabel,
                        ].where((e) => e.isNotEmpty).join(' · '),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade700,
                          height: 1.35,
                        ),
                      ),
                      trailing: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          _amountWidget(row),
                          Text(
                            doc.statusLabel,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 11, color: color),
                          ),
                        ],
                      ),
                      onTap: () => _openInvoice(row),
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
                  Expanded(
                    child: PopupMenuButton<String>(
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
                      child: ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.date_range_outlined),
                        title: Text(
                          switch (_dateFilter) {
                            'today' => _isAr ? 'اليوم' : 'Today',
                            'week' => _isAr ? 'هذا الأسبوع' : 'This week',
                            'month' => _isAr ? 'هذا الشهر' : 'This month',
                            _ => _isAr ? 'كل الفترات' : 'All time',
                          },
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ),
                    ),
                  ),
                  PopupMenuButton<String>(
                    tooltip: _isAr ? 'تصدير وطباعة' : 'Export and print',
                    onSelected: (v) {
                      if (v == 'csv') unawaited(_exportCsv());
                      if (v == 'xlsx') unawaited(_exportExcel());
                      if (v == 'pdf') unawaited(_exportTabPdf());
                      if (v == 'print') unawaited(_printAll());
                    },
                    itemBuilder: (_) => [
                      PopupMenuItem(
                        value: 'print',
                        child: Text(_isAr ? 'طباعة التبويب' : 'Print tab'),
                      ),
                      PopupMenuItem(
                        value: 'pdf',
                        child: Text(_isAr ? 'تصدير PDF' : 'Export PDF'),
                      ),
                      const PopupMenuItem(
                        value: 'xlsx',
                        child: Text('Excel'),
                      ),
                      const PopupMenuItem(
                        value: 'csv',
                        child: Text('CSV'),
                      ),
                    ],
                    child: Padding(
                      padding: const EdgeInsetsDirectional.only(start: 8),
                      child: _exporting
                          ? const SizedBox(
                              width: 28,
                              height: 28,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Icon(
                              Icons.ios_share_outlined,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                    ),
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
