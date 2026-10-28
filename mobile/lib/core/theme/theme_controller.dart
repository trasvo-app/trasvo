// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0.
// If a copy of the MPL was not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';

import '../../data/settings/settings_repository.dart';

/// Tema actual. Antes de elegir (primer inicio) se previsualiza el del sistema.
class ThemeController extends ChangeNotifier {
  ThemeController(this._repository) : _saved = _repository.loadThemeMode();

  final SettingsRepository _repository;
  ThemeMode? _saved;
  ThemeMode? _preview;

  /// `false` hasta que el usuario confirma su elección.
  bool get hasChosen => _saved != null;

  ThemeMode get mode => _preview ?? _saved ?? ThemeMode.system;

  /// Cambia el tema en pantalla sin guardarlo.
  void preview(ThemeMode mode) {
    _preview = mode;
    notifyListeners();
  }

  /// Cambia y guarda el tema.
  Future<void> choose(ThemeMode mode) async {
    _saved = mode;
    _preview = null;
    notifyListeners();
    await _repository.saveThemeMode(mode);
  }
}
