// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0.
// If a copy of the MPL was not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../data/discovery/nearby_service.dart';
import '../../../data/transfer/transfer_engine.dart';
import '../../../domain/protocol/pairing_uri.dart';

/// Enlace con la PC: se conecta una vez (QR, IP o «Cerca») desde cualquiera de los
/// dos lados y queda conectado para enviar en ambos sentidos hasta «Desconectar».
class ConnectionController extends ChangeNotifier {
  ConnectionController(this._engine, {required this._nearby}) {
    _subs = [
      _engine.linkChanges.listen((state) {
        _state = state;
        notifyListeners();
      }),
      _engine.linkPrompts.listen((event) {
        switch (event) {
          case LinkRequested():
            _request = event;
          case LinkRequestEnded(:final requestId):
            if (_request?.requestId == requestId) _request = null;
        }
        notifyListeners();
      }),
    ];
  }

  final TransferEngine _engine;
  final NearbyService _nearby;
  late final List<StreamSubscription<Object>> _subs;
  LinkState _state = LinkState.disconnected;
  LinkRequested? _request;
  List<NearbyDevice> _devices = const [];
  bool _busy = false;
  String? _error;

  /// La PC enlazada (`null` si no hay enlace).
  Peer? get peer => _state.peer;
  LinkStatus get status => _state.status;
  bool get reconnecting => _state.status == LinkStatus.reconnecting;
  bool get busy => _busy;

  /// Código de error de la última conexión fallida (ver `reasonText`).
  String? get error => _error;

  /// Una PC cercana pide conectarse y espera que el usuario responda.
  LinkRequested? get request => _request;

  /// PCs con la app en el mismo Wi-Fi (mientras se busca).
  List<NearbyDevice> get nearby => _devices;

  Future<bool> connect(String host, int port, String code) =>
      _attempt(() => _engine.link(host, port, code));

  /// Conecta con lo que dice un QR. `false` (con `error = invalid_qr`) si no es nuestro.
  Future<bool> connectQr(String raw) async {
    final info = PairingInfo.tryParse(raw);
    if (info == null) {
      _error = 'invalid_qr';
      notifyListeners();
      return false;
    }
    return connect(info.host, info.port, info.code);
  }

  /// Conecta con un dispositivo encontrado: el otro lado tiene que aceptar.
  Future<bool> connectNearby(NearbyDevice device) =>
      _attempt(() => _engine.linkNearby(device.host, device.port));

  Future<bool> _attempt(Future<String> Function() link) async {
    _busy = true;
    _error = null;
    notifyListeners();
    try {
      await link();
      return true;
    } on TransferException catch (e) {
      _error = e.code;
      return false;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  /// Desconecta en los dos lados.
  void disconnect() => _engine.unlink();

  void answerRequest(bool accept) {
    final request = _request;
    if (request == null) return;
    _request = null;
    _engine.respond(request.requestId, accept);
    notifyListeners();
  }

  /// Busca PCs en el Wi-Fi mientras la pantalla de conectar está abierta.
  Future<void> startNearby() async {
    try {
      await _nearby.startBrowsing((devices) {
        _devices = devices;
        notifyListeners();
      });
    } catch (_) {
      // Sin Wi-Fi o sin soporte: quedan QR e IP.
    }
  }

  Future<void> stopNearby() async {
    _devices = const [];
    try {
      await _nearby.stopBrowsing();
    } catch (_) {}
  }

  @override
  void dispose() {
    for (final sub in _subs) {
      unawaited(sub.cancel());
    }
    unawaited(stopNearby());
    super.dispose();
  }
}
