import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';

/// اسم مصور مع أيقونة كاميرا عند التوثيق.
class CertifiedPhotographerName extends StatelessWidget {
  const CertifiedPhotographerName({
    super.key,
    required this.name,
    this.verified = false,
    this.style,
  });

  final String name;
  final bool verified;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (verified) ...[
          Icon(
            Icons.photo_camera_outlined,
            size: 16,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(width: 4),
        ],
        Flexible(
          child: Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: style ?? const TextStyle(fontWeight: FontWeight.w800),
          ),
        ),
        if (verified && l10n != null) ...[
          const SizedBox(width: 4),
          Tooltip(
            message: l10n.photographerCertifiedTooltip,
            child: Icon(
              Icons.verified,
              size: 16,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
        ],
      ],
    );
  }
}
