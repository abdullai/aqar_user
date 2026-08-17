import 'package:flutter/material.dart';
import 'package:aqar_user/widgets/aqar_text_field.dart';

import '../main.dart' show langNotifier;
import '../services/report_service.dart';
import 'report_preview_screen.dart';

class CustomReportBuilderScreen extends StatefulWidget {
  const CustomReportBuilderScreen({super.key, this.initialConfig, this.lang});

  final ReportConfig? initialConfig;
  final String? lang;

  @override
  State<CustomReportBuilderScreen> createState() =>
      _CustomReportBuilderScreenState();
}

class _CustomReportBuilderScreenState extends State<CustomReportBuilderScreen> {
  late final TextEditingController _title;
  late final TextEditingController _cols;
  late final TextEditingController _filters;

  bool get _isAr =>
      (widget.lang ?? langNotifier.value).toLowerCase() != 'en';

  @override
  void initState() {
    super.initState();
    final i = widget.initialConfig;
    _title = TextEditingController(text: i?.title ?? 'Custom report');
    _cols = TextEditingController(
      text: i == null ? 'Col A, Col B' : i.columns.join(', '),
    );
    _filters = TextEditingController(text: i?.filtersDescription ?? '');
  }

  @override
  void dispose() {
    _title.dispose();
    _cols.dispose();
    _filters.dispose();
    super.dispose();
  }

  ReportConfig _buildCfg() {
    final parts = _cols.text
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    return ReportConfig(
      id: 'custom',
      title: _title.text.trim().isEmpty ? 'Report' : _title.text.trim(),
      columns: parts.isEmpty ? ['Column'] : parts,
      rows: widget.initialConfig?.rows ?? const [],
      filtersDescription: _filters.text.trim(),
    );
  }

  void _preview() {
    Navigator.push<void>(
      context,
      MaterialPageRoute<void>(
        builder: (_) => ReportPreviewScreen(
          config: _buildCfg(),
          lang: widget.lang,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isAr ? 'منشئ التقارير' : 'Report builder'),
        actions: [
          TextButton(
            onPressed: _preview,
            child: Text(_isAr ? 'معاينة' : 'Preview'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          AqarTextField(
            controller: _title,
            decoration: InputDecoration(
              labelText: _isAr ? 'عنوان التقرير' : 'Title',
            ),
          ),
          const SizedBox(height: 12),
          AqarTextField(
            controller: _cols,
            decoration: InputDecoration(
              labelText: _isAr
                  ? 'الأعمدة (مفصولة بفاصلة)'
                  : 'Columns (comma-separated)',
            ),
          ),
          const SizedBox(height: 12),
          AqarTextField(
            controller: _filters,
            maxLines: 2,
            decoration: InputDecoration(
              labelText: _isAr ? 'وصف الفلاتر' : 'Filter description',
            ),
          ),
          const SizedBox(height: 24),
          Text(
            _isAr
                ? 'يُربط لاحقاً باستعلامات خادم عند تفعيل view_reports / view_analytics.'
                : 'Wire server queries when analytics permissions are enabled.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: _preview,
            child: Text(_isAr ? 'معاينة وتصدير' : 'Preview & export'),
          ),
        ],
      ),
    );
  }
}
