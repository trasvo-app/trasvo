// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0.
// If a copy of the MPL was not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'tokens.dart';

abstract final class AppTheme {
  static ThemeData light() => _build(AppColors.light, Brightness.light);

  static ThemeData dark() => _build(AppColors.dark, Brightness.dark);

  static ThemeData _build(AppColors c, Brightness brightness) {
    final scheme = ColorScheme.fromSeed(
      seedColor: c.primary,
      brightness: brightness,
    ).copyWith(
      primary: c.primary,
      onPrimary: c.onPrimary,
      primaryContainer: c.primaryTint,
      surface: c.surface,
      onSurface: c.text,
      onSurfaceVariant: c.textSecondary,
      outlineVariant: c.border,
      error: c.error,
    );

    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(Tokens.radiusMd),
    );
    const label = TextStyle(fontWeight: FontWeight.w600, fontSize: 16);

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: c.bg,
      extensions: [c],
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(52),
          backgroundColor: c.primary,
          foregroundColor: c.onPrimary,
          textStyle: label,
          shape: shape,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(52),
          foregroundColor: c.text,
          backgroundColor: c.surface,
          side: BorderSide(color: c.border),
          textStyle: label,
          shape: shape,
        ),
      ),
      cardTheme: CardThemeData(
        color: c.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Tokens.radiusXl),
          side: BorderSide(color: c.border),
        ),
      ),
    );
  }
}
