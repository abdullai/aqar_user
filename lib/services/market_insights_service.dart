// lib/services/market_insights_service.dart

import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/market_insights_snapshot.dart';

class MarketInsightsService {
  MarketInsightsService(this._sb);

  final SupabaseClient _sb;

  static bool _isMissingRpc(Object e) {
    if (e is PostgrestException) {
      final c = (e.code ?? '').trim();
      if (c == 'PGRST202' || c == '42883') return true;
      final m = e.message.toLowerCase();
      return m.contains('could not find the function') ||
          m.contains('function public.get_market_insights_snapshot') ||
          m.contains('does not exist');
    }
    final m = e.toString().toLowerCase();
    return m.contains('pgrst202') ||
        m.contains('could not find the function') ||
        (m.contains('get_market_insights_snapshot') &&
            m.contains('does not exist'));
  }

  Future<MarketInsightsSnapshot?> fetchSnapshot() async {
    try {
      final res = await _sb.rpc('get_market_insights_snapshot');
      return MarketInsightsSnapshot.tryParse(res) ??
          MarketInsightsSnapshot.empty();
    } catch (e) {
      if (_isMissingRpc(e)) {
        return MarketInsightsSnapshot.empty();
      }
      rethrow;
    }
  }
}
