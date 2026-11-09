import 'package:flutter/material.dart';

class AqarSignatureHomeBanner extends StatelessWidget {
  const AqarSignatureHomeBanner({
    super.key,
    required this.isArabic,
    required this.listingCount,
    required this.requestCount,
    required this.onExploreMap,
    required this.onCompareProperties,
  });

  final bool isArabic;
  final int listingCount;
  final int requestCount;
  final VoidCallback onExploreMap;
  final VoidCallback onCompareProperties;

  static const Color _deepGreen = Color(0xFF062A25);
  static const Color _brandGreen = Color(0xFF0B5A49);
  static const Color _gold = Color(0xFFE4BF68);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final width = MediaQuery.sizeOf(context).width;
    final compact = width < 430;
    final titleStyle = theme.textTheme.headlineSmall?.copyWith(
      color: Colors.white,
      fontWeight: FontWeight.w900,
      fontSize: compact ? 21 : 25,
      height: 1.25,
    );
    final supportingStyle = theme.textTheme.bodyMedium?.copyWith(
      color: Colors.white.withValues(alpha: 0.82),
      fontWeight: FontWeight.w600,
      height: 1.5,
    );

    return RepaintBoundary(
      child: Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(16, 10, 16, 14),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(26),
          child: DecoratedBox(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: AlignmentDirectional.topStart,
                end: AlignmentDirectional.bottomEnd,
                colors: [_brandGreen, _deepGreen],
              ),
            ),
            child: Stack(
              children: [
                PositionedDirectional(
                  end: -30,
                  top: -52,
                  child: Container(
                    width: 184,
                    height: 184,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.08),
                        width: 1.2,
                      ),
                    ),
                  ),
                ),
                PositionedDirectional(
                  end: 14,
                  top: 26,
                  child: Icon(
                    Icons.apartment_rounded,
                    size: 112,
                    color: Colors.white.withValues(alpha: 0.055),
                  ),
                ),
                Padding(
                  padding: EdgeInsets.all(compact ? 18 : 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          const Icon(
                            Icons.location_city_rounded,
                            color: _gold,
                            size: 19,
                          ),
                          const SizedBox(width: 7),
                          Text(
                            isArabic
                                ? 'عقار  |  السوق السعودي'
                                : 'AQAR  |  SAUDI MARKET',
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: _gold,
                              fontWeight: FontWeight.w900,
                              letterSpacing: isArabic ? 0 : 1.1,
                            ),
                          ),
                          const Spacer(),
                          Icon(
                            Icons.auto_awesome_rounded,
                            color: _gold.withValues(alpha: 0.9),
                            size: 17,
                          ),
                        ],
                      ),
                      const SizedBox(height: 17),
                      Text(
                        isArabic
                            ? 'وجهتك العقارية،\nبرؤية أوضح.'
                            : 'Your real estate destination,\nwith a clearer view.',
                        style: titleStyle,
                      ),
                      const SizedBox(height: 7),
                      Text(
                        isArabic
                            ? 'اكتشف العقارات وطلبات السوق في مكان واحد.'
                            : 'Explore property listings and market requests in one place.',
                        style: supportingStyle,
                      ),
                      const SizedBox(height: 18),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          _FeedCountPill(
                            count: listingCount,
                            label: isArabic ? 'عقار' : 'Listings',
                          ),
                          _FeedCountPill(
                            count: requestCount,
                            label: isArabic ? 'طلب سوق' : 'Requests',
                          ),
                          FilledButton.icon(
                            onPressed: onExploreMap,
                            icon: const Icon(Icons.map_outlined, size: 19),
                            label: Text(
                              isArabic ? 'استكشف الخريطة' : 'Explore map',
                            ),
                            style: FilledButton.styleFrom(
                              backgroundColor: Colors.white,
                              foregroundColor: _deepGreen,
                              padding: const EdgeInsetsDirectional.fromSTEB(
                                15,
                                12,
                                15,
                                12,
                              ),
                              textStyle: theme.textTheme.labelLarge?.copyWith(
                                fontWeight: FontWeight.w900,
                              ),
                              shape: const StadiumBorder(),
                            ),
                          ),
                          if (listingCount >= 2)
                            OutlinedButton.icon(
                              onPressed: onCompareProperties,
                              icon: const Icon(Icons.compare_arrows_rounded,
                                  size: 19),
                              label: Text(
                                isArabic ? 'قارن العقارات' : 'Compare listings',
                              ),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.white,
                                side: BorderSide(
                                  color: Colors.white.withValues(alpha: 0.45),
                                ),
                                padding: const EdgeInsetsDirectional.fromSTEB(
                                  15,
                                  12,
                                  15,
                                  12,
                                ),
                                textStyle: theme.textTheme.labelLarge?.copyWith(
                                  fontWeight: FontWeight.w900,
                                ),
                                shape: const StadiumBorder(),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FeedCountPill extends StatelessWidget {
  const _FeedCountPill({required this.count, required this.label});

  final int count;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsetsDirectional.fromSTEB(11, 8, 11, 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.11),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
      ),
      child: Text(
        '$count $label',
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w800,
            ),
      ),
    );
  }
}
