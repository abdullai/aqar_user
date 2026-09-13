import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:excel/excel.dart';
import 'package:file_saver/file_saver.dart';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/branding/app_branding.dart';
import '../core/branding/branding_pdf.dart';
import '../core/payment/invoice_copy.dart';
import '../core/pdf/pdf_readable_qr.dart';
import '../core/utils/app_money.dart';
import '../core/utils/date_helper.dart';
import 'billing_transaction_repository.dart';
import 'org_team_service.dart';

/// تكوين تقرير بسيط + تصدير PDF / Excel / CSV — مع وسم مائي باسم المُصدِّر.
class ReportConfig {
  ReportConfig({
    required this.id,
    required this.title,
    required this.columns,
    this.rows = const [],
    this.filtersDescription = '',
  });

  final String id;
  final String title;
  final List<String> columns;
  final List<List<String>> rows;
  final String filtersDescription;
}

class ReportService {
  ReportService(this._client);

  final SupabaseClient _client;

  /// تقارير من بيانات الحساب الحقيقية (منشأة + فوترة + جلسات).
  Future<List<ReportConfig>> loadLiveReports({bool isAr = false}) async {
    final org = OrgTeamService(_client);
    final ctx = await org.myOrgContext();
    final orgId = '${ctx?['org_id'] ?? ''}'.trim();
    final none = isAr ? 'لا توجد بيانات في هذا الحساب حالياً' : 'No data on this account yet';

    String memberName(Map<String, dynamic> m) {
      final prof =
          (m['profile'] as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};
      final n = isAr
          ? '${prof['full_name_ar'] ?? prof['username'] ?? ''}'
          : '${prof['full_name_en'] ?? prof['username'] ?? ''}';
      final t = n.trim();
      return t.isEmpty ? '${m['user_id'] ?? ''}' : t;
    }

    List<List<String>> orEmpty(List<List<String>> rows, int cols) {
      if (rows.isNotEmpty) return rows;
      return [
        List<String>.generate(cols, (i) => i == 0 ? none : ''),
      ];
    }

    final members = orgId.isEmpty ? <Map<String, dynamic>>[] : await org.listMembers(orgId);
    final contrib = orgId.isEmpty
        ? <String, Map<String, int>>{}
        : await org.fetchOrgMemberContribution(orgId);
    final log = orgId.isEmpty
        ? <Map<String, dynamic>>[]
        : await org.activityLog(orgId, limit: 400);
    final joins = orgId.isEmpty
        ? <Map<String, dynamic>>[]
        : await org.listPendingJoinRequests();

    final cutoff = DateTime.now().subtract(const Duration(days: 30));
    final activityCounts = <String, int>{};
    for (final r in log) {
      final dt = DateTime.tryParse('${r['created_at']}');
      if (dt == null || dt.isBefore(cutoff)) continue;
      final uid = '${r['actor_user_id'] ?? ''}';
      if (uid.isEmpty) continue;
      activityCounts[uid] = (activityCounts[uid] ?? 0) + 1;
    }
    final nameById = <String, String>{
      for (final m in members) '${m['user_id']}': memberName(m),
    };

    final activityRows = activityCounts.entries
        .map(
          (e) => [
            nameById[e.key] ?? e.key,
            '${e.value}',
          ],
        )
        .toList()
      ..sort((a, b) => (int.tryParse(b[1]) ?? 0).compareTo(int.tryParse(a[1]) ?? 0));

    final propRows = <List<String>>[];
    final adsRows = <List<String>>[];
    for (final m in members) {
      final uid = '${m['user_id'] ?? ''}';
      final c = contrib[uid] ?? const {};
      propRows.add([memberName(m), '${c['properties'] ?? 0}']);
      adsRows.add([memberName(m), '${c['ads'] ?? 0}']);
    }

    final joinByStatus = <String, int>{};
    for (final r in joins) {
      var st = '${r['status'] ?? ''}'.trim();
      if (st.isEmpty) st = 'pending';
      joinByStatus[st] = (joinByStatus[st] ?? 0) + 1;
    }
    final joinRows = joinByStatus.entries
        .map((e) => [e.key, '${e.value}'])
        .toList();

    final billing = await BillingTransactionRepository(_client).list(limit: 200);
    final payRows = billing.map((r) {
      final raw = r['amount'];
      final v = raw is num
          ? raw.toDouble()
          : double.tryParse('${raw ?? ''}') ?? 0.0;
      final dt = DateTime.tryParse('${r['completed_at'] ?? r['created_at']}');
      return [
        '${r['invoice_number'] ?? ''}'.trim(),
        dt == null
            ? ''
            : DateHelper.fmtCivilDateTime(dt.toLocal(), isAr: false),
        AppBranding.billingTitleFromRow(r, isAr: isAr),
        AppMoney.formatForExport(v, isAr: isAr, maxFractionDigits: 2),
        BillingTransactionRepository.normalizedStatus(r),
        InvoiceCopy.methodLabel('${r['payment_method'] ?? ''}', isAr: isAr),
      ];
    }).toList();

    List<Map<String, dynamic>> sessions = [];
    try {
      dynamic raw = await _client.rpc('list_my_user_sessions');
      if (raw is String) {
        try {
          raw = jsonDecode(raw);
        } catch (_) {}
      }
      if (raw is List) {
        sessions = raw.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      }
    } catch (_) {}
    final sessionRows = sessions.map((s) {
      final login = DateHelper.fmtCivilDateTimeRaw(
        s['login_at'],
        isAr: isAr,
        fallback: '—',
      );
      final device = '${s['device_info'] ?? s['os_info'] ?? ''}'.trim();
      final loc = '${s['location'] ?? ''}'.trim();
      final active = s['is_active'] == true
          ? (isAr ? 'نشطة' : 'Active')
          : (isAr ? 'مغلقة' : 'Closed');
      return [
        login,
        device.isEmpty ? '—' : device,
        loc.isEmpty ? '—' : loc,
        active,
        '${s['login_method'] ?? ''}',
      ];
    }).toList();

    return [
      ReportConfig(
        id: 'team_activity_30d',
        title: isAr ? 'نشاط الفريق (30 يوماً)' : 'Team activity (30d)',
        columns: isAr
            ? const ['العضو', 'الإجراءات']
            : const ['Member', 'Actions'],
        rows: orEmpty(activityRows, 2),
        filtersDescription: isAr ? 'آخر 30 يوماً — من سجل المنشأة' : 'Last 30 days — org activity log',
      ),
      ReportConfig(
        id: 'properties_by_member',
        title: isAr ? 'العقارات حسب العضو' : 'Properties by member',
        columns: isAr ? const ['العضو', 'العدد'] : const ['Member', 'Count'],
        rows: orEmpty(propRows, 2),
      ),
      ReportConfig(
        id: 'ads_by_member',
        title: isAr ? 'الإعلانات المنشورة حسب العضو' : 'Published ads by member',
        columns: isAr ? const ['العضو', 'العدد'] : const ['Member', 'Count'],
        rows: orEmpty(adsRows, 2),
      ),
      ReportConfig(
        id: 'join_requests',
        title: isAr ? 'طلبات الانضمام' : 'Join requests',
        columns: isAr ? const ['الحالة', 'العدد'] : const ['Status', 'Count'],
        rows: orEmpty(joinRows, 2),
      ),
      ReportConfig(
        id: 'payments',
        title: isAr ? 'المدفوعات والاشتراكات' : 'Payments & subscriptions',
        columns: isAr
            ? const ['رقم', 'التاريخ', 'البيان', 'المبلغ', 'الحالة', 'الطريقة']
            : const ['Ref', 'Date', 'Description', 'Amount', 'Status', 'Method'],
        rows: orEmpty(payRows, 6),
        filtersDescription: isAr ? 'فواتيرك الحقيقية' : 'Your live billing rows',
      ),
      ReportConfig(
        id: 'sessions',
        title: isAr ? 'جلسات المستخدمين' : 'User sessions',
        columns: isAr
            ? const ['دخول', 'الجهاز', 'الموقع', 'الحالة', 'الطريقة']
            : const ['Login', 'Device', 'Location', 'Status', 'Method'],
        rows: orEmpty(sessionRows, 5),
      ),
    ];
  }

  /// للتوافق مع الشاشات القديمة — فضّل [loadLiveReports].
  List<ReportConfig> getReportTemplates({bool isAr = false}) {
    return [
      ReportConfig(
        id: 'loading',
        title: isAr ? 'جاري تحميل البيانات الحقيقية…' : 'Loading live data…',
        columns: isAr ? const ['ملاحظة'] : const ['Note'],
        rows: const [],
      ),
    ];
  }

  String _exporterWatermarkLabel() {
    final u = _client.auth.currentUser;
    final email = u?.email ?? '';
    final phone = u?.phone ?? '';
    final basis = email.isNotEmpty ? email : phone;
    if (basis.isEmpty) return 'user:${u?.id ?? ""}';
    final h = sha1.convert(utf8.encode(basis));
    return '${basis.substring(0, basis.length.clamp(0, 6))}… ${h.toString().substring(0, 8)}';
  }

  String _pdfGeneratedLabel(bool isAr, String now) =>
      isAr ? 'تاريخ الإنشاء: $now' : 'Generated: $now';

  String _pdfFiltersLabel(bool isAr, String filters) =>
      isAr ? 'الفلاتر: $filters' : 'Filters: $filters';

  String _pdfExportedBy(bool isAr, String wm) =>
      isAr ? 'صدر بواسطة $wm' : 'Exported by $wm';

  String _pdfFooterPage(bool isAr, int page, String wm) =>
      isAr ? 'صفحة $page — $wm' : 'Page $page — $wm';

  Future<Uint8List> exportToPdf(
    ReportConfig cfg, {
    PdfColor? tableHeaderColor,
    PdfColor? tableRowAltColor,
    bool isAr = false,
  }) async {
    final wm = _exporterWatermarkLabel();
    final now = DateHelper.fmtCivilDateTime(DateTime.now(), isAr: isAr);
    pw.Font baseFont = pw.Font.helvetica();
    pw.Font fontBold = pw.Font.helveticaBold();
    try {
      final data = await rootBundle.load('assets/fonts/arabic_pdf_regular.ttf');
      final ttf = pw.Font.ttf(data);
      baseFont = ttf;
      fontBold = ttf;
    } catch (_) {}
    final doc = pw.Document(theme: pw.ThemeData.withFont(base: baseFont, bold: fontBold));
    final logo = await loadBrandingPdfLogo();
    final brandColor = tableHeaderColor ?? kDocumentBrandPdfColor;
    final filtersMeta = cfg.filtersDescription.trim().isNotEmpty
        ? _pdfFiltersLabel(isAr, cfg.filtersDescription)
        : null;
    doc.addPage(
      pw.MultiPage(
        pageTheme: pw.PageTheme(
          margin: const pw.EdgeInsets.all(32),
          textDirection: isAr ? pw.TextDirection.rtl : pw.TextDirection.ltr,
        ),
        build: (ctx) => [
          brandingPdfHeader(
            base: baseFont,
            bold: fontBold,
            logo: logo,
            isAr: isAr,
            docTitle: cfg.title,
            brandColor: brandColor,
            metaLine: _pdfGeneratedLabel(isAr, now),
            subtitle: filtersMeta,
          ),
          pw.TableHelper.fromTextArray(
            headers: cfg.columns,
            data: cfg.rows,
            headerStyle: pw.TextStyle(
              font: fontBold,
              fontSize: 10,
              color: PdfColors.white,
            ),
            headerDecoration: pw.BoxDecoration(
              color: tableHeaderColor ?? kDocumentBrandPdfColor,
            ),
            cellStyle: pw.TextStyle(font: baseFont, fontSize: 9),
            cellHeight: 22,
            cellAlignments: {
              for (var i = 0; i < cfg.columns.length; i++)
                i: isAr ? pw.Alignment.centerRight : pw.Alignment.centerLeft,
            },
            oddRowDecoration: pw.BoxDecoration(
              color: tableRowAltColor ?? PdfColors.grey200,
            ),
          ),
          pw.SizedBox(height: 20),
          pw.Center(
            child: pdfReadableQrBlock(
              data: documentQrPlainText(
                isAr: isAr,
                kind: cfg.title,
                description: cfg.filtersDescription,
                paidAt: now,
                rowCount: cfg.rows.length,
              ),
              isAr: isAr,
              font: baseFont,
              fontBold: fontBold,
              size: 108,
              title: isAr ? 'مرجع التقرير (QR)' : 'Report reference (QR)',
              brandColor: brandColor,
            ),
          ),
          pw.SizedBox(height: 16),
          pw.Center(
            child: pw.Transform.rotate(
              angle: -0.35,
              child: pw.Opacity(
                opacity: 0.12,
                child: pw.Text(
                  _pdfExportedBy(isAr, wm),
                  style: pw.TextStyle(font: baseFont, fontSize: 22),
                ),
              ),
            ),
          ),
        ],
        footer: (ctx) => pw.Padding(
          padding: const pw.EdgeInsets.only(top: 8),
          child: pw.Text(
            _pdfFooterPage(isAr, ctx.pageNumber, wm),
            style: pw.TextStyle(font: baseFont, fontSize: 8),
            textAlign: pw.TextAlign.center,
          ),
        ),
      ),
    );
    return doc.save();
  }

  String _spreadsheetExporterLine(bool isAr) =>
      isAr ? 'الوَسم: ${_exporterWatermarkLabel()}' : 'Watermark: ${_exporterWatermarkLabel()}';

  Future<void> exportToExcel(
    ReportConfig cfg,
    String fileBaseName, {
    bool isAr = false,
  }) async {
    final excel = Excel.createExcel();
    final sheet = excel['Report'];
    for (final line in excelLetterheadLines(isAr: isAr, title: cfg.title)) {
      sheet.appendRow([TextCellValue(line)]);
    }
    sheet.appendRow([TextCellValue(_spreadsheetExporterLine(isAr))]);
    if (cfg.filtersDescription.trim().isNotEmpty) {
      sheet.appendRow([TextCellValue(cfg.filtersDescription)]);
    }
    sheet.appendRow([]);
    sheet.appendRow(cfg.columns.map(TextCellValue.new).toList());
    for (final r in cfg.rows) {
      sheet.appendRow(r.map(TextCellValue.new).toList());
    }
    final bytes = Uint8List.fromList(excel.encode()!);
    await FileSaver.instance.saveFile(
      name: fileBaseName,
      bytes: bytes,
      fileExtension: 'xlsx',
      mimeType: MimeType.microsoftExcel,
    );
  }

  Future<void> exportToCsv(
    ReportConfig cfg,
    String fileBaseName, {
    bool isAr = false,
  }) async {
    final sb = StringBuffer();
    for (final line in excelLetterheadLines(isAr: isAr, title: cfg.title)) {
      sb.writeln('# $line');
    }
    sb.writeln(
      isAr
          ? '# صاحب التصدير: ${_exporterWatermarkLabel()}'
          : '# Exporter: ${_exporterWatermarkLabel()}',
    );
    sb.writeln(cfg.columns.map(_csvEscape).join(','));
    for (final r in cfg.rows) {
      sb.writeln(r.map(_csvEscape).join(','));
    }
    final bytes = Uint8List.fromList(utf8.encode(sb.toString()));
    await FileSaver.instance.saveFile(
      name: fileBaseName,
      bytes: bytes,
      fileExtension: 'csv',
      mimeType: MimeType.csv,
    );
  }

  static String _csvEscape(String v) {
    final s = v.replaceAll('"', '""');
    if (s.contains(',') || s.contains('\n') || s.contains('"')) {
      return '"$s"';
    }
    return s;
  }

  /// DOCX غير مفعّل هنا — يصدّر CSV بنفس الاسم مع إشعار في الواجهة.
  Future<void> exportToWord(
    ReportConfig cfg,
    String fileBaseName, {
    bool isAr = false,
  }) =>
      exportToCsv(cfg, '${fileBaseName}_as_csv', isAr: isAr);

  Future<void> printReport(ReportConfig cfg, {bool isAr = false}) async {
    final bytes = await exportToPdf(cfg, isAr: isAr);
    await Printing.layoutPdf(onLayout: (_) async => bytes);
  }

  /// جدولة التقارير عبر البريد/التخزين تحتاج خادماً (Edge Functions + Cron) — غير مُنفَّذة في العميل.
  Future<Map<String, dynamic>> scheduleReport(
    ReportConfig cfg,
    String cronExpression,
  ) async {
    return {
      'ok': false,
      'error': 'server_scheduling_required',
      'hint': cronExpression,
    };
  }

  Future<Uint8List> generateReport(ReportConfig cfg, {bool isAr = false}) =>
      exportToPdf(cfg, isAr: isAr);
}
