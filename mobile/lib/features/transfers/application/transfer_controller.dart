// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0.
// If a copy of the MPL was not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../data/platform/device_storage.dart';
import '../../../data/transfer/transfer_engine.dart';
import 'transfer_item.dart';

/// Estado de las transferencias para la interfaz, a partir de los eventos del motor.
/// Lo recibido se mueve a Descargas/Trasvo al terminar.
class TransferController extends ChangeNotifier {
  TransferController({required this._engine, required this._storage, required this._prefs}) {
    _loadHistory();
  }

  static const _historyKey = 'history';
  static const _historyLimit = 100;

  final TransferEngine _engine;
  final DeviceStorage _storage;
  final SharedPreferences _prefs;
  final _items = <String, TransferItem>{};
  final _order = <String>[];
  StreamSubscription<TransferEvent>? _sub;
  int? _port;

  /// De la más nueva a la más vieja.
  List<TransferItem> get items => [for (final id in _order) _items[id]!];

  /// La oferta entrante más vieja sin responder.
  TransferItem? get pendingOffer =>
      items.reversed.where((t) => t.status == TransferStatus.offer).firstOrNull;

  /// Puerto en el que recibimos (`null` hasta que arranca o si falló).
  int? get port => _port;

  String get code => _engine.config.code;

  /// Escucha eventos y abre el servidor (puerto fijo; si está ocupado, uno libre).
  Future<void> start() async {
    _sub ??= _engine.events.listen(handleEvent);
    try {
      _port = await _engine.listen();
    } on SocketException {
      _port = await _engine.listen(port: 0);
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _sub?.cancel();
    unawaited(_engine.close());
    super.dispose();
  }

  void accept(String id) => _answer(id, true);

  void reject(String id) => _answer(id, false);

  void _answer(String id, bool accept) {
    final item = _items[id];
    if (item == null) return;
    _put(
      accept
          ? item.copyWith(status: TransferStatus.active)
          : item.copyWith(status: TransferStatus.declined, finishedAt: DateTime.now()),
    );
    _engine.respond(id, accept);
  }

  /// El estado final llega del motor como `FailedEvent('cancelled')`.
  void cancel(String id) => _engine.cancel(id);

  /// Empieza a enviar a la PC enlazada; el progreso y el resultado llegan como eventos.
  void send(List<OutgoingFile> files) {
    final id = newTransferId();
    _put(
      TransferItem(
        id: id,
        direction: Direction.send,
        status: TransferStatus.waiting,
        startedAt: DateTime.now(),
        peerName: _engine.linkState.peer?.name ?? '',
        fileCount: files.length,
        bytesTotal: files.fold(0, (sum, f) => sum + f.size),
      ),
    );
    unawaited(_engine.sendLinked(id, files).catchError((Object _) {}));
  }

  @visibleForTesting
  void handleEvent(TransferEvent event) {
    final now = DateTime.now();
    final current = _items[event.transferId];
    TransferItem base(Direction direction) =>
        current ??
        TransferItem(
          id: event.transferId,
          direction: direction,
          status: TransferStatus.waiting,
          startedAt: now,
        );

    switch (event) {
      case OfferEvent(:final peerName, :final files):
        _put(
          base(Direction.receive).copyWith(
            status: TransferStatus.offer,
            peerName: peerName,
            files: [for (final f in files) f.name],
            fileCount: files.length,
            bytesTotal: event.totalBytes,
          ),
        );
      case WaitingEvent(:final peerName, :final fileCount, :final totalBytes):
        _put(
          base(Direction.send).copyWith(
            status: TransferStatus.waiting,
            peerName: peerName,
            fileCount: fileCount,
            bytesTotal: totalBytes,
          ),
        );
      case ProgressEvent(:final direction, :final bytesDone, :final bytesTotal, :final currentFile):
        final item = base(direction);
        _put(
          item.copyWith(
            status: item.isFinished ? item.status : TransferStatus.active,
            bytesDone: bytesDone,
            bytesTotal: bytesTotal,
            currentFile: currentFile,
          ),
        );
      case CompletedEvent(:final direction, :final files):
        final item = base(direction);
        if (direction == Direction.receive) {
          unawaited(_moveToDownloads(item, files));
        } else {
          _put(
            item.copyWith(
              status: TransferStatus.done,
              files: files,
              fileCount: files.length,
              bytesDone: item.bytesTotal,
              finishedAt: now,
            ),
          );
        }
      case FailedEvent(:final direction, :final reason):
        _put(
          base(direction).copyWith(
            status: reason == 'declined' ? TransferStatus.declined : TransferStatus.failed,
            reason: reason,
            finishedAt: now,
          ),
        );
    }
  }

  /// Lo recibido está en la caché de la app: pasa a Descargas/Trasvo.
  Future<void> _moveToDownloads(TransferItem item, List<String> received) async {
    final incoming = _engine.config.downloadDir.path;
    final saved = <String>[];
    try {
      for (final path in received) {
        final relative = path.substring(incoming.length + 1).replaceAll(r'\', '/');
        final slash = relative.lastIndexOf('/');
        final subfolder = slash < 0 ? '' : relative.substring(0, slash);
        saved.add(await _storage.saveToDownloads(path, subfolder: subfolder));
      }
      _put(
        item.copyWith(
          status: TransferStatus.done,
          files: saved,
          fileCount: saved.length,
          bytesDone: item.bytesTotal,
          finishedAt: DateTime.now(),
        ),
      );
    } catch (_) {
      _put(item.copyWith(status: TransferStatus.failed, reason: 'io', finishedAt: DateTime.now()));
    }
  }

  void _put(TransferItem item) {
    if (!_items.containsKey(item.id)) _order.insert(0, item.id);
    _items[item.id] = item;
    if (item.isFinished) _saveHistory();
    notifyListeners();
  }

  void _loadHistory() {
    try {
      final raw = _prefs.getString(_historyKey);
      if (raw == null) return;
      for (final json in (jsonDecode(raw) as List<dynamic>).cast<Map<String, dynamic>>()) {
        final item = TransferItem.fromJson(json);
        if (!item.isFinished) continue;
        _items[item.id] = item;
        _order.add(item.id);
      }
    } catch (_) {
      // Historial dañado: se empieza de cero.
    }
  }

  void _saveHistory() {
    final finished = items.where((t) => t.isFinished).take(_historyLimit);
    unawaited(_prefs.setString(_historyKey, jsonEncode([for (final t in finished) t.toJson()])));
  }
}
