import 'package:flutter/material.dart';

import '../core/utils/date_helper.dart';
import 'equal_option_tile_grid.dart';

/// مدة الإيجار: يومي / أسبوعي / شهري / سنوي مع بداية ونهاية محسوبة (إعلان وطلب).
class RentTermScheduleFields extends StatelessWidget {
  const RentTermScheduleFields({
    super.key,
    required this.isAr,
    required this.busy,
    required this.rentTerm,
    required this.rentDays,
    required this.rentWeeks,
    required this.rentMonths,
    required this.rentYears,
    required this.rentStart,
    required this.rentEnd,
    required this.onTerm,
    required this.onDays,
    required this.onWeeks,
    required this.onMonths,
    required this.onYears,
    required this.onPickStart,
  });

  final bool isAr;
  final bool busy;
  final String rentTerm;
  final int rentDays;
  final int rentWeeks;
  final int rentMonths;
  final int rentYears;
  final DateTime? rentStart;
  final DateTime? rentEnd;
  final ValueChanged<String> onTerm;
  final ValueChanged<int> onDays;
  final ValueChanged<int> onWeeks;
  final ValueChanged<int> onMonths;
  final ValueChanged<int> onYears;
  final VoidCallback onPickStart;

  static String gregorianLabel(DateTime d, {required bool isAr}) =>
      DateHelper.fmtCivilDate(d, isAr: isAr);

  static String hijriLabel(DateTime d, {required bool isAr}) =>
      DateHelper.fmtHijriDate(d, isAr: isAr);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    Widget dateBox({
      required String label,
      required DateTime? value,
      required VoidCallback? onTap,
      bool locked = false,
    }) {
      final g = value == null ? '—' : gregorianLabel(value, isAr: isAr);
      final h = value == null ? '' : hijriLabel(value, isAr: isAr);
      return InkWell(
        onTap: busy || locked ? null : onTap,
        borderRadius: BorderRadius.circular(14),
        child: InputDecorator(
          decoration: InputDecoration(
            labelText: label,
            border: const OutlineInputBorder(),
            suffixIcon: locked
                ? Icon(Icons.lock_outline, color: cs.primary, size: 18)
                : const Icon(Icons.event_outlined, size: 20),
          ),
          child: Text(
            h.isEmpty ? g : '$g  ·  $h',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              fontFamily: 'Cairo',
            ),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 12),
        Text(
          isAr ? 'مدة الإيجار' : 'Rent period',
          style: const TextStyle(fontWeight: FontWeight.w900, fontFamily: 'Cairo'),
        ),
        const SizedBox(height: 8),
        EqualOptionTileGrid(
          children: [
            for (final e in [
              ('daily', isAr ? 'يومي' : 'Daily'),
              ('weekly', isAr ? 'أسبوعي' : 'Weekly'),
              ('monthly', isAr ? 'شهري' : 'Monthly'),
              ('yearly', isAr ? 'سنوي' : 'Yearly'),
            ])
              EqualSelectTile(
                label: e.$2,
                selected: rentTerm == e.$1,
                enabled: !busy,
                onTap: () => onTerm(e.$1),
              ),
          ],
        ),
        if (rentTerm == 'daily') ...[
          const SizedBox(height: 10),
          DropdownButtonFormField<int>(
            initialValue: rentDays,
            decoration: InputDecoration(
              labelText: isAr ? 'عدد الأيام' : 'Days',
              border: const OutlineInputBorder(),
            ),
            items: [
              for (var n = 1; n <= 6; n++)
                DropdownMenuItem(value: n, child: Text('$n')),
            ],
            onChanged: busy
                ? null
                : (v) {
                    if (v == null) return;
                    onDays(v);
                  },
          ),
          const SizedBox(height: 10),
          if (rentDays == 1)
            dateBox(
              label: isAr ? 'التاريخ المرغوب' : 'Desired date',
              value: rentStart,
              onTap: onPickStart,
            )
          else ...[
            dateBox(
              label: isAr ? 'البداية' : 'Start',
              value: rentStart,
              onTap: onPickStart,
            ),
            const SizedBox(height: 8),
            dateBox(
              label: isAr ? 'النهاية' : 'End',
              value: rentEnd,
              onTap: null,
              locked: true,
            ),
          ],
        ],
        if (rentTerm == 'weekly') ...[
          const SizedBox(height: 10),
          DropdownButtonFormField<int>(
            initialValue: rentWeeks,
            decoration: InputDecoration(
              labelText: isAr ? 'عدد الأسابيع' : 'Weeks',
              border: const OutlineInputBorder(),
            ),
            items: [
              for (var n = 1; n <= 3; n++)
                DropdownMenuItem(value: n, child: Text('$n')),
            ],
            onChanged: busy
                ? null
                : (v) {
                    if (v == null) return;
                    onWeeks(v);
                  },
          ),
          const SizedBox(height: 10),
          dateBox(
            label: isAr ? 'البداية' : 'Start',
            value: rentStart,
            onTap: onPickStart,
          ),
          const SizedBox(height: 8),
          dateBox(
            label: isAr ? 'النهاية' : 'End',
            value: rentEnd,
            onTap: null,
            locked: true,
          ),
        ],
        if (rentTerm == 'monthly') ...[
          const SizedBox(height: 10),
          DropdownButtonFormField<int>(
            initialValue: rentMonths.clamp(1, 12),
            decoration: InputDecoration(
              labelText: isAr ? 'عدد الأشهر' : 'Months',
              border: const OutlineInputBorder(),
            ),
            items: [
              for (var n = 1; n <= 12; n++)
                DropdownMenuItem(value: n, child: Text('$n')),
            ],
            onChanged: busy
                ? null
                : (v) {
                    if (v == null) return;
                    onMonths(v);
                  },
          ),
          const SizedBox(height: 10),
          dateBox(
            label: isAr ? 'البداية' : 'Start',
            value: rentStart,
            onTap: onPickStart,
          ),
          const SizedBox(height: 8),
          dateBox(
            label: isAr ? 'النهاية' : 'End',
            value: rentEnd,
            onTap: null,
            locked: true,
          ),
        ],
        if (rentTerm == 'yearly') ...[
          const SizedBox(height: 10),
          DropdownButtonFormField<int>(
            initialValue: rentYears,
            decoration: InputDecoration(
              labelText: isAr ? 'عدد السنوات' : 'Years',
              border: const OutlineInputBorder(),
            ),
            items: [
              for (var n = 1; n <= 10; n++)
                DropdownMenuItem(value: n, child: Text('$n')),
            ],
            onChanged: busy
                ? null
                : (v) {
                    if (v == null) return;
                    onYears(v);
                  },
          ),
          const SizedBox(height: 10),
          dateBox(
            label: isAr ? 'البداية' : 'Start',
            value: rentStart,
            onTap: onPickStart,
          ),
          const SizedBox(height: 8),
          dateBox(
            label: isAr ? 'النهاية' : 'End',
            value: rentEnd,
            onTap: null,
            locked: true,
          ),
        ],
      ],
    );
  }
}
