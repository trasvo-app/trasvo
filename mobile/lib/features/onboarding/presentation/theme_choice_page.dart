// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0.
// If a copy of the MPL was not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_controller.dart';
import '../../../core/theme/tokens.dart';

/// Primer inicio: el usuario elige claro u oscuro. Al tocar una opción se ve en vivo.
class ThemeChoicePage extends StatelessWidget {
  const ThemeChoicePage({super.key, required this.controller});

  final ThemeController controller;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final text = Theme.of(context).textTheme;
    final selected = Theme.of(context).brightness == Brightness.dark
        ? ThemeMode.dark
        : ThemeMode.light;

    return Scaffold(
      body: SafeArea(
        // Desplazable y con ancho máximo: en horizontal no entra en la altura de la pantalla.
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: 560,
                  minHeight: (constraints.maxHeight - 48).clamp(0, double.infinity),
                ),
                child: IntrinsicHeight(child: _content(context, c, text, selected)),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _content(BuildContext context, AppColors c, TextTheme text, ThemeMode selected) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const SizedBox(height: 24),
      Image.asset('assets/trasvo-icon.png', width: 48, height: 48),
      const SizedBox(height: 24),
      Text(
        '¡Bienvenido!',
        style: text.headlineMedium?.copyWith(fontWeight: FontWeight.w700, color: c.text),
      ),
      const SizedBox(height: 8),
      Text(
        '¿Cómo prefieres ver la app? Puedes cambiarlo cuando quieras.',
        style: text.bodyLarge?.copyWith(color: c.textSecondary),
      ),
      const SizedBox(height: 32),
      Row(
        children: [
          Expanded(
            child: _ThemeOption(
              label: 'Claro',
              palette: AppColors.light,
              selected: selected == ThemeMode.light,
              onTap: () => controller.preview(ThemeMode.light),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _ThemeOption(
              label: 'Oscuro',
              palette: AppColors.dark,
              selected: selected == ThemeMode.dark,
              onTap: () => controller.preview(ThemeMode.dark),
            ),
          ),
        ],
      ),
      const Spacer(),
      const SizedBox(height: 24),
      FilledButton(onPressed: () => controller.choose(selected), child: const Text('Continuar')),
    ],
  );
}

class _ThemeOption extends StatelessWidget {
  const _ThemeOption({
    required this.label,
    required this.palette,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final AppColors palette;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      button: true,
      selected: selected,
      label: 'Tema $label',
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: Tokens.fastDuration,
          // Preview con radio 8 + padding 8 = radio 16.
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: BorderRadius.circular(Tokens.radiusLg),
            border: Border.all(color: selected ? c.primary : c.border, width: 2),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _MiniPhone(palette: palette),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Row(
                  children: [
                    Text(
                      label,
                      style: TextStyle(fontWeight: FontWeight.w600, color: c.text),
                    ),
                    const Spacer(),
                    AnimatedOpacity(
                      opacity: selected ? 1 : 0,
                      duration: Tokens.enterDuration,
                      child: Icon(Icons.check_circle_rounded, color: c.primary, size: 20),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Mini pantalla con los colores fijos de cada tema.
class _MiniPhone extends StatelessWidget {
  const _MiniPhone({required this.palette});

  final AppColors palette;

  @override
  Widget build(BuildContext context) {
    Widget bar(double width, Color color, {double height = 8}) => Container(
      width: width,
      height: height,
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(4)),
    );

    return Container(
      height: 150,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: palette.bg,
        borderRadius: BorderRadius.circular(Tokens.radiusSm),
        border: Border.all(color: palette.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          bar(18, palette.primary, height: 18),
          const Spacer(),
          bar(70, palette.text),
          const SizedBox(height: 6),
          bar(50, palette.textTertiary, height: 6),
          const Spacer(),
          bar(double.infinity, palette.primary, height: 18),
          const SizedBox(height: 6),
          Container(
            height: 18,
            decoration: BoxDecoration(
              color: palette.surface,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: palette.border),
            ),
          ),
        ],
      ),
    );
  }
}
