// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0.
// If a copy of the MPL was not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

/// Radios y tiempos de `design/tokens.json`. Los colores están en `app_colors.dart`.
library;

abstract final class Tokens {
  static const radiusSm = 8.0;
  static const radiusMd = 12.0;
  static const radiusLg = 16.0;
  static const radiusXl = 28.0;

  static const pressScale = 0.96;
  static const pressDuration = Duration(milliseconds: 150);
  static const fastDuration = Duration(milliseconds: 150);
  static const enterDuration = Duration(milliseconds: 300);
  static const exitDuration = Duration(milliseconds: 150);
  static const staggerDelay = Duration(milliseconds: 100);
}
