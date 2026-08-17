import 'dart:async' show unawaited;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/branding/app_branding.dart';
import '../core/navigation/web_bootstrap_diag.dart';
import '../core/navigation/web_interaction_recovery.dart';
import '../l10n/app_localizations.dart';
import '../services/properties_home_feed_service.dart';

/// لوحة ويب خفيفة للضيف — بدون [UserDashboard] الثقيل (CanvasKit + بطاقات معقّدة).
/// الحل الجذري لتجمّد اللمس بعد الدخول كضيف على Flutter Web.
class WebGuestDashboard extends StatefulWidget {
  const WebGuestDashboard({super.key, required this.lang});

  final String lang;

  @override
  State<WebGuestDashboard> createState() => _WebGuestDashboardState();
}

class _WebGuestDashboardState extends State<WebGuestDashboard> {
  final _sb = Supabase.instance.client;

  bool _loading = true;
  String? _error;
  List<_GuestListingTile> _items = const [];
  int _tabIndex = 0;
  int _tapProbe = 0;

  bool get _isAr => widget.lang.toLowerCase() != 'en';

  @override
  void initState() {
    super.initState();
    if (!kIsWeb) return;
    WebBootstrapDiag.log('guest.dashboard', 'init lightweight guest UI');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      WebInteractionRecovery.dismissStuckOverlaysOnce();
      WebInteractionRecovery.scheduleDashboardRecovery(
        forDuration: const Duration(seconds: 60),
      );
      WebBootstrapDiag.armFreezeWatchdog('guest.after_first_frame');
    });
    unawaited(_loadFeed());
  }

  @override
  void dispose() {
    WebBootstrapDiag.disarmFreezeWatchdog('guest.after_first_frame');
    super.dispose();
  }

  String? _firstImageUrl(Map<String, dynamic> m) {
    final images = m['property_images'];
    if (images is! List || images.isEmpty) return null;
    String? bestPath;
    var bestOrder = 1 << 30;
    for (final raw in images) {
      if (raw is! Map) continue;
      final path = (raw['path'] ?? '').toString().trim();
      if (path.isEmpty) continue;
      final order = (raw['sort_order'] is num)
          ? (raw['sort_order'] as num).toInt()
          : 999;
      if (order < bestOrder) {
        bestOrder = order;
        bestPath = path;
      }
    }
    final path = (bestPath ?? '').trim();
    if (path.isEmpty) return null;
    if (path.startsWith('http://') || path.startsWith('https://')) return path;
    try {
      return _sb.storage.from('property-images').getPublicUrl(path);
    } catch (_) {
      return null;
    }
  }

  Future<void> _loadFeed() async {
    if (!mounted) return;
    WebBootstrapDiag.start('guest.feed');
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final raw = await PropertiesHomeFeedService.fetch(
        client: _sb,
        filterSuppressed: true,
        limit: 24,
        allowBypassCircuit: true,
      ).timeout(const Duration(seconds: 18));
      if (!mounted) return;
      final tiles = <_GuestListingTile>[];
      for (final row in raw) {
        if (row is! Map) continue;
        final m = Map<String, dynamic>.from(row);
        final id = (m['id'] ?? '').toString().trim();
        if (id.isEmpty) continue;
        final title = (m['title'] ?? m['name'] ?? '').toString().trim();
        final city = (m['city'] ?? '').toString().trim();
        final district = (m['district'] ?? '').toString().trim();
        final price = m['price'];
        final priceNum = price is num
            ? price.toDouble()
            : double.tryParse('$price') ?? 0;
        final purpose = (m['purpose'] ?? '').toString().trim();
        tiles.add(
          _GuestListingTile(
            id: id,
            title: title.isEmpty ? (_isAr ? 'إعلان عقاري' : 'Listing') : title,
            city: city,
            district: district,
            price: priceNum,
            purpose: purpose,
            imageUrl: _firstImageUrl(m),
          ),
        );
      }
      setState(() {
        _items = tiles;
        _loading = false;
      });
      WebBootstrapDiag.end('guest.feed', 'items=${tiles.length}');
      WebBootstrapDiag.disarmFreezeWatchdog('guest.after_first_frame');
    } catch (e) {
      WebBootstrapDiag.warn('guest.feed', e.toString());
      WebBootstrapDiag.disarmFreezeWatchdog('guest.after_first_frame');
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  void _goLogin() {
    WebInteractionRecovery.dismissStuckOverlaysOnce();
    Navigator.of(context, rootNavigator: true).pushNamedAndRemoveUntil(
      '/login',
      (r) => false,
    );
  }

  void _goRegister() {
    WebInteractionRecovery.dismissStuckOverlaysOnce();
    Navigator.of(context, rootNavigator: true).pushNamed('/register');
  }

  void _onProbeTap() {
    setState(() => _tapProbe++);
    WebInteractionRecovery.dismissStuckOverlaysOnce();
    WebBootstrapDiag.log('guest.tap', 'probe=$_tapProbe tab=$_tabIndex');
  }

  Future<void> _requireAuth(String featureAr, String featureEn) async {
    _onProbeTap();
    if (!mounted) return;
    final go = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                _isAr ? 'يلزم تسجيل الدخول' : 'Sign in required',
                textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
              ),
              const SizedBox(height: 8),
              Text(
                _isAr
                    ? 'لاستخدام «$featureAr» سجّل الدخول أو أنشئ حساباً.'
                    : 'To use "$featureEn", sign in or create an account.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(_isAr ? 'تسجيل الدخول' : 'Sign in'),
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: () {
                  Navigator.pop(ctx, false);
                  _goRegister();
                },
                child: Text(_isAr ? 'إنشاء حساب' : 'Create account'),
              ),
            ],
          ),
        );
      },
    );
    if (go == true && mounted) _goLogin();
  }

  void _onBottomSelected(int i) {
    if (i == 0 || i == 6) {
      _onProbeTap();
      setState(() => _tabIndex = i == 0 ? 0 : 1);
      return;
    }
    // زر + : نفس تدفق مايو — خياران ثم بوابة تسجيل الدخول.
    if (i == 3) {
      unawaited(_guestOpenPlusFlow());
      return;
    }
    const features = <(String, String)>[
      ('صفحتي', 'My page'),
      ('طلباتي/إعلاناتي', 'Requests/Listings'),
      ('إضافة إعلان', 'Post ad'),
      ('إدارتي', 'My desk'),
      ('صفقاتي', 'My deals'),
    ];
    final f = features[i - 1];
    unawaited(_requireAuth(f.$1, f.$2));
  }

  Future<void> _guestOpenPlusFlow() async {
    _onProbeTap();
    if (!mounted) return;
    final cs = Theme.of(context).colorScheme;
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: CircleAvatar(
                  backgroundColor: cs.primaryContainer,
                  child: Icon(
                    Icons.domain_add_rounded,
                    color: cs.onPrimaryContainer,
                  ),
                ),
                title: Text(
                  _isAr ? 'إعلان عقاري' : 'Property listing',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                subtitle: Text(
                  _isAr
                      ? 'نشر عقار للبيع أو الإيجار.'
                      : 'Publish a property for sale or rent.',
                  style: const TextStyle(fontSize: 12),
                ),
                onTap: () => Navigator.pop(ctx, 'listing'),
              ),
              ListTile(
                leading: CircleAvatar(
                  backgroundColor: cs.secondaryContainer,
                  child: Icon(
                    Icons.travel_explore_rounded,
                    color: cs.onSecondaryContainer,
                  ),
                ),
                title: Text(
                  _isAr ? 'طلب عقاري' : 'Property request',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                subtitle: Text(
                  _isAr
                      ? 'أبحث عن عقار للشراء أو الإيجار.'
                      : 'Looking to buy or rent.',
                  style: const TextStyle(fontSize: 12),
                ),
                onTap: () => Navigator.pop(ctx, 'request'),
              ),
            ],
          ),
        );
      },
    );
    if (!mounted || choice == null) return;
    final featureAr = choice == 'listing' ? 'إعلان عقاري' : 'طلب عقاري';
    final featureEn =
        choice == 'listing' ? 'Property listing' : 'Property request';
    await _requireAuth(featureAr, featureEn);
  }

  String _navLabel(String label) => label.replaceAll(' ', '\u00A0');

  Widget _guestAddChip(ColorScheme cs, {required bool filled}) {
    return Material(
      elevation: filled ? 12 : 8,
      surfaceTintColor: Colors.transparent,
      shadowColor: Colors.black38,
      shape: const CircleBorder(),
      color: cs.primary,
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: 46,
        height: 46,
        child: Center(
          child: Icon(Icons.add_rounded, size: 30, color: cs.onPrimary),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context);
    final selectedNav = _tabIndex == 0 ? 0 : 6;
    // نفس أسماء/أيقونات لوحة المستخدم المسجّل — الحماية عبر شيت الدخول.
    final home = l10n?.navHome ?? (_isAr ? 'الرئيسية' : 'Home');
    final myPage = l10n?.navMyAds ?? (_isAr ? 'صفحتي' : 'My page');
    final submissions =
        l10n?.navMySubmissions ?? (_isAr ? 'طلباتي/إعلاناتي' : 'Requests/Listings');
    final add = l10n?.navAdd ?? (_isAr ? 'إضافة إعلان' : 'Post ad');
    final desk = l10n?.navMyDesk ?? (_isAr ? 'إدارتي' : 'My desk');
    final cart = l10n?.navCart ?? (_isAr ? 'صفقاتي' : 'My deals');
    final support =
        l10n?.navSupport ?? (_isAr ? 'الدعم الفني' : 'Technical support');
    return Directionality(
      textDirection: _isAr ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        backgroundColor: cs.surface,
        appBar: AppBar(
          title: Text(_isAr ? 'موثوق عقاري' : 'Motawoq Real Estate'),
          actions: [
            TextButton(
              onPressed: _goLogin,
              child: Text(_isAr ? 'تسجيل الدخول' : 'Sign in'),
            ),
          ],
        ),
        body: _tabIndex == 0 ? _buildHomeBody(cs) : _buildSupportBody(cs),
        bottomNavigationBar: LayoutBuilder(
          builder: (context, constraints) {
            final iconOnly = constraints.maxWidth < 720;
            return NavigationBar(
              selectedIndex: selectedNav,
              height: iconOnly ? 64 : 80,
              labelBehavior: iconOnly
                  ? NavigationDestinationLabelBehavior.alwaysHide
                  : NavigationDestinationLabelBehavior.alwaysShow,
              onDestinationSelected: _onBottomSelected,
              destinations: [
                NavigationDestination(
                  icon: const Icon(Icons.home_outlined),
                  selectedIcon: const Icon(Icons.home),
                  label: _navLabel(home),
                ),
                NavigationDestination(
                  icon: const Icon(Icons.list_alt_outlined),
                  selectedIcon: const Icon(Icons.list_alt),
                  label: _navLabel(myPage),
                ),
                NavigationDestination(
                  icon: const Icon(Icons.assignment_turned_in_outlined),
                  selectedIcon: const Icon(Icons.assignment_turned_in),
                  label: _navLabel(submissions),
                ),
                NavigationDestination(
                  icon: _guestAddChip(cs, filled: false),
                  selectedIcon: _guestAddChip(cs, filled: true),
                  label: _navLabel(add),
                ),
                NavigationDestination(
                  icon: const Icon(Icons.dashboard_outlined),
                  selectedIcon: const Icon(Icons.dashboard),
                  label: _navLabel(desk),
                ),
                NavigationDestination(
                  icon: const Icon(Icons.handshake_outlined),
                  selectedIcon: const Icon(Icons.handshake),
                  label: _navLabel(cart),
                ),
                NavigationDestination(
                  icon: const Icon(Icons.support_agent_outlined),
                  selectedIcon: const Icon(Icons.support_agent),
                  label: _navLabel(support),
                ),
              ],
            );
          },
        ),
        floatingActionButton: kDebugMode
            ? FloatingActionButton.small(
                onPressed: _onProbeTap,
                child: Text('$_tapProbe'),
              )
            : null,
      ),
    );
  }

  Widget _buildSupportBody(ColorScheme cs) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.support_agent_rounded, size: 56, color: cs.primary),
            const SizedBox(height: 12),
            Text(
              _isAr ? 'الدعم متاح بعد تسجيل الدخول' : 'Support after sign-in',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _goLogin,
              child: Text(_isAr ? 'تسجيل الدخول' : 'Sign in'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHomeBody(ColorScheme cs) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.cloud_off_rounded, size: 48, color: cs.error),
              const SizedBox(height: 12),
              Text(
                _isAr ? 'تعذّر تحميل الإعلانات' : 'Could not load listings',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: () => unawaited(_loadFeed()),
                icon: const Icon(Icons.refresh_rounded),
                label: Text(_isAr ? 'إعادة المحاولة' : 'Retry'),
              ),
            ],
          ),
        ),
      );
    }
    if (_items.isEmpty) {
      return Center(
        child: Text(
          _isAr ? 'لا توجد إعلانات حالياً' : 'No listings yet',
          style: TextStyle(
            color: cs.onSurfaceVariant,
            fontWeight: FontWeight.w700,
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadFeed,
      child: ListView.separated(
        primary: false,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
        itemCount: _items.length + 1,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (context, index) {
          if (index == 0) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Text(
                _isAr
                    ? 'النتائج: ${_items.length} — تصفّح كضيف'
                    : 'Results: ${_items.length} — browsing as guest',
                style: TextStyle(
                  color: cs.onSurfaceVariant,
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                ),
              ),
            );
          }
          return _GuestListingCard(
            item: _items[index - 1],
            isAr: _isAr,
            onTap: () {
              unawaited(
                _requireAuth('تفاصيل الإعلان', 'listing details'),
              );
            },
          );
        },
      ),
    );
  }
}

class _GuestListingCard extends StatelessWidget {
  const _GuestListingCard({
    required this.item,
    required this.isAr,
    required this.onTap,
  });

  final _GuestListingTile item;
  final bool isAr;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final place = [
      if (item.city.isNotEmpty) item.city,
      if (item.district.isNotEmpty) item.district,
    ].join(' · ');

    return Material(
      color: cs.surfaceContainerLow,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AspectRatio(
              aspectRatio: 16 / 9,
              child: item.imageUrl != null && item.imageUrl!.isNotEmpty
                  ? CachedNetworkImage(
                      imageUrl: item.imageUrl!,
                      fit: BoxFit.cover,
                      filterQuality: FilterQuality.low,
                      memCacheWidth: kIsWeb ? 720 : 1000,
                      memCacheHeight: kIsWeb ? 405 : 560,
                      errorWidget: (_, __, ___) => _placeholder(cs),
                      placeholder: (_, __) => ColoredBox(
                        color: cs.surfaceContainerHighest,
                        child: const Center(
                          child: SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ),
                      ),
                    )
                  : _placeholder(cs),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    item.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 15,
                    ),
                  ),
                  if (place.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      place,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: cs.onSurfaceVariant,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                  if (item.price > 0) ...[
                    const SizedBox(height: 8),
                    Text(
                      isAr
                          ? '${item.price.toStringAsFixed(0)} ر.س'
                          : '${item.price.toStringAsFixed(0)} SAR',
                      style: TextStyle(
                        color: cs.primary,
                        fontWeight: FontWeight.w900,
                        fontSize: 16,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _placeholder(ColorScheme cs) {
    return ColoredBox(
      color: cs.surfaceContainerHighest,
      child: Center(
        child: Image.asset(
          AppBranding.listingPlaceholderAsset,
          width: 72,
          height: 72,
          fit: BoxFit.contain,
          errorBuilder: (_, __, ___) => Icon(
            Icons.home_work_outlined,
            size: 40,
            color: cs.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

class _GuestListingTile {
  const _GuestListingTile({
    required this.id,
    required this.title,
    required this.city,
    required this.district,
    required this.price,
    required this.purpose,
    this.imageUrl,
  });

  final String id;
  final String title;
  final String city;
  final String district;
  final double price;
  final String purpose;
  final String? imageUrl;
}
