// lib/widgets/swipe_actions_tile.dart
//
// عنصر «بطاقة قابلة للسحب» يُظهر زرَّي إجراءَين (مثلاً «حذف» و«أرشفة») عند
// السحب يميناً (أو يساراً) على شاشات اللمس، مع زرَّي إجراءَين علنيَّين على
// الشاشات الكبيرة/المتصفّحات المكتبية حيث لا يكون السحب طبيعياً.
//
// التصميم:
// - شاشات كبيرة (web/desktop) أو حيث `forceButtonsAlways=true`:
//   نعرض زرَّي إجراء كأيقونتين بجوار محتوى الصف (يضعهما المستخدِم كـ
//   `trailing` يدوياً إذا أراد). هنا فقط نُغلِّف المحتوى وندع المستخدم يضيف
//   `trailingActions` كـ trailing داخل الـ `child`.
// - شاشات اللمس (مثلاً المتصفّحات الجوّالة): نُمكِّن السحب اليميني/اليساري
//   لإظهار لوحة إجراءَين خلف العنصر (Delete + Archive).
//
// لا نعتمد على حزمة `flutter_slidable` بحيث يبقى المشروع خفيفاً.

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// إجراء تظهره [SwipeActionsTile] خلف العنصر عند السحب.
class SwipeAction {
  const SwipeAction({
    required this.icon,
    required this.label,
    required this.color,
    required this.onPressed,
    this.foreground = Colors.white,
  });

  final IconData icon;
  final String label;
  final Color color;
  final Color foreground;
  final VoidCallback onPressed;
}

/// عنصر قابل للسحب لإظهار إجراءَين كحدّ أقصى (الحذف، الأرشفة، …).
/// يدعم اللغة العربية تلقائياً عبر [Directionality].
class SwipeActionsTile extends StatefulWidget {
  const SwipeActionsTile({
    super.key,
    required this.child,
    required this.actions,
    this.background,
    this.height,
    this.borderRadius = 12,
    this.actionWidth = 88,
  });

  /// محتوى الصف الرئيسي.
  final Widget child;

  /// قائمة الإجراءات المعروضة عند السحب (1 أو 2). يُعرض الأول الأقرب للنهاية.
  final List<SwipeAction> actions;

  /// لون خلفية الصفّ الرئيسي (يتبع `cardColor` افتراضياً).
  final Color? background;

  /// ارتفاع الصف. إن كان `null` يأخذ ارتفاع الـ`child` الطبيعي.
  final double? height;

  /// انحناء حواف الصف.
  final double borderRadius;

  /// عرض كل زر إجراء.
  final double actionWidth;

  @override
  State<SwipeActionsTile> createState() => _SwipeActionsTileState();
}

class _SwipeActionsTileState extends State<SwipeActionsTile>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;
  double _drag = 0.0;
  double _maxDrag = 176.0;
  bool _open = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    );
    _animation = const AlwaysStoppedAnimation<double>(0);
  }

  @override
  void didUpdateWidget(covariant SwipeActionsTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    final desiredMax = widget.actions.length * widget.actionWidth;
    if (desiredMax != _maxDrag) {
      _maxDrag = desiredMax;
      if (_open) {
        _drag = _maxDrag;
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _animateTo(double target) {
    _animation = Tween<double>(begin: _drag, end: target).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic),
    );
    _controller.forward(from: 0).then((_) {
      if (!mounted) return;
      setState(() {
        _drag = target;
        _open = target.abs() > 1;
      });
    });
    _animation.addListener(() {
      if (!mounted) return;
      setState(() => _drag = _animation.value);
    });
  }

  void _onHorizontalDragUpdate(DragUpdateDetails d, bool isRtl) {
    final dx = d.primaryDelta ?? 0;
    setState(() {
      // RTL: السحب لليمين على شاشة المستخدم = delta سالب فعلياً عند بعض
      // الإيماءات. نتعامل مع `_drag` كموجب يعني «انكشاف الأزرار».
      double next = _drag + (isRtl ? -dx : dx);
      if (next < 0) next = 0;
      if (next > _maxDrag) next = _maxDrag;
      _drag = next;
    });
  }

  void _onHorizontalDragEnd(DragEndDetails d, bool isRtl) {
    final v = d.primaryVelocity ?? 0;
    final shouldOpen = _drag > _maxDrag / 2.0 ||
        (isRtl ? v < -300 : v > 300);
    _animateTo(shouldOpen ? _maxDrag : 0);
  }

  void _runAndClose(SwipeAction action) {
    action.onPressed();
    _animateTo(0);
  }

  bool get _isTouchPlatform {
    if (!kIsWeb) return true; // mobile/desktop apps - allow swipe everywhere
    // على الويب: نُمكِّن السحب فقط على الشاشات الضيقة (متصفح الجوال).
    final w = MediaQuery.sizeOf(context).width;
    return w < 800;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isRtl = Directionality.of(context) == TextDirection.rtl;
    final bg = widget.background ?? Theme.of(context).cardColor;
    final actionsTotalWidth = _maxDrag;
    final actions = widget.actions;

    if (!_isTouchPlatform) {
      return widget.child;
    }

    final actionsRow = Row(
      children: [
        for (final a in actions)
          Container(
            width: widget.actionWidth,
            color: a.color,
            alignment: Alignment.center,
            child: InkWell(
              onTap: () => _runAndClose(a),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 12),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(a.icon, color: a.foreground),
                    const SizedBox(height: 4),
                    Text(
                      a.label,
                      style: TextStyle(
                        color: a.foreground,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                      ),
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );

    // مهم: لا نضع كل الأبناء كـ Positioned داخل Stack داخل ListView —
    // ذلك يجعل ارتفاع الصف صفراً فيختفي المحتوى حتى يُعاد البناء بدون السحب.
    final dx = isRtl ? _drag : -_drag;

    return ClipRRect(
      borderRadius: BorderRadius.circular(widget.borderRadius),
      child: Stack(
        alignment: AlignmentDirectional.centerStart,
        children: [
          PositionedDirectional(
            top: 0,
            bottom: 0,
            end: 0,
            width: actionsTotalWidth,
            child: Container(
              color: cs.surfaceContainerHighest,
              child: actionsRow,
            ),
          ),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            dragStartBehavior: DragStartBehavior.start,
            onHorizontalDragUpdate: (d) =>
                _onHorizontalDragUpdate(d, isRtl),
            onHorizontalDragEnd: (d) => _onHorizontalDragEnd(d, isRtl),
            onTap: _open ? () => _animateTo(0) : null,
            child: Transform.translate(
              offset: Offset(dx, 0),
              child: Container(
                color: bg,
                width: double.infinity,
                height: widget.height,
                child: widget.child,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
