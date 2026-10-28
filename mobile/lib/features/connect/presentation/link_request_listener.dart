// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0.
// If a copy of the MPL was not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/ui/surface_card.dart';
import '../application/connection_controller.dart';

/// Muestra «X quiere conectarse» en cualquier pantalla cuando una PC cercana pide
/// conectarse sin código. Se cierra solo si la petición vence.
class LinkRequestListener extends StatefulWidget {
  const LinkRequestListener({
    super.key,
    required this.connection,
    required this.navigatorKey,
    required this.child,
  });

  final ConnectionController connection;
  final GlobalKey<NavigatorState> navigatorKey;
  final Widget child;

  @override
  State<LinkRequestListener> createState() => _LinkRequestListenerState();
}

class _LinkRequestListenerState extends State<LinkRequestListener> {
  String? _showing;

  @override
  void initState() {
    super.initState();
    widget.connection.addListener(_check);
  }

  @override
  void dispose() {
    widget.connection.removeListener(_check);
    super.dispose();
  }

  void _check() {
    final request = widget.connection.request;
    final navigator = widget.navigatorKey.currentState;
    if (navigator == null) return;
    // Venció o se respondió desde otro lado: cerrar el diálogo.
    if (_showing != null && request?.requestId != _showing) {
      _showing = null;
      navigator.pop();
    }
    if (request == null || _showing != null) return;
    _showing = request.requestId;
    showDialog<void>(
      context: navigator.context,
      barrierDismissible: false,
      builder: (_) => LinkRequestDialog(
        peerName: request.peerName,
        onAnswer: (accept) {
          _showing = null;
          Navigator.of(navigator.context).pop();
          widget.connection.answerRequest(accept);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class LinkRequestDialog extends StatelessWidget {
  const LinkRequestDialog({super.key, required this.peerName, required this.onAnswer});

  final String peerName;
  final void Function(bool accept) onAnswer;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final text = Theme.of(context).textTheme;
    return Dialog(
      backgroundColor: c.surface,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const TintedIcon(Icons.computer_rounded, size: 52),
            const SizedBox(height: 16),
            Text(
              '$peerName quiere conectarse',
              style: text.titleLarge?.copyWith(color: c.text, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              'Si aceptas, podrán enviarse archivos en ambos sentidos hasta que toques '
              '«Desconectar». Acepta solo si es tu PC.',
              style: text.bodyMedium?.copyWith(color: c.textSecondary),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => onAnswer(false),
                    child: const Text('Rechazar'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    autofocus: true,
                    onPressed: () => onAnswer(true),
                    child: const Text('Aceptar'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
