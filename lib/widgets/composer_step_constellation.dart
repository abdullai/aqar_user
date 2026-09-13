import 'dart:math' as math;

import 'package:flutter/material.dart';

/// نجوم خطوة المعالج — كل نجمة تُضاء عند الوصول إليها (بدل شريط تقدّم مسطّح فقط).
class ComposerStepConstellation extends StatefulWidget {
  const ComposerStepConstellation({
    super.key,
    required this.step,
    required this.total,
    required this.accent,
  });

  final int step;
  final int total;
  final Color accent;

  @override
  State<ComposerStepConstellation> createState() =>
      _ComposerStepConstellationState();
}

class _ComposerStepConstellationState extends State<ComposerStepConstellation>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final n = widget.total.clamp(1, 12);
    final active = widget.step.clamp(1, n);
    return AnimatedBuilder(
      animation: _pulse,
      builder: (context, _) {
        return SizedBox(
          height: 18,
          child: Row(
            children: [
              for (var i = 1; i <= n; i++) ...[
                if (i > 1)
                  Expanded(
                    child: Container(
                      height: 1.5,
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      color: i <= active
                          ? widget.accent.withValues(alpha: 0.55)
                          : widget.accent.withValues(alpha: 0.12),
                    ),
                  ),
                _StarDot(
                  lit: i < active,
                  current: i == active,
                  pulse: _pulse.value,
                  color: widget.accent,
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _StarDot extends StatelessWidget {
  const _StarDot({
    required this.lit,
    required this.current,
    required this.pulse,
    required this.color,
  });

  final bool lit;
  final bool current;
  final double pulse;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final t = current ? (0.72 + 0.28 * pulse) : 1.0;
    final size = current ? 11.0 : 7.0;
    return Transform.rotate(
      angle: current ? pulse * 0.35 : 0,
      child: Icon(
        lit || current ? Icons.star_rounded : Icons.star_outline_rounded,
        size: size * t,
        color: lit || current
            ? color.withValues(alpha: current ? 1 : 0.7)
            : color.withValues(alpha: 0.22),
      ),
    );
  }
}

/// مدار وسائط البطاقة: نقاط للصورة / الفيديو / الجولة تدور ببطء عند وجودها.
class ListingMediaStoryOrbit extends StatefulWidget {
  const ListingMediaStoryOrbit({
    super.key,
    required this.hasImage,
    required this.hasVideo,
    required this.hasTour,
    this.isAr = true,
  });

  final bool hasImage;
  final bool hasVideo;
  final bool hasTour;
  final bool isAr;

  @override
  State<ListingMediaStoryOrbit> createState() => _ListingMediaStoryOrbitState();
}

class _ListingMediaStoryOrbitState extends State<ListingMediaStoryOrbit>
    with SingleTickerProviderStateMixin {
  late final AnimationController _spin;

  @override
  void initState() {
    super.initState();
    _spin = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 8),
    )..repeat();
  }

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bits = <(IconData, Color)>[
      if (widget.hasImage) (Icons.photo_outlined, const Color(0xFF14B8A6)),
      if (widget.hasVideo) (Icons.videocam_outlined, const Color(0xFF6366F1)),
      if (widget.hasTour) (Icons.threed_rotation, const Color(0xFFF59E0B)),
    ];
    if (bits.isEmpty) return const SizedBox.shrink();
    final label = widget.isAr ? 'قصة العقار' : 'Listing story';
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _spin,
        builder: (context, _) {
          return Stack(
            children: [
              PositionedDirectional(
                bottom: 6,
                end: 6,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.55),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (var i = 0; i < bits.length; i++)
                        Transform.translate(
                          offset: Offset(
                            math.sin(_spin.value * 2 * math.pi + i) * 0.6,
                            math.cos(_spin.value * 2 * math.pi + i * 1.2) *
                                0.6,
                          ),
                          child: Padding(
                            padding: const EdgeInsetsDirectional.only(end: 3),
                            child: Icon(
                              bits[i].$1,
                              size: 13,
                              color: bits[i].$2,
                            ),
                          ),
                        ),
                      Text(
                        label,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 9.5,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
