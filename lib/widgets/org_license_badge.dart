import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';

/// شارة رخصة فال المعروضة للمنشأة (FAL-…).
class OrgLicenseBadge extends StatelessWidget {
  const OrgLicenseBadge({
    super.key,
    required this.code,
    this.compact = true,
  });

  final String code;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    final c = code.trim();
    if (c.isEmpty) return const SizedBox.shrink();
    final label = t?.orgFalBadge(c) ?? 'FAL $c';
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 8 : 10,
        vertical: compact ? 4 : 6,
      ),
      decoration: BoxDecoration(
        color: cs.primaryContainer.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: cs.primary.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.verified_outlined, size: compact ? 14 : 16, color: cs.primary),
          SizedBox(width: compact ? 4 : 6),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                    color: cs.onPrimaryContainer,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}
