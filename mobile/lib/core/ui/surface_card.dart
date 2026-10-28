// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0.
// If a copy of the MPL was not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/tokens.dart';

/// Tarjeta base: superficie, borde suave y radio XL (contenido interior con radio 12
/// + padding 16 = 28).
class SurfaceCard extends StatelessWidget {
  const SurfaceCard({super.key, required this.child, this.padding = const EdgeInsets.all(16)});

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(Tokens.radiusXl),
        border: Border.all(color: c.border),
      ),
      child: child,
    );
  }
}

/// Ícono dentro de un cuadrado con tinte (encabezados de tarjeta, estados).
class TintedIcon extends StatelessWidget {
  const TintedIcon(this.icon, {super.key, this.color, this.background, this.size = 44});

  final IconData icon;
  final Color? color;
  final Color? background;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: background ?? c.primaryTint,
        borderRadius: BorderRadius.circular(Tokens.radiusMd),
      ),
      child: Icon(icon, color: color ?? c.primary, size: size * 0.5),
    );
  }
}
