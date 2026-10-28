// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0.
// If a copy of the MPL was not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';

/// Paleta de `design/tokens.json` (claro y oscuro). Mantener sincronizada.
///
/// Se lee con `context.colors` desde cualquier widget.
@immutable
class AppColors extends ThemeExtension<AppColors> {
  const AppColors({
    required this.bg,
    required this.surface,
    required this.sunken,
    required this.border,
    required this.text,
    required this.textSecondary,
    required this.textTertiary,
    required this.primary,
    required this.primaryTint,
    required this.onPrimary,
    required this.warning,
    required this.warningTint,
    required this.error,
    required this.errorTint,
    required this.success,
    required this.successTint,
    required this.info,
    required this.infoTint,
  });

  static const light = AppColors(
    bg: Color(0xFFF5F5F7),
    surface: Color(0xFFFFFFFF),
    sunken: Color(0xFFEFEFF1),
    border: Color(0xFFE3E3E6),
    text: Color(0xFF111113),
    textSecondary: Color(0xFF6E6E73),
    textTertiary: Color(0xFFA1A1A6),
    primary: Color(0xFF1F6FEB),
    primaryTint: Color(0xFFE8F0FD),
    onPrimary: Color(0xFFFFFFFF),
    warning: Color(0xFFF5B400),
    warningTint: Color(0xFFFFF4D6),
    error: Color(0xFFE5484D),
    errorTint: Color(0xFFFDECEC),
    success: Color(0xFF30A46C),
    successTint: Color(0xFFE6F6EE),
    info: Color(0xFF5B7C99),
    infoTint: Color(0xFFE9EFF4),
  );

  static const dark = AppColors(
    bg: Color(0xFF0B0B0C),
    surface: Color(0xFF161618),
    sunken: Color(0xFF1F1F22),
    border: Color(0xFF2C2C30),
    text: Color(0xFFF2F2F3),
    textSecondary: Color(0xFFA0A0A6),
    textTertiary: Color(0xFF6B6B70),
    primary: Color(0xFF3B82F6),
    primaryTint: Color(0xFF13233F),
    onPrimary: Color(0xFFFFFFFF),
    warning: Color(0xFFFFCA28),
    warningTint: Color(0xFF3A2F0B),
    error: Color(0xFFF2555A),
    errorTint: Color(0xFF3B1517),
    success: Color(0xFF3DD68C),
    successTint: Color(0xFF0F2E1F),
    info: Color(0xFF7C9CB8),
    infoTint: Color(0xFF1A2530),
  );

  final Color bg;
  final Color surface;
  final Color sunken;
  final Color border;
  final Color text;
  final Color textSecondary;
  final Color textTertiary;
  final Color primary;
  final Color primaryTint;
  final Color onPrimary;
  final Color warning;
  final Color warningTint;
  final Color error;
  final Color errorTint;
  final Color success;
  final Color successTint;
  final Color info;
  final Color infoTint;

  @override
  AppColors copyWith() => this;

  // El cambio de tema no se anima (ver better-ui): se usa el destino directo.
  @override
  AppColors lerp(ThemeExtension<AppColors>? other, double t) =>
      other is AppColors && t >= 0.5 ? other : this;
}

extension AppColorsContext on BuildContext {
  AppColors get colors => Theme.of(this).extension<AppColors>()!;
}
