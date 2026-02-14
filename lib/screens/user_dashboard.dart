// lib/screens/user_dashboard.dart
import 'dart:async';
import 'dart:convert';
import 'dart:math' as math; // ✅ REQUIRED for nearest (Haversine)

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// ✅ Provider
import 'package:provider/provider.dart';
import '../core/session/app_session.dart';

import '../main.dart';
import '../models/property.dart';
import '../services/reservations_service.dart';
import '../services/fast_login_service.dart' as fl_service;
import 'add_property_page.dart' as addp;
import 'property_details_page.dart' as details;
import 'settings_page.dart';
import 'edit_property_page.dart';
import 'chat_page.dart';
import 'login_screen.dart';
import 'support_page.dart';

part 'user_dashboard.ext.bodies.dart';
part 'user_dashboard.ext.build.dart';
part 'user_dashboard.ext.ui_helpers.dart';
part 'user_dashboard.ext.model_helpers.dart';
part 'user_dashboard.ext.notifications.dart';
part 'user_dashboard.ext.chat.dart';
part 'user_dashboard.actions.dart';
part 'user_dashboard.loaders.dart';
part 'user_dashboard.filters.dart';
part 'user_dashboard.state.dart';
part 'user_dashboard.widgets.dart';
part 'user_dashboard.ui.dart';
