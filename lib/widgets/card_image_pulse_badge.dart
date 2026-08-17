import 'package:flutter/material.dart';

/// نبضة خفيفة على شارة الصورة (عاجل / موثّق) — مستوحاة من نموذج البطاقات الشبكي.
class CardImagePulseBadge extends StatefulWidget {
  const CardImagePulseBadge({
    super.key,
    required this.label,
    required this.color,
    this.icon = Icons.bolt_rounded,
    this.prominent = false,
  });

  final String label;
  final Color color;
  final IconData icon;

  /// شارة أوضح للمستعجل المدفوع (وميض أقوى + حجم أكبر).
  final bool prominent;

  @override
  State<CardImagePulseBadge> createState() => _CardImagePulseBadgeState();
}

class _CardImagePulseBadgeState extends State<CardImagePulseBadge>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _pulse;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: widget.prominent ? 900 : 1400),
    )..repeat(reverse: true);
    _pulse = CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final prominent = widget.prominent;
    return AnimatedBuilder(
      animation: _pulse,
      builder: (context, child) {
        final t = _pulse.value;
        return Transform.scale(
          scale: 1.0 + (t * (prominent ? 0.08 : 0.04)),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: widget.color.withValues(alpha: 0.94),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.4 + t * 0.35),
                width: prominent ? 1.6 : 1.2,
              ),
              boxShadow: [
                BoxShadow(
                  color: widget.color.withValues(
                    alpha: (prominent ? 0.45 : 0.35) + t * 0.3,
                  ),
                  blurRadius: (prominent ? 12 : 8) + t * (prominent ? 10 : 6),
                  spreadRadius: t * (prominent ? 2.4 : 1.5),
                ),
              ],
            ),
            child: child,
          ),
        );
      },
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: prominent ? 12 : 8,
          vertical: prominent ? 6.5 : 4,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              widget.icon,
              size: prominent ? 15 : 11,
              color: Colors.white,
            ),
            const SizedBox(width: 5),
            Text(
              widget.label,
              maxLines: 1,
              softWrap: false,
              style: TextStyle(
                color: Colors.white,
                fontSize: prominent ? 12 : 9.5,
                fontWeight: FontWeight.w900,
                height: 1.0,
                letterSpacing: prominent ? 0.2 : 0,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
