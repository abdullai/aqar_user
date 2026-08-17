import 'package:flutter/foundation.dart';



/// يمنع لوحتين [UserDashboard] على الويب — سبب «Page Unresponsive» وتجمّد اللمس.

abstract final class WebDashboardMountGuard {

  static int _active = 0;



  static bool claim() {

    if (!kIsWeb) return true;

    _active++;

    return _active == 1;

  }



  static void release() {

    if (!kIsWeb) return;

    if (_active > 0) _active--;

  }



  static bool get hasDuplicate => kIsWeb && _active > 1;

}



/// يمنع تشغيل bootstrap مرتين عند وجود نسختين من اللوحة.

abstract final class WebDashboardBootstrapGuard {

  static bool _started = false;



  static bool tryStart() {

    if (!kIsWeb) return true;

    if (_started) return false;

    _started = true;

    return true;

  }



  static void reset() {

    _started = false;

  }

}

