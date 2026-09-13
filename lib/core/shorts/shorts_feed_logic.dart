import '../../models/market_property_request_row.dart';
import '../../models/property.dart';
import '../listing/listing_media_urls.dart';
import '../workflow/listing_workflow_stage.dart';

/// قواعد ظهور عنصر في شورتز العقار (وسائط حقيقية + غير مباع/منتهٍ).
abstract final class ShortsFeedLogic {
  static const _deadStatuses = <String>{
        'rented',
        'sold',
    'sold_out',
    'completed',
    'deal_completed',
    'ended',
    'expired',
    'terminated',
    'archived',
    'cancelled',
    'canceled',
    'closed',
    'inactive',
    'deleted',
    'removed',
    'hidden',
    'fulfilled',
  };

  static const _deadRequestStatuses = <String>{
    'completed',
    'cancelled',
    'canceled',
    'closed',
    'expired',
    'fulfilled',
    'deleted',
    'archived',
  };

  static bool propertyGone(Property p) {
    if (p.isDeletedLike) return true;
    if (p.terminatedAt != null || p.cancelledAt != null) return true;
    if (_deadStatuses.contains(p.normalizedStatus)) return true;
    final ws = p.effectiveWorkflowStage;
    return ws == ListingWorkflowStage.terminated ||
        ws == ListingWorkflowStage.archived ||
        ws == ListingWorkflowStage.cancelled ||
        ws == ListingWorkflowStage.inactive72h ||
        ws == ListingWorkflowStage.contractCancelled;
  }

  static bool propertyEligible(Property p) {
    if (propertyGone(p)) return false;
    if (ListingMediaUrls.propertyHasRealMedia(p)) return true;
    final tour = (p.virtualTourUrl ?? '').trim();
    return tour.startsWith('https://');
  }

  static bool requestGone(MarketPropertyRequestRow r) {
    if (r.completedAt != null) return true;
    if (r.deletionRequestedAt != null) return true;
    if ((r.selectedOfferId ?? '').trim().isNotEmpty) return true;
    return _deadRequestStatuses.contains(r.status.trim().toLowerCase());
  }

  static bool requestEligible(MarketPropertyRequestRow r) {
    if (requestGone(r)) return false;
    return true;
  }

  static const recycleAfter = Duration(hours: 48);

  static bool isFreshSeen(DateTime? seenAt, {DateTime? now}) {
    if (seenAt == null) return false;
    final n = now ?? DateTime.now();
    return n.difference(seenAt) < recycleAfter;
  }

  static bool purposeIsRent(String raw) {
    final p = raw.trim().toLowerCase();
    return p.contains('rent') ||
        p == 'daily_rent' ||
        p == 'monthly_rent' ||
        p == 'yearly_rent';
  }

  /// غير المشاهَد أولاً، ثم إعادة عرض الأقدم بعد دورة، دون إسقاط بقية السوق.
  static List<T> rankPlaylist<T>({
    required List<T> eligible,
    required String Function(T item) idOf,
    required DateTime Function(T item) dateOf,
    required int Function(T item) scoreOf,
    required Map<String, DateTime> seenAt,
    bool Function(T item)? featuredOf,
    Duration recycle = recycleAfter,
  }) {
    if (eligible.isEmpty) return const [];
    final now = DateTime.now();

    bool fresh(T e) {
      final t = seenAt[idOf(e)];
      if (t == null) return false;
      return now.difference(t) < recycle;
    }

    bool featured(T e) => featuredOf?.call(e) == true;

    final unseen = eligible.where((e) => !fresh(e)).toList(growable: false);
    final recycled = eligible.where(fresh).toList(growable: false)
      ..sort((a, b) {
        final sa = seenAt[idOf(a)] ?? now;
        final sb = seenAt[idOf(b)] ?? now;
        final c = sa.compareTo(sb);
        if (c != 0) return c;
        return dateOf(b).compareTo(dateOf(a));
      });

    final featuredUnseen = unseen.where(featured).toList()
      ..sort((a, b) => dateOf(b).compareTo(dateOf(a)));
    final restUnseen = unseen.where((e) => !featured(e)).toList()
      ..sort((a, b) => dateOf(b).compareTo(dateOf(a)));

    final trending = [...unseen]
      ..sort((a, b) {
        final s = scoreOf(b).compareTo(scoreOf(a));
        if (s != 0) return s;
        return dateOf(b).compareTo(dateOf(a));
      });

    final out = <T>[];
    final used = <String>{};
    var t = 0;

    void add(T item) {
      final id = idOf(item);
      if (!used.add(id)) return;
      out.add(item);
    }

    for (final hit in featuredUnseen) {
      add(hit);
    }

    for (var i = 0; i < restUnseen.length; i++) {
      add(restUnseen[i]);
      if ((i + 1) % 5 == 0) {
        while (t < trending.length) {
          final hit = trending[t++];
          if (!used.contains(idOf(hit)) && scoreOf(hit) > 0) {
            add(hit);
            break;
          }
        }
      }
    }

    for (final hit in recycled) {
      add(hit);
    }

    return out;
  }
}
