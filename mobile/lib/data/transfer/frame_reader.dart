// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0.
// If a copy of the MPL was not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

import 'dart:async';
import 'dart:typed_data';

import '../../domain/protocol/codec.dart';

/// Lee frames completos de un stream de bytes (un socket).
///
/// Solo hay una lectura en curso a la vez: llamar a [next] mientras otra está
/// pendiente devuelve el mismo future. Así se puede "escuchar" al otro lado
/// mientras se espera otra cosa sin perder frames.
class FrameReader {
  FrameReader(Stream<Uint8List> stream) {
    _sub = stream.listen(
      _onData,
      onError: (Object e) {
        _error = e;
        _wake();
      },
      onDone: () {
        _done = true;
        _wake();
      },
    );
  }

  static const _pauseAbove = 4 * 1024 * 1024;

  late final StreamSubscription<Uint8List> _sub;
  Uint8List _buf = Uint8List(0);
  int _start = 0;
  bool _done = false;
  Object? _error;
  Completer<void>? _waiter;
  Future<Frame?>? _inflight;

  int get _available => _buf.length - _start;

  /// Siguiente frame, o `null` si el otro lado cerró limpiamente entre frames.
  Future<Frame?> next() => _inflight ??= _next().whenComplete(() => _inflight = null);

  Future<void> cancel() => _sub.cancel();

  Future<Frame?> _next() async {
    while (true) {
      final frame = _tryDecode();
      if (frame != null) return frame;
      if (_error != null) throw _error!;
      if (_done) {
        if (_available == 0) return null;
        throw const IncompleteFrame();
      }
      if (_sub.isPaused) _sub.resume();
      _waiter = Completer<void>();
      await _waiter!.future;
    }
  }

  Frame? _tryDecode() {
    if (_available < 4) return null;
    final view = Uint8List.sublistView(_buf, _start);
    final length = ByteData.sublistView(view).getUint32(0);
    if (length == 0 || length > maxFrameBody) {
      // decodeFrame lanza el error adecuado.
      decodeFrame(view);
    }
    if (_available < 4 + length) return null;
    final (frame, used) = decodeFrame(view);
    _start += used;
    return frame;
  }

  void _onData(Uint8List data) {
    // Compacta lo ya leído y agrega lo nuevo.
    final rest = _available;
    final merged = Uint8List(rest + data.length)
      ..setRange(0, rest, _buf, _start)
      ..setRange(rest, rest + data.length, data);
    _buf = merged;
    _start = 0;
    if (_available > _pauseAbove) _sub.pause();
    _wake();
  }

  void _wake() {
    final waiter = _waiter;
    _waiter = null;
    if (waiter != null && !waiter.isCompleted) waiter.complete();
  }
}
