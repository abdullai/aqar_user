// lib/services/market_insights_service.dart

import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/market_insights_snapshot.dart';

class MarketInsightsService {
  MarketInsightsService(this._sb);

  final SupabaseClient _sb;

  Future<MarketInsightsSnapshot?> fetchSnapshot() async {
    final res = await _sb.rpc('get_market_insights_snapshot');
    return MarketInsightsSnapshot.tryParse(res);
  }
}
