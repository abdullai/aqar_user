import 'dart:convert';

/// Reads real deed metadata from a request/preview row. Never invents values:
/// missing data yields an empty string.
abstract final class DeedRowMeta {
  static const _numberKeys = [
    'deed_number',
    'preview_deed_number',
    'request_deed_number',
  ];
  static const _dateKeys = [
    'deed_date',
    'preview_deed_date',
    'request_deed_date',
  ];

  static Map<String, dynamic> _payload(Map<String, dynamic> r) {
    for (final k in const ['payload_json', 'payload']) {
      final p = r[k];
      if (p is Map) return Map<String, dynamic>.from(p);
      if (p is String && p.trim().startsWith('{')) {
        try {
          final d = jsonDecode(p);
          if (d is Map) return Map<String, dynamic>.from(d);
        } catch (_) {}
      }
    }
    return const {};
  }

  static String _first(Map<String, dynamic> m, List<String> keys) {
    for (final k in keys) {
      final v = (m[k] ?? '').toString().trim();
      if (v.isNotEmpty && v.toLowerCase() != 'null') return v;
    }
    return '';
  }

  static String number(Map<String, dynamic> row, [String? fromProperty]) {
    final p = (fromProperty ?? '').trim();
    if (p.isNotEmpty) return p;
    final direct = _first(row, _numberKeys);
    return direct.isNotEmpty ? direct : _first(_payload(row), _numberKeys);
  }

  /// Stored date text from the row/payload; empty when absent.
  static String date(Map<String, dynamic> row) {
    final direct = _first(row, _dateKeys);
    return direct.isNotEmpty ? direct : _first(_payload(row), _dateKeys);
  }
}
