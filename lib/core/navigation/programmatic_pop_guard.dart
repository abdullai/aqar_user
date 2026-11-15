import 'package:flutter/foundation.dart';

abstract final class ProgrammaticPopGuard {
  static int _depth = 0;

  static bool get isActive => _depth > 0;

  static void run(VoidCallback action) {
    _depth++;
    try {
      action();
    } finally {
      _depth--;
    }
  }
}
