import 'package:flutter/material.dart';

import '../core/theme/app_accent.dart';
import '../core/config/app_config.dart';
import '../l10n/app_localizations.dart';

/// حوار اختيار لون التميّز — لا يُغلق إلا بزر الإغلاق (X).
/// اختيار اللون يطبّق فوراً على حساب المستخدم الحالي دون إغلاق الحوار.
Future<void> showAccentColorFirstRunDialog(BuildContext context) async {
  final t = AppLocalizations.of(context)!;
  final cs = Theme.of(context).colorScheme;
  final screen = MediaQuery.sizeOf(context);
  final narrow = screen.width < 420;
  final short = screen.height < 640;
  final maxDialogH = screen.height * (short ? 0.78 : 0.72);
  final initial = await currentAppAccentIndex();

  if (!context.mounted) return;

  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) {
      return _AccentColorPickerDialog(
        title: t.accentColorDialogTitle,
        body: t.accentColorDialogBody,
        hint: t.accentColorSkipKeepsDefault,
        closeLabel: t.onboardingClose,
        initialIndex: initial,
        narrow: narrow,
        maxDialogH: maxDialogH,
        colorScheme: cs,
      );
    },
  );
}

class _AccentColorPickerDialog extends StatefulWidget {
  const _AccentColorPickerDialog({
    required this.title,
    required this.body,
    required this.hint,
    required this.closeLabel,
    required this.initialIndex,
    required this.narrow,
    required this.maxDialogH,
    required this.colorScheme,
  });

  final String title;
  final String body;
  final String hint;
  final String closeLabel;
  final int initialIndex;
  final bool narrow;
  final double maxDialogH;
  final ColorScheme colorScheme;

  @override
  State<_AccentColorPickerDialog> createState() =>
      _AccentColorPickerDialogState();
}

class _AccentColorPickerDialogState extends State<_AccentColorPickerDialog> {
  late int _selected;

  @override
  void initState() {
    super.initState();
    _selected = widget.initialIndex.clamp(0, AppConfig.primaryAccentCount - 1);
  }

  @override
  Widget build(BuildContext context) {
    final cs = widget.colorScheme;
    final narrow = widget.narrow;
    final sw = MediaQuery.sizeOf(context).width;
    final cols = sw < 340 ? 3 : (sw < 420 ? 4 : 5);
    final gap = narrow ? 10.0 : 12.0;
    final circle = narrow ? 40.0 : 48.0;

    return PopScope(
      canPop: false,
      child: AlertDialog(
        insetPadding: EdgeInsets.symmetric(
          horizontal: narrow ? 16 : 24,
          vertical: MediaQuery.sizeOf(context).height < 640 ? 12 : 24,
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                widget.title,
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
            IconButton(
              tooltip: widget.closeLabel,
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.close_rounded),
            ),
          ],
        ),
        content: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 420,
            maxHeight: widget.maxDialogH,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  widget.body,
                  style: TextStyle(color: cs.onSurfaceVariant, height: 1.35),
                ),
                const SizedBox(height: 10),
                Text(
                  widget.hint,
                  style: TextStyle(
                    color: cs.onSurfaceVariant.withValues(alpha: 0.88),
                    height: 1.3,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 16),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final maxW = constraints.maxWidth;
                    final cell = (maxW - gap * (cols - 1)) / cols;
                    final size = cell.clamp(36.0, circle);
                    return Wrap(
                      spacing: gap,
                      runSpacing: gap,
                      alignment: WrapAlignment.center,
                      children:
                          List.generate(AppConfig.primaryAccentCount, (i) {
                        final selected = _selected == i;
                        return Material(
                          color: Colors.transparent,
                          child: InkWell(
                            customBorder: const CircleBorder(),
                            onTap: () async {
                              setState(() => _selected = i);
                              await setAppAccentIndex(i);
                            },
                            child: Ink(
                              width: size,
                              height: size,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: AppConfig.accentSeedAt(i),
                                border: Border.all(
                                  color: selected
                                      ? cs.onSurface
                                      : Colors.transparent,
                                  width: selected ? 3 : 0,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.12),
                                    blurRadius: 6,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: selected
                                  ? Icon(
                                      Icons.check_rounded,
                                      color: Colors.white,
                                      size: size * 0.45,
                                    )
                                  : null,
                            ),
                          ),
                        );
                      }),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
        actions: [
          FilledButton.tonal(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(widget.closeLabel),
          ),
        ],
      ),
    );
  }
}
