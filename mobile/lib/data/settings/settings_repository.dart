// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0.
// If a copy of the MPL was not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Preferencias guardadas en el celular.
class SettingsRepository {
  SettingsRepository(this._prefs);

  static const _themeKey = 'theme';

  final SharedPreferences _prefs;

  /// `null` si el usuario todavía no eligió (primer inicio).
  ThemeMode? loadThemeMode() {
    return switch (_prefs.getString(_themeKey)) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => null,
    };
  }

  Future<void> saveThemeMode(ThemeMode mode) {
    assert(mode != ThemeMode.system, 'Only light or dark can be saved');
    return _prefs.setString(_themeKey, mode == ThemeMode.dark ? 'dark' : 'light');
  }
}
