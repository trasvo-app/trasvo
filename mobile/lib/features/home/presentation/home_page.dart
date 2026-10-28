// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0.
// If a copy of the MPL was not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';

import '../../../core/di/app_scope.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/ui/surface_card.dart';
import '../../connect/presentation/connect_page.dart';
import '../../send/presentation/send_page.dart';
import '../../transfers/presentation/transfer_tile.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    return Scaffold(
      body: SafeArea(
        child: ListenableBuilder(
          listenable: Listenable.merge([services.connection, services.transfers]),
          builder: (context, _) {
            final activity = services.transfers.items.take(20).toList();
            return ListView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
              children: [
                const _Header(),
                const SizedBox(height: 20),
                const _ConnectionCard(),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: () =>
                      Navigator.of(context)
                          .push(MaterialPageRoute<void>(builder: (_) => const SendPage())),
                  icon: const Icon(Icons.upload_rounded),
                  label: const Text('Enviar fotos y archivos'),
                ),
                // Ya enlazados, la PC envía sin escribir nada.
                if (services.connection.peer == null) ...[
                  const SizedBox(height: 20),
                  const _ReceiveCard(),
                ],
                const SizedBox(height: 28),
                Text(
                  'Actividad',
                  style: Theme.of(context).textTheme.titleMedium
                      ?.copyWith(color: context.colors.text, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 12),
                if (activity.isEmpty)
                  Text(
                    'Lo que envíes o recibas aparecerá aquí.',
                    style: TextStyle(color: context.colors.textSecondary),
                  )
                else
                  for (final item in activity)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: TransferTile(
                        item: item,
                        onCancel: () => services.transfers.cancel(item.id),
                      ),
                    ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final theme = AppScope.of(context).theme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Row(
      children: [
        Image.asset('assets/trasvo-icon.png', width: 40, height: 40),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            'Trasvo',
            style: Theme.of(context).textTheme.titleLarge
                ?.copyWith(color: c.text, fontWeight: FontWeight.w700),
          ),
        ),
        IconButton(
          tooltip: isDark ? 'Usar tema claro' : 'Usar tema oscuro',
          onPressed: () => theme.choose(isDark ? ThemeMode.light : ThemeMode.dark),
          icon: Icon(isDark ? Icons.light_mode_outlined : Icons.dark_mode_outlined, color: c.text),
        ),
      ],
    );
  }
}

class _ConnectionCard extends StatelessWidget {
  const _ConnectionCard();

  Future<void> _open(BuildContext context, ConnectTab tab) =>
      Navigator.of(context)
          .push<bool>(MaterialPageRoute(builder: (_) => ConnectPage(initialTab: tab)));

  // Escucha por su cuenta: como widget `const`, no se reconstruye con el padre.
  @override
  Widget build(BuildContext context) {
    final connection = AppScope.of(context).connection;
    return ListenableBuilder(listenable: connection, builder: (context, _) => _build(context));
  }

  Widget _build(BuildContext context) {
    final c = context.colors;
    final text = Theme.of(context).textTheme;
    final connection = AppScope.of(context).connection;
    final peer = connection.peer;

    if (peer != null) {
      final reconnecting = connection.reconnecting;
      return SurfaceCard(
        child: Row(
          children: [
            reconnecting
                ? TintedIcon(Icons.sync_rounded, color: c.warning, background: c.warningTint)
                : TintedIcon(Icons.computer_rounded, color: c.success, background: c.successTint),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Conectado con ${peer.name}',
                    style: text.titleSmall?.copyWith(color: c.text, fontWeight: FontWeight.w600),
                  ),
                  Text(
                    reconnecting ? 'Reconectando…' : 'Pueden enviarse archivos en ambos sentidos',
                    style: TextStyle(color: reconnecting ? c.warning : c.textSecondary),
                  ),
                ],
              ),
            ),
            TextButton(onPressed: connection.disconnect, child: const Text('Desconectar')),
          ],
        ),
      );
    }

    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const TintedIcon(Icons.computer_rounded),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Conecta con tu PC',
                      style: text.titleSmall?.copyWith(color: c.text, fontWeight: FontWeight.w600),
                    ),
                    Text(
                      'Ambos deben estar en el mismo Wi-Fi.',
                      style: TextStyle(color: c.textSecondary),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton.tonalIcon(
              onPressed: () => _open(context, ConnectTab.nearby),
              icon: const Icon(Icons.wifi_find_rounded),
              label: const Text('Buscar mi PC'),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _open(context, ConnectTab.qr),
                  icon: const Icon(Icons.qr_code_scanner_rounded),
                  label: const Text('Escanear QR'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _open(context, ConnectTab.ip),
                  icon: const Icon(Icons.keyboard_alt_outlined),
                  label: const Text('Escribir IP'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Lo que hay que escribir en la PC para que envíe a este celular.
class _ReceiveCard extends StatelessWidget {
  const _ReceiveCard();

  // Escucha por su cuenta: el puerto llega cuando arranca el servidor.
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: AppScope.of(context).transfers,
    builder: (context, _) => _build(context),
  );

  Widget _build(BuildContext context) {
    final c = context.colors;
    final text = Theme.of(context).textTheme;
    final services = AppScope.of(context);
    final port = services.transfers.port;
    final ip = services.localIp;
    final ready = ip != null && port != null;

    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const TintedIcon(Icons.download_rounded),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'O conéctate desde la PC',
                      style: text.titleSmall?.copyWith(color: c.text, fontWeight: FontWeight.w600),
                    ),
                    Text(services.deviceName, style: TextStyle(color: c.textSecondary)),
                  ],
                ),
              ),
              _Status(ready: ready),
            ],
          ),
          const SizedBox(height: 16),
          if (ip == null)
            Text('Conecta el celular a un Wi-Fi para recibir.', style: TextStyle(color: c.error))
          else
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: c.sunken,
                borderRadius: BorderRadius.circular(Tokens.radiusMd),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: _Datum(label: 'IP', value: '$ip:${port ?? '…'}'),
                  ),
                  _Datum(label: 'Código', value: services.transfers.code, highlight: true),
                ],
              ),
            ),
          const SizedBox(height: 8),
          Text(
            'En la PC: «Conectar» → «Cerca» y toca este celular, o «IP» con estos datos.',
            style: text.bodySmall?.copyWith(color: c.textSecondary),
          ),
        ],
      ),
    );
  }
}

class _Status extends StatelessWidget {
  const _Status({required this.ready});

  final bool ready;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: c.sunken, borderRadius: BorderRadius.circular(999)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(shape: BoxShape.circle, color: ready ? c.success : c.warning),
          ),
          const SizedBox(width: 6),
          Text(
            ready ? 'Listo' : 'Preparando',
            style: TextStyle(color: c.text, fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

class _Datum extends StatelessWidget {
  const _Datum({required this.label, required this.value, this.highlight = false});

  final String label;
  final String value;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: TextStyle(
            color: c.textSecondary,
            fontSize: 11,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 2),
        Container(
          padding: highlight
              ? const EdgeInsets.symmetric(horizontal: 8, vertical: 2)
              : EdgeInsets.zero,
          decoration: highlight
              ? BoxDecoration(
                  color: c.primaryTint,
                  borderRadius: BorderRadius.circular(Tokens.radiusSm),
                )
              : null,
          child: Text(
            value,
            style: TextStyle(
              color: highlight ? c.primary : c.text,
              fontSize: highlight ? 20 : 16,
              fontWeight: FontWeight.w700,
              letterSpacing: highlight ? 2 : 0,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
      ],
    );
  }
}
