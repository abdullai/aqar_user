import 'dart:async';

import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';

/// زر ⋮ لطلبات السوق على الرئيسية — نفس فكرة [ListingPublicActionsMenuButton] (نسخ، مشاركة، إخفاء، بلاغ).
class MarketRequestPublicActionsMenuButton extends StatelessWidget {
  const MarketRequestPublicActionsMenuButton({
    super.key,
    required this.colorScheme,
    this.homeFeedShowsHiddenOnly = false,
    this.onCopyLink,
    this.onShare,
    this.onHideFromHome,
    this.onReport,
    this.onRestoreToHome,
  });

  final ColorScheme colorScheme;
  final bool homeFeedShowsHiddenOnly;

  final Future<void> Function()? onCopyLink;
  final Future<void> Function()? onShare;
  final Future<void> Function()? onHideFromHome;
  final Future<void> Function()? onReport;
  final Future<void> Function()? onRestoreToHome;

  Future<void> _openMenu(BuildContext context) async {
    final l10n = AppLocalizations.of(context);
    if (l10n == null) return;
    const iconSz = 20.0;

    final items = <PopupMenuEntry<String>>[];
    if (onCopyLink != null) {
      items.add(
        PopupMenuItem<String>(
          value: 'copy',
          child: _MrMenuRow(
            icon: Icons.link_rounded,
            label: l10n.listingPublicCopyLink,
            iconSize: iconSz,
            colorScheme: colorScheme,
          ),
        ),
      );
    }
    if (onShare != null) {
      items.add(
        PopupMenuItem<String>(
          value: 'share',
          child: _MrMenuRow(
            icon: Icons.share_rounded,
            label: l10n.listingPublicShareLink,
            iconSize: iconSz,
            colorScheme: colorScheme,
          ),
        ),
      );
    }
    if (homeFeedShowsHiddenOnly) {
      if (onRestoreToHome != null) {
        items.add(
          PopupMenuItem<String>(
            value: 'restore',
            child: _MrMenuRow(
              icon: Icons.visibility_rounded,
              label: l10n.listingPublicShowOnHome,
              iconSize: iconSz,
              colorScheme: colorScheme,
            ),
          ),
        );
      }
    } else {
      if (onHideFromHome != null) {
        items.add(
          PopupMenuItem<String>(
            value: 'hide',
            child: _MrMenuRow(
              icon: Icons.visibility_off_outlined,
              label: l10n.listingPublicHideFromHome,
              iconSize: iconSz,
              colorScheme: colorScheme,
            ),
          ),
        );
      }
      if (onReport != null) {
        items.add(
          PopupMenuItem<String>(
            value: 'report',
            child: _MrMenuRow(
              icon: Icons.flag_outlined,
              label: l10n.listingPublicReport,
              iconSize: iconSz,
              colorScheme: colorScheme,
              foreground: colorScheme.error,
            ),
          ),
        );
      }
    }

    if (items.isEmpty) return;

    final rect = _MrMenuAnchorRect.getRect(context);
    final overlay = Navigator.of(context).overlay;
    if (overlay == null) return;
    final overlayBox = overlay.context.findRenderObject() as RenderBox?;
    if (overlayBox == null) return;
    final position = RelativeRect.fromRect(
      rect,
      Offset.zero & overlayBox.size,
    );

    final choice = await showMenu<String>(
      context: context,
      position: position,
      items: items,
    );

    if (!context.mounted) return;
    switch (choice) {
      case 'copy':
        if (onCopyLink != null) await onCopyLink!();
        break;
      case 'share':
        if (onShare != null) await onShare!();
        break;
      case 'hide':
        if (onHideFromHome != null) await onHideFromHome!();
        break;
      case 'report':
        if (onReport != null) await onReport!();
        break;
      case 'restore':
        if (onRestoreToHome != null) await onRestoreToHome!();
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    const iconSz = 20.0;
    const pad = 8.0;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: () => unawaited(_openMenu(context)),
        child: Container(
          padding: const EdgeInsets.all(pad),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.45),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
          ),
          child: Icon(Icons.more_vert, color: Colors.white, size: iconSz),
        ),
      ),
    );
  }
}

class _MrMenuRow extends StatelessWidget {
  const _MrMenuRow({
    required this.icon,
    required this.label,
    required this.iconSize,
    required this.colorScheme,
    this.foreground,
  });

  final IconData icon;
  final String label;
  final double iconSize;
  final ColorScheme colorScheme;
  final Color? foreground;

  @override
  Widget build(BuildContext context) {
    final fg = foreground ?? colorScheme.onSurface;
    return Row(
      children: [
        Icon(icon, size: iconSize + 1, color: fg),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: iconSize >= 19 ? 14.5 : 13.5,
              color: fg,
              height: 1.25,
            ),
          ),
        ),
      ],
    );
  }
}

class _MrMenuAnchorRect {
  static Rect getRect(BuildContext context) {
    final box = context.findRenderObject() as RenderBox?;
    final overlayState = Navigator.of(context).overlay;
    if (box == null || !box.hasSize || overlayState == null) {
      return Rect.zero;
    }
    final overlay = overlayState.context.findRenderObject() as RenderBox;
    final topLeft = box.localToGlobal(Offset.zero, ancestor: overlay);
    return Rect.fromLTWH(topLeft.dx, topLeft.dy, box.size.width, box.size.height);
  }
}
