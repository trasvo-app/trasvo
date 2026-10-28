// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0.
// If a copy of the MPL was not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import '../../domain/protocol/codec.dart';
import '../../domain/protocol/message.dart';
import 'file_names.dart';
import 'frame_reader.dart';
import 'transfer_types.dart';

export 'transfer_types.dart';

part 'link.dart';

/// Motor de transferencia del celular: servidor que recibe, cliente que envía, y el
/// enlace persistente con la PC. Mismo protocolo y mismas reglas que `ft_transfer`
/// en Rust (ver docs/protocol.md).
///
/// Solo usa `dart:io`: funciona en la app y en herramientas de terminal (`tool/`).
class TransferEngine {
  TransferEngine(this.config);

  static const offerTimeout = Duration(seconds: 120);

  /// Cuánto tiene el usuario para aceptar una conexión desde un dispositivo cercano.
  static const promptTimeout = Duration(seconds: 60);
  static const _connectTimeout = Duration(seconds: 5);

  /// Saludo y emparejamiento con código o token (sin intervención del usuario).
  static const _handshakeTimeout = Duration(seconds: 15);
  static const _completeWait = Duration(seconds: 30);
  static const _maxFailedPairings = 10;

  final EngineConfig config;
  final _events = StreamController<TransferEvent>.broadcast();
  final _linkChanges = StreamController<LinkState>.broadcast();
  final _prompts = StreamController<LinkPromptEvent>.broadcast();
  final _pending = <String, Completer<bool>>{};
  final _cancels = <String, Completer<void>>{};
  int _failedPairings = 0;
  ServerSocket? _server;
  int _port = 0;
  bool _closed = false;

  // Enlace actual. `_epoch` cambia con cada enlace nuevo o cierre, para que las tareas
  // de un enlace viejo no toquen al nuevo.
  _Link? _link;
  int _epoch = 0;
  Timer? _resumeTimer;
  bool _prompting = false;

  Stream<TransferEvent> get events => _events.stream;

  /// Cambios del enlace (conectado, reconectando, desconectado).
  Stream<LinkState> get linkChanges => _linkChanges.stream;

  /// Peticiones de conexión sin código que esperan al usuario.
  Stream<LinkPromptEvent> get linkPrompts => _prompts.stream;

  LinkState get linkState {
    final link = _link;
    return link == null ? LinkState.disconnected : LinkState(link.status, link.peer);
  }

  /// Empieza a aceptar conexiones. Devuelve el puerto real (útil con puerto 0).
  Future<int> listen({int port = defaultPort, InternetAddress? address}) async {
    final server = await ServerSocket.bind(address ?? InternetAddress.anyIPv4, port);
    _server = server;
    _port = server.port;
    server.listen((socket) => unawaited(_handle(socket)));
    return server.port;
  }

  Future<void> close() async {
    _closed = true;
    _link?.stop();
    _link = null;
    _resumeTimer?.cancel();
    await _server?.close();
    await _events.close();
    await _linkChanges.close();
    await _prompts.close();
  }

  /// Se enlaza con `host:port` usando su código. Desde ahí los dos lados pueden
  /// enviarse archivos con [sendLinked]. Devuelve el nombre del otro dispositivo.
  Future<String> link(String host, int port, String code) => _openLink(host, port, code);

  /// Como [link], sin código: el otro lado le pregunta a su usuario (dispositivo cercano).
  Future<String> linkNearby(String host, int port) => _openLink(host, port, '');

  /// Cierra el enlace en los dos lados.
  void unlink() {
    final link = _link;
    if (link == null) return;
    _link = null;
    _epoch++;
    link.stop();
    _emitLink();
  }

  /// Solo para tests: corta la conexión del enlace como si se cayera el Wi-Fi.
  void debugDropLinkConnection() => _link?._conn?.socket.destroy();

  /// Envía al dispositivo enlazado (aunque esté reconectando).
  Future<void> sendLinked(String transferId, List<OutgoingFile> files) {
    final link = _link;
    if (link == null) {
      _emit(FailedEvent(transferId, direction: Direction.send, reason: 'not_connected'));
      return Future.error(const TransferException('not_connected'));
    }
    return send(transferId, link.host, link.port, link.token, files);
  }

  /// Respuesta del usuario a un [OfferEvent] o a un [LinkRequested].
  /// `false` si ya no espera respuesta.
  bool respond(String transferId, bool accept) {
    final decision = _pending.remove(transferId);
    if (decision == null || decision.isCompleted) return false;
    decision.complete(accept);
    return true;
  }

  /// Cancela una transferencia en curso o rechaza una oferta pendiente.
  bool cancel(String transferId) {
    if (respond(transferId, false)) return true;
    final cancel = _cancels[transferId];
    if (cancel == null || cancel.isCompleted) return false;
    cancel.complete();
    return true;
  }

  /// Comprueba que hay un dispositivo en `host:port` que acepta `code`. Devuelve su nombre.
  Future<String> checkPairing(String host, int port, String code) async {
    try {
      final (conn, peerName) = await _connect(host, port, code);
      conn.close();
      return peerName;
    } catch (e) {
      throw _asTransfer(e);
    }
  }

  /// Envía `files` presentando `token` (su código o el del enlace).
  /// Emite eventos de progreso y, si falla, [FailedEvent].
  Future<void> send(
    String transferId,
    String host,
    int port,
    String token,
    List<OutgoingFile> files,
  ) async {
    try {
      await _send(transferId, host, port, token, files);
    } catch (e) {
      final error = _asTransfer(e);
      _emit(FailedEvent(transferId, direction: Direction.send, reason: error.code));
      throw error;
    }
  }

  // ---------------------------------------------------------------- envío

  Future<void> _send(
    String id,
    String host,
    int port,
    String code,
    List<OutgoingFile> files,
  ) async {
    final cancel = _trackCancel(id);
    try {
      if (files.isEmpty) throw const TransferException('empty');
      final total = files.fold(0, (sum, f) => sum + f.size);
      final (conn, peerName) = await _connect(host, port, code);
      try {
        await conn.send(
          TransferOffer(
            transferId: id,
            files: [for (final f in files) FileInfo(name: f.name, size: f.size)],
          ),
        );
        _emit(WaitingEvent(id, peerName: peerName, fileCount: files.length, totalBytes: total));

        final reply = await _orCancel(
          conn.reader.next().timeout(offerTimeout + const Duration(seconds: 10)),
          cancel,
        );
        switch (_control(reply)) {
          case TransferAccept():
            break;
          case TransferReject(:final reason):
            throw TransferException.fromReason(reason);
          default:
            throw TransferException.unexpected;
        }

        // Desde aquí solo escribimos; escuchamos aparte si el receptor cancela o falla.
        final peer = _PeerWatch(conn.reader.next());
        final progress = _Progress(this, id, Direction.send, total);
        for (var index = 0; index < files.length; index++) {
          final file = files[index];
          progress.startFile(file.name);
          final hash = await _sendFile(conn, file, progress, () {
            if (cancel.isCompleted) throw const TransferException('cancelled');
            peer.check();
          });
          await conn.send(FileEnd(transferId: id, index: index, hash: hash));
        }
        await conn.send(TransferDone(transferId: id));

        switch (_control(await peer.future.timeout(_completeWait))) {
          case TransferComplete():
            break;
          case TransferError(:final reason):
            throw TransferException.fromReason(reason);
          case Cancel():
            throw const TransferException('cancelled');
          default:
            throw TransferException.unexpected;
        }
        _emit(
          CompletedEvent(id, direction: Direction.send, files: [for (final f in files) f.name]),
        );
      } on TransferException catch (e) {
        if (e.code == 'cancelled' && cancel.isCompleted) {
          await conn.trySend(Cancel(transferId: id));
        }
        rethrow;
      } finally {
        conn.close();
      }
    } finally {
      _cancels.remove(id);
    }
  }

  /// Manda exactamente `file.size` bytes en trozos y devuelve su SHA-256 en hex.
  Future<String> _sendFile(
    _Conn conn,
    OutgoingFile file,
    _Progress progress,
    void Function() check,
  ) async {
    final digest = _DigestSink();
    final hasher = sha256.startChunkedConversion(digest);
    var sent = 0;
    await for (final chunk in file.open()) {
      var offset = 0;
      while (offset < chunk.length && sent < file.size) {
        check();
        final end = min(min(offset + maxChunkBytes, chunk.length), offset + file.size - sent);
        final piece = Uint8List.fromList(chunk.sublist(offset, end));
        await conn.sendData(piece);
        hasher.add(piece);
        sent += piece.length;
        offset = end;
        progress.advance(piece.length);
      }
      if (sent >= file.size) break;
    }
    if (sent != file.size) {
      // El archivo cambió desde que lo listamos.
      throw TransferException('io', '${file.name} changed while sending');
    }
    check();
    hasher.close();
    return digest.value.toString();
  }

  // ------------------------------------------------------------- recepción

  Future<void> _handle(Socket socket) async {
    socket.setOption(SocketOption.tcpNoDelay, true);
    final conn = _Conn(socket);
    // Si la conexión pasa a ser el enlace, sigue abierta al salir.
    var linked = false;
    try {
      await conn.send(_hello());
      final hello = await conn.readMessage();
      if (hello is! Hello) throw TransferException.unexpected;
      if (hello.version != protocolVersion) {
        await conn.send(const PairReject(reason: 'version_mismatch'));
        return;
      }
      final request = await conn.readMessage();
      if (request is! PairRequest) throw TransferException.unexpected;
      final auth = await _authorize(conn, request.token, hello.deviceName);
      if (auth == null) return;
      await conn.send(PairAccept(deviceId: config.deviceId));

      var frame = await conn.reader.next();
      if (frame == null) return;
      final first = _control(frame);
      if (first is LinkOpen) {
        // Con el token del enlace solo se puede retomar ese mismo enlace.
        if (first.token.length != _tokenLength) throw TransferException.unexpected;
        if (auth == _Auth.session && !_isSessionToken(first.token)) {
          throw TransferException.unexpected;
        }
        await conn.send(const LinkAccept());
        _install(
          _Link(
            token: first.token,
            peerName: hello.deviceName,
            host: socket.remoteAddress.address,
            port: first.port,
            initiator: false,
          ),
          conn,
        );
        linked = true;
        return;
      }
      if (auth == _Auth.approved) throw TransferException.unexpected;

      // Una conexión emparejada puede traer varias transferencias seguidas.
      while (frame != null) {
        final offer = _control(frame);
        if (offer is! TransferOffer) throw TransferException.unexpected;
        try {
          await _receive(conn, hello.deviceName, offer);
        } catch (e) {
          final error = _asTransfer(e);
          _emit(FailedEvent(offer.transferId, direction: Direction.receive, reason: error.code));
          await conn.trySend(TransferError(transferId: offer.transferId, reason: error.code));
          return;
        }
        frame = await conn.reader.next();
      }
    } catch (_) {
      // Conexión rota o protocolo inválido fuera de una transferencia: nada que avisar.
    } finally {
      if (!linked) conn.close();
    }
  }

  /// Comprueba cómo se presenta el otro lado. `null` si se rechazó (ya avisado).
  Future<_Auth?> _authorize(_Conn conn, String token, String peerName) async {
    if (token.isEmpty) {
      if (await _askUser(peerName)) return _Auth.approved;
      await conn.send(const PairReject(reason: 'declined'));
      return null;
    }
    // Los tokens de enlace (128 bits) no se pueden adivinar: no cuentan para el bloqueo.
    if (token.length == _tokenLength) {
      if (_isSessionToken(token)) return _Auth.session;
      await conn.send(const PairReject(reason: 'invalid_code'));
      return null;
    }
    if (_failedPairings >= _maxFailedPairings) {
      await conn.send(const PairReject(reason: 'locked'));
      return null;
    }
    if (!_sameCode(token, config.code)) {
      _failedPairings++;
      await conn.send(const PairReject(reason: 'invalid_code'));
      return null;
    }
    return _Auth.code;
  }

  Future<void> _receive(_Conn conn, String peerName, TransferOffer offer) async {
    final id = offer.transferId;
    final parts = [for (final f in offer.files) sanitizeName(f.name)];
    final total = offer.files.fold(0, (sum, f) => sum + f.size);

    final decision = Completer<bool>();
    _pending[id] = decision;
    _emit(OfferEvent(id, peerName: peerName, files: offer.files));

    // Mientras el usuario decide, el emisor puede mandar `cancel`. La lectura queda
    // en curso y se reutiliza como primer frame si el usuario acepta.
    final firstRead = conn.reader.next();
    final Object? outcome;
    try {
      outcome = await Future.any<Object?>([
        decision.future.timeout(offerTimeout, onTimeout: () => false),
        firstRead.then((frame) => _Early(frame)),
      ]);
    } finally {
      _pending.remove(id);
    }
    if (outcome is _Early) {
      throw _control(outcome.frame) is Cancel
          ? const TransferException('cancelled')
          : TransferException.unexpected;
    }
    if (outcome != true) {
      await conn.send(TransferReject(transferId: id, reason: 'declined'));
      _emit(FailedEvent(id, direction: Direction.receive, reason: 'declined'));
      return;
    }
    await conn.send(TransferAccept(transferId: id));

    final cancel = _trackCancel(id);
    Future<Frame?>? carried = firstRead;
    Future<Frame?> next() async {
      final read = carried ?? conn.reader.next();
      carried = null;
      final frame = await _orCancel(read, cancel);
      if (frame is ControlFrame) {
        switch (frame.message) {
          case Cancel():
            throw const TransferException('cancelled');
          case TransferError(:final reason):
            throw TransferException.fromReason(reason);
          default:
        }
      }
      return frame;
    }

    try {
      final progress = _Progress(this, id, Direction.receive, total);
      final saved = <String>[];
      for (var index = 0; index < offer.files.length; index++) {
        final file = offer.files[index];
        progress.startFile(file.name);
        final dest = uniqueDestination(config.downloadDir, parts[index]);
        saved.add(await _receiveFile(file, index, dest, next, progress));
      }
      if (_control(await next()) is! TransferDone) throw TransferException.unexpected;
      await conn.send(TransferComplete(transferId: id));
      _emit(CompletedEvent(id, direction: Direction.receive, files: saved));
    } on TransferException catch (e) {
      if (e.code == 'cancelled' && cancel.isCompleted) {
        await conn.trySend(Cancel(transferId: id));
      }
      rethrow;
    } finally {
      _cancels.remove(id);
    }
  }

  Future<String> _receiveFile(
    FileInfo file,
    int index,
    String dest,
    Future<Frame?> Function() next,
    _Progress progress,
  ) async {
    await File(dest).parent.create(recursive: true);
    final part = File(partPath(dest));
    final sink = part.openWrite();
    var closed = false;
    var kept = false;
    try {
      final digest = _DigestSink();
      final hasher = sha256.startChunkedConversion(digest);
      var remaining = file.size;
      while (remaining > 0) {
        final frame = await next();
        if (frame is! DataFrame) throw TransferException.unexpected;
        final n = frame.bytes.length;
        if (n == 0 || n > remaining) throw TransferException.unexpected;
        hasher.add(frame.bytes);
        sink.add(frame.bytes);
        remaining -= n;
        progress.advance(n);
      }
      await sink.close();
      closed = true;
      hasher.close();

      final end = _control(await next());
      if (end is! FileEnd || end.index != index) throw TransferException.unexpected;
      if (end.hash != digest.value.toString()) {
        throw TransferException('hash_mismatch', file.name);
      }
      await part.rename(dest);
      kept = true;
      return dest;
    } finally {
      if (!closed) {
        try {
          await sink.close();
        } catch (_) {}
      }
      if (!kept) {
        try {
          await part.delete();
        } catch (_) {}
      }
    }
  }

  // ----------------------------------------------------------- compartido

  /// Conecta, saluda y presenta `token` (código, token del enlace o vacío para pedir
  /// permiso). `wait`: tope para cada respuesta del otro lado.
  Future<(_Conn, String)> _connect(
    String host,
    int port,
    String token, {
    Duration wait = _handshakeTimeout,
  }) async {
    final Socket socket;
    try {
      socket = await Socket.connect(host, port, timeout: _connectTimeout);
    } on SocketException catch (e) {
      throw TransferException('unreachable', e);
    }
    socket.setOption(SocketOption.tcpNoDelay, true);
    final conn = _Conn(socket);
    try {
      await conn.send(_hello());
      final hello = await conn.readMessage().timeout(wait);
      if (hello is! Hello) throw TransferException.unexpected;
      if (hello.version != protocolVersion) throw const TransferException('version_mismatch');
      await conn.send(PairRequest(token: token, fingerprint: ''));
      switch (await conn.readMessage().timeout(wait)) {
        case PairAccept():
          return (conn, hello.deviceName);
        case PairReject(:final reason):
          throw TransferException.fromReason(reason);
        default:
          throw TransferException.unexpected;
      }
    } catch (_) {
      conn.close();
      rethrow;
    }
  }

  Hello _hello() =>
      Hello(version: protocolVersion, deviceId: config.deviceId, deviceName: config.deviceName);

  Completer<void> _trackCancel(String id) => _cancels[id] = Completer<void>();

  /// Espera `read`, o corta con `cancelled` si el usuario cancela antes.
  Future<Frame?> _orCancel(Future<Frame?> read, Completer<void> cancel) async {
    final result = await Future.any<Object?>([read, cancel.future.then((_) => _cancelled)]);
    if (identical(result, _cancelled)) throw const TransferException('cancelled');
    return result as Frame?;
  }

  void _emit(TransferEvent event) {
    if (!_events.isClosed) _events.add(event);
  }

  void _emitLink() {
    if (!_linkChanges.isClosed) _linkChanges.add(linkState);
  }

  void _emitPrompt(LinkPromptEvent event) {
    if (!_prompts.isClosed) _prompts.add(event);
  }
}

/// Cómo se autenticó el otro lado.
enum _Auth {
  /// Con nuestro código de 6 dígitos.
  code,

  /// Con el token del enlace actual.
  session,

  /// Sin código: nuestro usuario aceptó (solo sirve para abrir un enlace).
  approved,
}

String newTransferId() {
  final random = Random.secure();
  return List.generate(8, (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
}

final _cancelled = Object();

class _Early {
  const _Early(this.frame);

  final Frame? frame;
}

Message _control(Frame? frame) {
  if (frame is ControlFrame) return frame.message;
  throw TransferException.unexpected;
}

/// Comparación que no corta en el primer byte distinto.
bool _sameCode(String a, String b) {
  if (a.length != b.length) return false;
  var diff = 0;
  for (var i = 0; i < a.length; i++) {
    diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
  }
  return diff == 0;
}

TransferException _asTransfer(Object error) => switch (error) {
  TransferException() => error,
  TimeoutException() => const TransferException('timeout'),
  FormatException() ||
  IncompleteFrame() ||
  MessageTooLarge() => TransferException('protocol', error),
  _ => TransferException('io', error),
};

class _Conn {
  _Conn(this.socket) : reader = FrameReader(socket);

  final Socket socket;
  final FrameReader reader;

  Future<void> send(Message message) async {
    socket.add(encodeMessage(message));
    await socket.flush();
  }

  Future<void> trySend(Message message) async {
    try {
      await send(message);
    } catch (_) {}
  }

  Future<void> sendData(Uint8List bytes) async {
    socket.add(encodeFrame(DataFrame(bytes)));
    await socket.flush();
  }

  Future<Message> readMessage() async => _control(await reader.next());

  void close() {
    unawaited(reader.cancel());
    socket.destroy();
  }
}

/// Lectura en curso del otro lado mientras enviamos; `check` corta si ya respondió.
class _PeerWatch {
  _PeerWatch(this.future) {
    future.then(
      (frame) {
        _frame = frame;
        _done = true;
      },
      onError: (Object e) {
        _error = e;
        _done = true;
      },
    );
  }

  final Future<Frame?> future;
  bool _done = false;
  Frame? _frame;
  Object? _error;

  void check() {
    if (!_done) return;
    if (_error != null) throw _asTransfer(_error!);
    switch (_control(_frame)) {
      case Cancel():
        throw const TransferException('cancelled');
      case TransferError(:final reason):
        throw TransferException.fromReason(reason);
      default:
        throw TransferException.unexpected;
    }
  }
}

/// Emite [ProgressEvent] como mucho cada 100 ms, y siempre al cambiar de archivo y al terminar.
class _Progress {
  _Progress(this._engine, this._id, this._direction, this._total);

  static const _interval = Duration(milliseconds: 100);

  final TransferEngine _engine;
  final String _id;
  final Direction _direction;
  final int _total;
  final _clock = Stopwatch()..start();
  int _done = 0;
  String _current = '';

  void startFile(String name) {
    _current = name;
    _emit();
  }

  void advance(int bytes) {
    _done += bytes;
    if (_done == _total || _clock.elapsed >= _interval) _emit();
  }

  void _emit() {
    _clock.reset();
    _engine._emit(
      ProgressEvent(
        _id,
        direction: _direction,
        bytesDone: _done,
        bytesTotal: _total,
        currentFile: _current,
      ),
    );
  }
}

class _DigestSink implements Sink<Digest> {
  late Digest value;

  @override
  void add(Digest data) => value = data;

  @override
  void close() {}
}
