import 'package:flutter/material.dart';

/// شريحة اختيار ثابتة العرض — لا تتمدّد عند ظهور علامة الصح.
///
/// تستخدم في المرافق، الفلاتر، نعم/لا، وأي مكان كانت فيه Checkmark تسبب إزاحة.
class StableSelectChip extends StatelessWidget {
  const StableSelectChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onSelected,
    this.enabled = true,
    this.exclusive = false,
    this.showLeadingCheck = true,
    this.selectedColor,
    this.checkColor,
  });

  final String label;
  final bool selected;
  final ValueChanged<bool>? onSelected;
  final bool enabled;
  /// true → [ChoiceChip] (اختيار واحد)، false → [FilterChip].
  final bool exclusive;
  /// إن false: يعتمد التحديد على اللون فقط (بدون أيقونة).
  final bool showLeadingCheck;
  final Color? selectedColor;
  final Color? checkColor;

  static const double _slot = 18;

  Widget get _avatar {
    if (!showLeadingCheck) {
      return const SizedBox(width: _slot, height: _slot);
    }
    return SizedBox(
      width: _slot,
      height: _slot,
      child: Icon(
        selected ? Icons.check_circle_rounded : Icons.circle_outlined,
        size: _slot,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final onSel = enabled ? onSelected : null;
    if (exclusive) {
      return ChoiceChip(
        showCheckmark: false,
        avatar: _avatar,
        label: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
        selected: selected,
        onSelected: onSel,
        selectedColor: selectedColor,
        checkmarkColor: checkColor,
      );
    }
    return FilterChip(
      showCheckmark: false,
      avatar: _avatar,
      label: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
      selected: selected,
      onSelected: onSel,
      selectedColor: selectedColor,
      checkmarkColor: checkColor,
    );
  }
}
