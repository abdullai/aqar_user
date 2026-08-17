import 'package:flutter/material.dart';
import 'package:hijri/hijri_calendar.dart';

/// منتقي تاريخ الصك: ميلادي (تقويم) أو هجري (سنة/شهر/يوم) عبر حزمة [hijri].
Future<DateTime?> showDeedDateCalendarDialog({
  required BuildContext context,
  required bool isAr,
  DateTime? initialDate,
}) async {
  final now = DateTime.now();
  final first = DateTime(1900);
  final last = DateTime(now.year + 1, 12, 31);
  var g = initialDate ?? now;
  g = DateTime(g.year, g.month, g.day);
  if (g.isBefore(first)) g = first;
  if (g.isAfter(last)) g = last;

  return showDialog<DateTime>(
    context: context,
    builder: (ctx) => _DeedDateCalendarDialog(
      isAr: isAr,
      first: first,
      last: last,
      initialDate: g,
    ),
  );
}

class _DeedDateCalendarDialog extends StatefulWidget {
  final bool isAr;
  final DateTime first;
  final DateTime last;
  final DateTime initialDate;

  const _DeedDateCalendarDialog({
    required this.isAr,
    required this.first,
    required this.last,
    required this.initialDate,
  });

  @override
  State<_DeedDateCalendarDialog> createState() =>
      _DeedDateCalendarDialogState();
}

class _DeedDateCalendarDialogState extends State<_DeedDateCalendarDialog> {
  late DateTime selectedG;
  late int hYear;
  late int hMonth;
  late int hDay;
  int mode = 0;

  @override
  void initState() {
    super.initState();
    selectedG = widget.initialDate;
    final h = HijriCalendar.fromDate(selectedG);
    hYear = h.hYear;
    hMonth = h.hMonth;
    hDay = h.hDay;
  }

  int _daysInHijriMonth() {
    final cal = HijriCalendar();
    final d = cal.getDaysInMonth(hYear, hMonth);
    return d > 0 ? d : 30;
  }

  void _clampHijriDay() {
    final maxD = _daysInHijriMonth();
    if (hDay > maxD) hDay = maxD;
    if (hDay < 1) hDay = 1;
  }

  void _syncHijriFromGregorian() {
    final h = HijriCalendar.fromDate(selectedG);
    hYear = h.hYear;
    hMonth = h.hMonth;
    hDay = h.hDay;
  }

  void _syncGregorianFromHijri() {
    final cal = HijriCalendar();
    final g = cal.hijriToGregorian(hYear, hMonth, hDay);
    selectedG = DateTime(g.year, g.month, g.day);
    if (selectedG.isBefore(widget.first)) selectedG = widget.first;
    if (selectedG.isAfter(widget.last)) selectedG = widget.last;
  }

  void _submit() {
    if (mode == 0) {
      Navigator.pop(context, selectedG);
      return;
    }
    final cal = HijriCalendar();
    final g = cal.hijriToGregorian(hYear, hMonth, hDay);
    var out = DateTime(g.year, g.month, g.day);
    if (out.isBefore(widget.first)) out = widget.first;
    if (out.isAfter(widget.last)) out = widget.last;
    Navigator.pop(context, out);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final seg = <ButtonSegment<int>>[
      ButtonSegment(
        value: 0,
        label: Text(widget.isAr ? 'ميلادي' : 'Gregorian'),
      ),
      ButtonSegment(
        value: 1,
        label: Text(widget.isAr ? 'هجري' : 'Hijri'),
      ),
    ];

    return AlertDialog(
      title: Text(widget.isAr ? 'تاريخ الصك' : 'Deed date'),
      content: SizedBox(
        width: 400,
        height: 400,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SegmentedButton<int>(
              segments: seg,
              selected: {mode},
              onSelectionChanged: (s) {
                setState(() => mode = s.first);
              },
            ),
            const SizedBox(height: 12),
            Expanded(
              child: mode == 0
                  ? CalendarDatePicker(
                      key: ValueKey(selectedG),
                      initialDate: selectedG,
                      firstDate: widget.first,
                      lastDate: widget.last,
                      onDateChanged: (d) {
                        setState(() {
                          selectedG = DateTime(d.year, d.month, d.day);
                          _syncHijriFromGregorian();
                        });
                      },
                    )
                  : SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          DropdownButtonFormField<int>(
                            value: hYear,
                            decoration: InputDecoration(
                              labelText:
                                  widget.isAr ? 'السنة الهجرية' : 'Hijri year',
                            ),
                            items: List<int>.generate(
                              151,
                              (i) => 1350 + i,
                            )
                                .map(
                                  (y) => DropdownMenuItem(
                                    value: y,
                                    child: Text('$y'),
                                  ),
                                )
                                .toList(),
                            onChanged: (y) {
                              if (y == null) return;
                              setState(() {
                                hYear = y;
                                _clampHijriDay();
                                _syncGregorianFromHijri();
                              });
                            },
                          ),
                          const SizedBox(height: 12),
                          DropdownButtonFormField<int>(
                            value: hMonth,
                            decoration: InputDecoration(
                              labelText: widget.isAr ? 'الشهر' : 'Month',
                            ),
                            items: List<int>.generate(12, (i) => i + 1)
                                .map(
                                  (m) => DropdownMenuItem(
                                    value: m,
                                    child: Text('$m'),
                                  ),
                                )
                                .toList(),
                            onChanged: (m) {
                              if (m == null) return;
                              setState(() {
                                hMonth = m;
                                _clampHijriDay();
                                _syncGregorianFromHijri();
                              });
                            },
                          ),
                          const SizedBox(height: 12),
                          DropdownButtonFormField<int>(
                            value: hDay,
                            decoration: InputDecoration(
                              labelText: widget.isAr ? 'اليوم' : 'Day',
                            ),
                            items: List<int>.generate(
                              _daysInHijriMonth(),
                              (i) => i + 1,
                            )
                                .map(
                                  (d) => DropdownMenuItem(
                                    value: d,
                                    child: Text('$d'),
                                  ),
                                )
                                .toList(),
                            onChanged: (d) {
                              if (d == null) return;
                              setState(() {
                                hDay = d;
                                _syncGregorianFromHijri();
                              });
                            },
                          ),
                          const SizedBox(height: 12),
                          Text(
                            widget.isAr
                                ? 'يُخزَّن كتاريخ ميلادي بعد التحويل.'
                                : 'Stored as Gregorian after conversion.',
                            style: TextStyle(
                              fontSize: 12,
                              color: cs.onSurfaceVariant,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(widget.isAr ? 'إلغاء' : 'Cancel'),
        ),
        FilledButton(
          onPressed: _submit,
          child: Text(widget.isAr ? 'اختيار' : 'Select'),
        ),
      ],
    );
  }
}
