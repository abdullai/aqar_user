part of 'user_dashboard.dart';

extension _UserDashboardState_ui_helpers on _UserDashboardState {
  // لون افتراضي (بدون الاعتماد على _bankColor داخل الـ State)
  static const Color _kPrimary = Color(0xFF0F766E);

  // =========================
  // Formatting
  // =========================
  String _fmtDateTime(DateTime? dt) {
    if (dt == null) return '';
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    final hh = dt.hour.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    return '$y-$m-$d $hh:$mm';
  }

  /// ✅ UI عندك يتوقع String وليس Widget
  String _tabTitle() {
    final ar = <String>[
      'الرئيسية',
      'إعلاناتي',
      'المفضلة',
      'السلة',
      'الحجوزات',
      'الدردشة',
    ];
    final en = <String>[
      'Home',
      'My Ads',
      'Favorites',
      'Cart',
      'Reservations',
      'Chat',
    ];

    final list = _isArabic ? ar : en;
    final i = (_tabIndex >= 0 && _tabIndex < list.length) ? _tabIndex : 0;
    return list[i];
  }

  String _failLoadTitle() =>
      _isArabic ? 'تعذر تحميل البيانات' : 'Failed to load data';

  String _failLoadSubtitle() => _isArabic
      ? 'تحقق من الإنترنت ثم أعد المحاولة.'
      : 'Check your internet connection and try again.';

  // =========================
  // Price row helper
  // =========================
  String _fmtMoney(dynamic v) {
    if (v == null) return '0';
    if (v is String) return v;
    if (v is num) {
      // بدون intl: تنسيق بسيط
      final s = v.toStringAsFixed(v % 1 == 0 ? 0 : 2);
      return s;
    }
    return v.toString();
  }

  /// ✅ يدعم value كـ double أو String + يدعم bold: true كما في ui.dart
  Widget _priceRow(
    BuildContext context, {
    required String label,
    required dynamic value,
    bool highlight = false,
    bool bold = false,
  }) {
    final txt = _fmtMoney(value);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontWeight: (bold || highlight) ? FontWeight.w700 : FontWeight.w600,
                color: highlight ? _kPrimary : null,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            txt,
            style: TextStyle(
              fontWeight: (bold || highlight) ? FontWeight.w900 : FontWeight.w800,
              color: highlight ? _kPrimary : null,
            ),
          ),
        ],
      ),
    );
  }

  // =========================
  // Filtering + sorting (typed)
  // =========================
  List<Property> _filterList(List<Property> src) {
    final q = _searchQuery.trim().toLowerCase();

    final filtered = src.where((p) {
      if (q.isEmpty) return true;
      return p.title.toLowerCase().contains(q) ||
          p.location.toLowerCase().contains(q) ||
          p.description.toLowerCase().contains(q);
    }).toList();

    _applyLocalSorting(filtered);
    return filtered;
  }

  void _applyLocalSorting(List<Property> list) {
    final sort = (_sortBy ?? 'latest').toString();

    if (sort == 'price_low') {
      list.sort((a, b) => a.price.compareTo(b.price));
      return;
    }
    if (sort == 'price_high') {
      list.sort((a, b) => b.price.compareTo(a.price));
      return;
    }

    // latest
    list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }
}
