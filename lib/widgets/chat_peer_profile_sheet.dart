import 'package:cached_network_image/cached_network_image.dart';

import 'package:flutter/material.dart';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/chat_peer_service.dart';

import 'app_logo_loading.dart';

String _initialLetter(String name) {
  final t = name.trim();

  if (t.isEmpty) return '?';

  return t.substring(0, 1).toUpperCase();
}

/// نافذة سفلية: صورة واسم المستخدم/المسوّق + نوع الحساب + تقييم.

Future<void> showChatPeerProfileSheet({
  required BuildContext context,
  required bool isAr,
  required String userId,
  SupabaseClient? supabase,
}) async {
  final sb = supabase ?? Supabase.instance.client;

  final cs = Theme.of(context).colorScheme;

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: cs.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) {
      return Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          bottom: MediaQuery.of(ctx).padding.bottom + 16,
          top: 8,
        ),
        child: _PeerProfileBody(
          isAr: isAr,
          userId: userId,
          sb: sb,
        ),
      );
    },
  );
}

class _PeerProfileBody extends StatefulWidget {
  final bool isAr;

  final String userId;

  final SupabaseClient sb;

  const _PeerProfileBody({
    required this.isAr,
    required this.userId,
    required this.sb,
  });

  @override
  State<_PeerProfileBody> createState() => _PeerProfileBodyState();
}

class _PeerProfileBodyState extends State<_PeerProfileBody> {
  bool _loading = true;

  Map<String, dynamic>? _row;

  String? _err;

  double _avgRating = 0;

  int _ratingCount = 0;

  int _myStars = 0;

  bool _ratingBusy = false;

  @override
  void initState() {
    super.initState();

    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;

      _err = null;
    });

    try {
      final r = await ChatPeerService.fetchProfile(widget.sb, widget.userId);

      final summary =
          await ChatPeerService.fetchRatingSummary(widget.sb, widget.userId);

      final my =
          await ChatPeerService.fetchMyStarsForPeer(widget.sb, widget.userId);

      if (!mounted) return;

      setState(() {
        _row = r;

        _avgRating = summary.avg;

        _ratingCount = summary.count;

        _myStars = my ?? 0;

        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _err = e.toString();

        _loading = false;
      });
    }
  }

  Future<void> _submitRating(int stars) async {
    final me = widget.sb.auth.currentUser?.id ?? '';

    if (me.isEmpty || me == widget.userId) return;

    setState(() => _ratingBusy = true);

    try {
      await ChatPeerService.upsertPeerRating(
        widget.sb,
        ratedUserId: widget.userId,
        stars: stars,
      );

      final summary =
          await ChatPeerService.fetchRatingSummary(widget.sb, widget.userId);

      if (!mounted) return;

      setState(() {
        _avgRating = summary.avg;

        _ratingCount = summary.count;

        _myStars = stars;
      });
    } catch (_) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content:
              Text(widget.isAr ? 'تعذر حفظ التقييم' : 'Could not save rating'),
        ),
      );
    } finally {
      if (mounted) setState(() => _ratingBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final ar = widget.isAr;

    if (_loading) {
      return const SizedBox(
        height: 220,
        child: Center(child: AppLogoLoading()),
      );
    }

    if (_err != null) {
      return SizedBox(
        height: 160,
        child: Center(
          child: Text(
            ar ? 'تعذر تحميل البيانات' : 'Failed to load profile',
            style: TextStyle(color: cs.error),
          ),
        ),
      );
    }

    final name = ChatPeerService.displayName(_row, ar);

    final av = (_row?['avatar_url'] ?? '').toString().trim();

    final acc = ChatPeerService.accountTypeLabel(
      _row?['account_type']?.toString(),
      ar,
    );

    final phone = (_row?['phone'] ?? '').toString().trim();

    final verified =
        (_row?['verification_status'] ?? '').toString().toLowerCase();

    final isVerified = verified == 'verified' ||
        verified == 'approved' ||
        verified == 'complete';

    final me = widget.sb.auth.currentUser?.id ?? '';

    final canRate = me.isNotEmpty && me != widget.userId;

    final wide = MediaQuery.sizeOf(context).width >= 720;

    final header = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          ar ? 'بيانات المستخدم' : 'User info',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w900,
              ),
        ),
        const SizedBox(height: 18),
        CircleAvatar(
          radius: 52,
          backgroundColor: cs.primaryContainer,
          backgroundImage:
              av.isNotEmpty ? CachedNetworkImageProvider(av) : null,
          child: av.isEmpty
              ? Text(
                  _initialLetter(name),
                  style: TextStyle(
                    fontSize: 36,
                    fontWeight: FontWeight.w900,
                    color: cs.onPrimaryContainer,
                  ),
                )
              : null,
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Flexible(
              child: Text(
                name,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 20,
                ),
              ),
            ),
            if (isVerified) ...[
              const SizedBox(width: 6),
              Icon(Icons.verified, color: cs.primary, size: 22),
            ],
          ],
        ),
        const SizedBox(height: 6),
        Text(
          acc,
          style: TextStyle(
            color: cs.onSurfaceVariant,
            fontWeight: FontWeight.w700,
            fontSize: 14,
          ),
        ),
        if (phone.isNotEmpty) ...[
          const SizedBox(height: 10),
          SelectableText(
            phone,
            style: TextStyle(
              fontWeight: FontWeight.w800,
              color: cs.onSurface,
              fontSize: 16,
            ),
          ),
        ],
      ],
    );

    final ratingCard = Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.65),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.star_rate_rounded, color: Colors.amber.shade700),
              const SizedBox(width: 8),
              Text(
                ar ? 'التقييم' : 'Rating',
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (_ratingCount > 0)
            Text(
              ar
                  ? 'متوسط ${_avgRating.toStringAsFixed(1)} من 5 ($_ratingCount تقييم)'
                  : 'Average ${_avgRating.toStringAsFixed(1)} / 5 ($_ratingCount ratings)',
              style: TextStyle(
                color: cs.onSurfaceVariant,
                fontWeight: FontWeight.w700,
              ),
            )
          else
            Text(
              ar ? 'لا توجد تقييمات بعد.' : 'No ratings yet.',
              style: TextStyle(
                color: cs.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
          if (canRate) ...[
            const SizedBox(height: 12),
            Text(
              ar ? 'قيّم تجربتك مع هذا المستخدم' : 'Rate your experience',
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
            ),
            const SizedBox(height: 6),
            Row(
              children: List.generate(5, (i) {
                final s = i + 1;
                final on = _myStars > 0 && s <= _myStars;
                return IconButton(
                  onPressed: _ratingBusy ? null : () => _submitRating(s),
                  icon: Icon(
                    on ? Icons.star : Icons.star_border,
                    color: Colors.amber.shade700,
                    size: 32,
                  ),
                );
              }),
            ),
          ],
        ],
      ),
    );

    if (wide) {
      return SizedBox(
        height: 440,
        child: DefaultTabController(
          length: 2,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TabBar(
                labelStyle: const TextStyle(fontWeight: FontWeight.w800),
                tabs: [
                  Tab(text: ar ? 'المعلومات' : 'Profile'),
                  Tab(text: ar ? 'التقييم' : 'Rating'),
                ],
              ),
              Expanded(
                child: TabBarView(
                  children: [
                    SingleChildScrollView(
                      child: Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: header,
                      ),
                    ),
                    SingleChildScrollView(
                      child: Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: ratingCard,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        header,
        const SizedBox(height: 12),
        Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            initiallyExpanded: true,
            title: Text(
              ar ? 'التقييم والخيارات' : 'Rating & options',
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
            childrenPadding:
                const EdgeInsets.only(left: 8, right: 8, bottom: 12),
            children: [ratingCard],
          ),
        ),
      ],
    );
  }
}
