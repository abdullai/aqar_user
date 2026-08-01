import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:excel/excel.dart';
import 'package:file_saver/file_saver.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/branding/app_branding.dart';
import '../core/branding/branding_pdf.dart';
import '../core/pdf/pdf_readable_qr.dart';

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

  /// قوالب جاهزة (معطيات تجريبية — استبدل بـ RPCs تحليلية عند توفرها).
  List<ReportConfig> getReportTemplates({bool isAr = false}) {
    if (isAr) {
      return [
        ReportConfig(
          id: 'team_activity_30d',
          title: 'نشاط الفريق (30 يوماً)',
          columns: const ['العضو', 'الإجراءات'],
          rows: const [
            ['—', 'اربط دالة تحليلات على الخادم'],
          ],
          filtersDescription: 'آخر 30 يوماً',
        ),
        ReportConfig(
          id: 'properties_by_member',
          title: 'العقارات حسب العضو',
          columns: const ['العضو', 'العدد'],
          rows: const [],
        ),
        ReportConfig(
          id: 'ads_by_member',
          title: 'الإعلانات المنشورة حسب العضو',
          columns: const ['العضو', 'العدد'],
          rows: const [],
        ),
        ReportConfig(
          id: 'join_requests',
          title: 'طلبات الانضمام',
          columns: const ['الحالة', 'العدد'],
          rows: const [],
        ),
        ReportConfig(
          id: 'payments',
          title: 'المدفوعات والاشتراكات',
          columns: const ['ملاحظة'],
          rows: const [
            ['اربط تصدير الفوترة عند توفره'],
          ],
        ),
        ReportConfig(
          id: 'sessions',
          title: 'جلسات المستخدمين',
          columns: const ['تلميح'],
          rows: const [
            ['استخدم شاشة سجل الجلسات ووظائف الخادم'],
          ],
        ),
      ];
    }
    return [
      ReportConfig(
        id: 'team_activity_30d',
        title: 'Team activity (30d)',
        columns: const ['Member', 'Actions'],
        rows: const [
          ['—', 'Connect analytics RPC'],
        ],
        filtersDescription: 'Last 30 days',
      ),
      ReportConfig(
        id: 'properties_by_member',
        title: 'Properties by member',
        columns: const ['Member', 'Count'],
        rows: const [],
      ),
      ReportConfig(
        id: 'ads_by_member',
        title: 'Published ads by member',
        columns: const ['Member', 'Count'],
        rows: const [],
      ),
      ReportConfig(
        id: 'join_requests',
        title: 'Join requests',
        columns: const ['Status', 'Count'],
        rows: const [],
      ),
      ReportConfig(
        id: 'payments',
        title: 'Payments & subscriptions',
        columns: const ['Note'],
        rows: const [
          ['Connect billing export when available'],
        ],
      ),
      ReportConfig(
        id: 'sessions',
        title: 'User sessions',
        columns: const ['Hint'],
        rows: const [
          ['Use Session History screen + server RPCs'],
        ],
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
    final now = DateFormat.yMMMd().add_Hm().format(DateTime.now());
    final doc = pw.Document();
    pw.Font baseFont = pw.Font.helvetica();
    pw.Font fontBold = pw.Font.helveticaBold();
    if (isAr) {
      try {
        final data = await rootBundle.load('assets/fonts/arabic_pdf_regular.ttf');
        final ttf = pw.Font.ttf(data);
        baseFont = ttf;
        fontBold = ttf;
      } catch (_) {}
    }
    final logo = await loadBrandingPdfLogo();
    final brandColor = tableHeaderColor ?? PdfColors.teal800;
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
              color: tableHeaderColor ?? PdfColors.teal700,
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
              data: '${cfg.id}\n${cfg.title}',
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
    sheet.appendRow([TextCellValue(AppBranding.legalName(isAr: isAr))]);
    sheet.appendRow([TextCellValue(cfg.title)]);
    sheet.appendRow([TextCellValue(_spreadsheetExporterLine(isAr))]);
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
    sb.writeln('# ${AppBranding.legalName(isAr: isAr)}');
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
