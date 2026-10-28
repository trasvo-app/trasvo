// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0.
// If a copy of the MPL was not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../../core/di/app_scope.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/ui/format.dart';
import '../../../core/ui/surface_card.dart';
import '../../../data/discovery/nearby_service.dart';
import '../../../domain/protocol/message.dart';
import '../../../domain/protocol/pairing_uri.dart';
import '../application/connection_controller.dart';

enum ConnectTab { nearby, qr, ip }

/// Conectar con la PC: buscándola en el Wi-Fi, escaneando su QR o escribiendo IP y
/// código. Se cierra sola (devolviendo `true`) en cuanto hay enlace, venga de este
/// lado o de la PC.
class ConnectPage extends StatefulWidget {
  const ConnectPage({super.key, this.initialTab = ConnectTab.nearby});

  final ConnectTab initialTab;

  @override
  State<ConnectPage> createState() => _ConnectPageState();
}

class _ConnectPageState extends State<ConnectPage> {
  late final ConnectionController _connection;
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    _connection = AppScope.read(context).connection;
    _connection.addListener(_closeWhenLinked);
    // Después del primer frame: la búsqueda avisa cambios y no puede hacerlo en pleno build.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_connection.startNearby());
    });
  }

  @override
  void dispose() {
    _connection.removeListener(_closeWhenLinked);
    unawaited(_connection.stopNearby());
    super.dispose();
  }

  void _closeWhenLinked() {
    if (_connection.peer == null || _closing || !mounted) return;
    _closing = true;
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      initialIndex: widget.initialTab.index,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Conectar con la PC'),
          bottom: const TabBar(
            tabs: [
              Tab(icon: Icon(Icons.wifi_find_rounded), text: 'Cerca'),
              Tab(icon: Icon(Icons.qr_code_scanner_rounded), text: 'QR'),
              Tab(icon: Icon(Icons.keyboard_alt_outlined), text: 'IP'),
            ],
          ),
        ),
        body: TabBarView(
          // El escáner usa gestos propios: deslizar entre pestañas lo estorba.
          physics: const NeverScrollableScrollPhysics(),
          children: [
            _NearbyTab(connection: _connection),
            _QrTab(connection: _connection),
            _IpTab(connection: _connection),
          ],
        ),
      ),
    );
  }
}

class _NearbyTab extends StatefulWidget {
  const _NearbyTab({required this.connection});

  final ConnectionController connection;

  @override
  State<_NearbyTab> createState() => _NearbyTabState();
}

class _NearbyTabState extends State<_NearbyTab> {
  String? _waitingFor;

  Future<void> _connect(NearbyDevice device) async {
    setState(() => _waitingFor = device.id);
    await widget.connection.connectNearby(device);
    if (mounted) setState(() => _waitingFor = null);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final text = Theme.of(context).textTheme;
    return ListenableBuilder(
      listenable: widget.connection,
      builder: (context, _) {
        final devices = widget.connection.nearby;
        return ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Row(
              children: [
                const SizedBox.square(
                  dimension: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Buscando PCs con la app abierta en tu Wi-Fi…',
                    style: TextStyle(color: c.textSecondary),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            if (widget.connection.error != null && _waitingFor == null)
              _ErrorBox(text: reasonText(widget.connection.error)),
            for (final device in devices)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _DeviceTile(
                  device: device,
                  waiting: _waitingFor == device.id,
                  onTap: _waitingFor == null ? () => _connect(device) : null,
                ),
              ),
            if (devices.isEmpty)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: c.sunken,
                  borderRadius: BorderRadius.circular(Tokens.radiusMd),
                ),
                child: Text(
                  'Abre la app en tu PC y revisa que los dos estén en el mismo Wi-Fi. '
                  'Si no aparece, usa «QR» o «IP».',
                  style: text.bodyMedium?.copyWith(color: c.textSecondary),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _DeviceTile extends StatelessWidget {
  const _DeviceTile({required this.device, required this.waiting, required this.onTap});

  final NearbyDevice device;
  final bool waiting;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Material(
      color: c.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Tokens.radiusLg),
        side: BorderSide(color: waiting ? c.primary : c.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        onTap: onTap,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        leading: const TintedIcon(Icons.computer_rounded),
        title: Text(
          device.name,
          style: TextStyle(color: c.text, fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          waiting ? 'Acepta la conexión en la PC…' : device.host,
          style: TextStyle(color: waiting ? c.primary : c.textSecondary),
        ),
        trailing: waiting
            ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2))
            : Icon(Icons.chevron_right_rounded, color: c.textSecondary),
      ),
    );
  }
}

class _QrTab extends StatefulWidget {
  const _QrTab({required this.connection});

  final ConnectionController connection;

  @override
  State<_QrTab> createState() => _QrTabState();
}

class _QrTabState extends State<_QrTab> {
  bool _handling = false;

  Future<void> _onDetect(BarcodeCapture capture) async {
    final raw = capture.barcodes.map((b) => b.rawValue).whereType<String>().firstOrNull;
    if (raw == null || _handling) return;
    setState(() => _handling = true);
    HapticFeedback.selectionClick();
    // Al conectar, la página se cierra sola.
    final ok = await widget.connection.connectQr(raw);
    if (!ok && mounted) setState(() => _handling = false);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return ListenableBuilder(
      listenable: widget.connection,
      builder: (context, _) => Column(
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(Tokens.radiusXl),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    MobileScanner(
                      onDetect: _onDetect,
                      errorBuilder: (context, error) => _ScannerError(error: error),
                    ),
                    if (_handling)
                      const ColoredBox(
                        color: Color(0x88000000),
                        child: Center(child: CircularProgressIndicator()),
                      ),
                  ],
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
            child: Column(
              children: [
                if (widget.connection.error != null && !_handling)
                  _ErrorBox(text: reasonText(widget.connection.error)),
                Text(
                  'En la PC abre «Conectar» → «QR» y apunta la cámara al código.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: c.textSecondary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ScannerError extends StatelessWidget {
  const _ScannerError({required this.error});

  final MobileScannerException error;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final denied = error.errorCode == MobileScannerErrorCode.permissionDenied;
    return ColoredBox(
      color: c.sunken,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.no_photography_outlined, size: 40, color: c.textSecondary),
              const SizedBox(height: 12),
              Text(
                denied
                    ? 'Sin permiso de cámara no podemos leer el QR. Puedes darlo en Ajustes, o usar «Escribir IP».'
                    : 'No se pudo abrir la cámara. Usa «Escribir IP».',
                textAlign: TextAlign.center,
                style: TextStyle(color: c.text),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _IpTab extends StatefulWidget {
  const _IpTab({required this.connection});

  final ConnectionController connection;

  @override
  State<_IpTab> createState() => _IpTabState();
}

class _IpTabState extends State<_IpTab> {
  final _ip = TextEditingController();
  final _port = TextEditingController(text: '$defaultPort');
  final _code = TextEditingController();
  bool _touched = false;

  @override
  void dispose() {
    _ip.dispose();
    _port.dispose();
    _code.dispose();
    super.dispose();
  }

  String? get _fieldError {
    if (!isValidIpv4(_ip.text)) return reasonText('invalid_ip');
    if (!isValidPort(_port.text)) return 'El puerto debe ser un número entre 1 y 65535.';
    if (!isValidCode(_code.text)) return 'El código debe tener 6 números.';
    return null;
  }

  Future<void> _submit() async {
    setState(() => _touched = true);
    if (_fieldError != null) return;
    FocusScope.of(context).unfocus();
    // Al conectar, la página se cierra sola.
    await widget.connection.connect(_ip.text.trim(), int.parse(_port.text), _code.text);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return ListenableBuilder(
      listenable: widget.connection,
      builder: (context, _) => ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text(
            'En la PC abre «Conectar» → «IP»: ahí ves su IP y su código.',
            style: TextStyle(color: c.textSecondary),
          ),
          const SizedBox(height: 20),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextField(
                  key: const Key('ip'),
                  controller: _ip,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'IP de la PC',
                    hintText: '192.168.1.20',
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 110,
                child: TextField(
                  key: const Key('port'),
                  controller: _port,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(labelText: 'Puerto'),
                  onChanged: (_) => setState(() {}),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          TextField(
            key: const Key('code'),
            controller: _code,
            keyboardType: TextInputType.number,
            maxLength: 6,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            style: const TextStyle(fontSize: 22, letterSpacing: 6, fontWeight: FontWeight.w600),
            decoration: const InputDecoration(labelText: 'Código de la PC', hintText: '000000'),
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) => _submit(),
          ),
          if (_touched && _fieldError != null) _ErrorBox(text: _fieldError!),
          if (widget.connection.error != null && _fieldError == null)
            _ErrorBox(text: reasonText(widget.connection.error)),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: widget.connection.busy ? null : _submit,
            child: Text(widget.connection.busy ? 'Conectando…' : 'Conectar'),
          ),
        ],
      ),
    );
  }
}

class _ErrorBox extends StatelessWidget {
  const _ErrorBox({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: c.errorTint,
        borderRadius: BorderRadius.circular(Tokens.radiusMd),
      ),
      child: Text(text, style: TextStyle(color: c.error)),
    );
  }
}
