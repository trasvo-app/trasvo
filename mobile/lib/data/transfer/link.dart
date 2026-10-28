// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0.
// If a copy of the MPL was not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

part of 'transfer_engine.dart';

// Enlace persistente: una vez emparejados (desde cualquiera de los dos lados), quedan
// conectados y se envían archivos en ambos sentidos sin volver a emparejar, hasta que
// alguno toca «Desconectar». Mismas reglas que `link.rs` en Rust (ver docs/protocol.md).

/// Cada cuánto se manda `ping` por el enlace.
const pingInterval = Duration(seconds: 10);

/// Sin noticias del otro lado durante este tiempo, el enlace se da por cortado.
const linkTimeout = Duration(seconds: 40);

/// Tras un corte, cuánto tiempo se intenta (o se espera) reconectar.
const resumeWindow = Duration(minutes: 10);
const _reconnectEvery = Duration(seconds: 3);

/// Longitud del token de sesión en hexadecimal (128 bits).
const _tokenLength = 32;

String _newLinkToken() {
  final random = Random.secure();
  return List.generate(
    _tokenLength ~/ 2,
    (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
}

class _Link {
  _Link({
    required this.token,
    required this.peerName,
    required this.host,
    required this.port,
    required this.initiator,
  });

  final String token;
  final String peerName;

  /// Dónde escucha el otro lado: ahí se conectan los envíos.
  final String host;
  final int port;

  /// Quien abrió el enlace es quien reconecta si se corta.
  final bool initiator;
  LinkStatus status = LinkStatus.connected;
  _Conn? _conn;
  Timer? _ping;

  /// Lo cerramos nosotros: quien lo cerró ya actualizó el estado.
  bool stopped = false;

  Peer get peer => Peer(name: peerName, host: host, port: port);

  void stop() {
    stopped = true;
    _ping?.cancel();
    final conn = _conn;
    if (conn != null) unawaited(conn.trySend(const LinkClose()).whenComplete(conn.close));
  }
}

enum _End { closed, lost }

extension _Links on TransferEngine {
  Future<String> _openLink(String host, int port, String pairToken) async {
    try {
      final token = _newLinkToken();
      final (conn, peerName) = await _linkHandshake(host, port, pairToken, token);
      _install(
        _Link(token: token, peerName: peerName, host: host, port: port, initiator: true),
        conn,
      );
      return peerName;
    } catch (e) {
      throw _asTransfer(e);
    }
  }

  Future<(_Conn, String)> _linkHandshake(
    String host,
    int port,
    String pairToken,
    String linkToken,
  ) async {
    // Pedir permiso espera a que el usuario del otro lado responda.
    final wait = pairToken.isEmpty
        ? TransferEngine.promptTimeout + const Duration(seconds: 10)
        : TransferEngine._handshakeTimeout;
    final (conn, peerName) = await _connect(host, port, pairToken, wait: wait);
    try {
      await conn.send(LinkOpen(token: linkToken, port: _port));
      final reply = await conn.readMessage().timeout(TransferEngine._handshakeTimeout);
      if (reply is! LinkAccept) throw TransferException.unexpected;
      return (conn, peerName);
    } catch (_) {
      conn.close();
      rethrow;
    }
  }

  bool _isSessionToken(String token) {
    final link = _link;
    return link != null && _sameCode(link.token, token);
  }

  /// Reemplaza el enlace actual (avisando al anterior) y empieza a vigilarlo.
  /// Con `expectEpoch`, no hace nada si el enlace cambió mientras tanto.
  void _install(_Link link, _Conn conn, {int? expectEpoch}) {
    if (expectEpoch != null && expectEpoch != _epoch) {
      conn.close();
      return;
    }
    _link?.stop();
    _epoch++;
    _link = link..status = LinkStatus.connected;
    link._conn = conn;
    _emitLink();
    unawaited(_watchLink(link, conn, _epoch));
  }

  Future<void> _watchLink(_Link link, _Conn conn, int epoch) async {
    link._ping = Timer.periodic(pingInterval, (_) => unawaited(conn.trySend(const Ping())));
    var end = _End.lost;
    try {
      while (true) {
        final message = _control(await conn.reader.next().timeout(linkTimeout));
        if (message is Ping) continue;
        if (message is LinkClose) end = _End.closed;
        break;
      }
    } catch (_) {
      // Conexión cortada, sin respuesta o mensaje inesperado.
    }
    link._ping?.cancel();
    conn.close();
    if (link.stopped) return;
    if (end == _End.closed) {
      _clearLink(epoch);
    } else {
      _lostLink(epoch);
    }
  }

  void _lostLink(int epoch) {
    final link = _link;
    if (epoch != _epoch || link == null) return;
    link.status = LinkStatus.reconnecting;
    _emitLink();
    if (link.initiator) {
      unawaited(_reconnect(epoch, link));
    } else {
      // El otro lado es quien reconecta; si no vuelve a tiempo, se cierra.
      _resumeTimer?.cancel();
      _resumeTimer = Timer(resumeWindow, () => _clearLink(epoch));
    }
  }

  Future<void> _reconnect(int epoch, _Link old) async {
    final deadline = DateTime.now().add(resumeWindow);
    while (DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(_reconnectEvery);
      if (epoch != _epoch || _closed) return;
      try {
        final (conn, peerName) = await _linkHandshake(old.host, old.port, old.token, old.token);
        final link = _Link(
          token: old.token,
          peerName: peerName,
          host: old.host,
          port: old.port,
          initiator: true,
        );
        _install(link, conn, expectEpoch: epoch);
        return;
      } on TransferException catch (e) {
        // El otro lado ya no reconoce el enlace (lo cerró o se reinició).
        if (e.code == 'invalid_code' || e.code == 'declined') break;
      } catch (_) {
        // Todavía sin red: se reintenta.
      }
    }
    _clearLink(epoch);
  }

  void _clearLink(int epoch) {
    if (epoch != _epoch || _link == null) return;
    _link = null;
    _epoch++;
    _emitLink();
  }

  /// Pregunta a nuestro usuario si acepta la conexión. Una pregunta a la vez.
  Future<bool> _askUser(String peerName) async {
    if (_prompting) return false;
    _prompting = true;
    final id = newTransferId();
    final decision = Completer<bool>();
    _pending[id] = decision;
    _emitPrompt(LinkRequested(id, peerName: peerName));
    try {
      return await decision.future.timeout(TransferEngine.promptTimeout, onTimeout: () => false);
    } finally {
      _pending.remove(id);
      _prompting = false;
      _emitPrompt(LinkRequestEnded(id));
    }
  }
}
