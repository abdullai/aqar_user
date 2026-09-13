import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:aqar_user/core/session/user_appearance_session.dart';

void main() {
  test('parseMode maps stored theme tokens including system', () {
    expect(UserAppearanceSession.parseMode('system'), ThemeMode.system);
    expect(UserAppearanceSession.parseMode('light'), ThemeMode.light);
    expect(UserAppearanceSession.parseMode('dark'), ThemeMode.dark);
    expect(UserAppearanceSession.parseMode(null), ThemeMode.system);
    expect(UserAppearanceSession.parseMode(''), ThemeMode.system);
  });

  test('persistToken round-trips ThemeMode', () {
    expect(
      UserAppearanceSession.parseMode(
        UserAppearanceSession.persistToken(ThemeMode.system),
      ),
      ThemeMode.system,
    );
    expect(
      UserAppearanceSession.parseMode(
        UserAppearanceSession.persistToken(ThemeMode.light),
      ),
      ThemeMode.light,
    );
    expect(
      UserAppearanceSession.parseMode(
        UserAppearanceSession.persistToken(ThemeMode.dark),
      ),
      ThemeMode.dark,
    );
  });

  test('resolvesLight follows platform brightness in system mode', () {
    expect(
      UserAppearanceSession.resolvesLight(ThemeMode.light, Brightness.dark),
      isTrue,
    );
    expect(
      UserAppearanceSession.resolvesLight(ThemeMode.dark, Brightness.light),
      isFalse,
    );
    expect(
      UserAppearanceSession.resolvesLight(ThemeMode.system, Brightness.dark),
      isFalse,
    );
    expect(
      UserAppearanceSession.resolvesLight(ThemeMode.system, Brightness.light),
      isTrue,
    );
  });
}
