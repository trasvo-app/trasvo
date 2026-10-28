// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0.
// If a copy of the MPL was not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

import 'dart:io';

import '../../domain/protocol/message.dart';

/// Tipos públicos del motor de transferencia (equivalentes a `ft_transfer` en Rust).

enum Direction { send, receive }

sealed class TransferEvent {
  const TransferEvent(this.transferId);

  final String transferId;
}

/// Alguien quiere enviarnos archivos: hay que llamar a `TransferEngine.respond`.
class OfferEvent extends TransferEvent {
  const OfferEvent(super.transferId, {required this.peerName, required this.files});

  final String peerName;
  final List<FileInfo> files;

  int get totalBytes => files.fold(0, (sum, f) => sum + f.size);
}

/// Enviamos una oferta y esperamos la respuesta del otro lado.
class WaitingEvent extends TransferEvent {
  const WaitingEvent(
    super.transferId, {
    required this.peerName,
    required this.fileCount,
    required this.totalBytes,
  });

  final String peerName;
  final int fileCount;
  final int totalBytes;
}

class ProgressEvent extends TransferEvent {
  const ProgressEvent(
    super.transferId, {
    required this.direction,
    required this.bytesDone,
    required this.bytesTotal,
    required this.currentFile,
  });

  final Direction direction;
  final int bytesDone;
  final int bytesTotal;
  final String currentFile;
}

/// `files`: rutas guardadas (al recibir) o nombres enviados (al enviar).
class CompletedEvent extends TransferEvent {
  const CompletedEvent(super.transferId, {required this.direction, required this.files});

  final Direction direction;
  final List<String> files;
}

class FailedEvent extends TransferEvent {
  const FailedEvent(super.transferId, {required this.direction, required this.reason});

  final Direction direction;
  final String reason;
}

enum LinkStatus {
  connected,

  /// Se cortó la red: se reintenta solo, sin pedir nada al usuario.
  reconnecting,
  disconnected,
}

/// El otro dispositivo del enlace.
class Peer {
  const Peer({required this.name, required this.host, required this.port});

  final String name;
  final String host;
  final int port;
}

class LinkState {
  const LinkState(this.status, [this.peer]);

  static const disconnected = LinkState(LinkStatus.disconnected);

  final LinkStatus status;

  /// `null` si no hay enlace.
  final Peer? peer;
}

/// Peticiones de conexión sin código (desde un dispositivo encontrado en el Wi-Fi).
sealed class LinkPromptEvent {
  const LinkPromptEvent(this.requestId);

  final String requestId;
}

/// Hay que responder con `TransferEngine.respond(requestId, aceptar)`.
class LinkRequested extends LinkPromptEvent {
  const LinkRequested(super.requestId, {required this.peerName});

  final String peerName;
}

/// La petición ya no espera respuesta (se respondió o venció).
class LinkRequestEnded extends LinkPromptEvent {
  const LinkRequestEnded(super.requestId);
}

/// Error con un código estable (los mismos que usa Rust y el protocolo).
class TransferException implements Exception {
  const TransferException(this.code, [this.detail]);

  /// `unreachable`, `invalid_code`, `locked`, `version_mismatch`, `declined`,
  /// `hash_mismatch`, `invalid_name`, `empty`, `cancelled`, `timeout`, `io`, `protocol`,
  /// `not_connected`.
  final String code;
  final Object? detail;

  static const unexpected = TransferException('protocol');

  /// Traduce el `reason` que manda el otro lado.
  factory TransferException.fromReason(String reason) => TransferException(switch (reason) {
    'invalid_code' || 'locked' || 'version_mismatch' || 'cancelled' => reason,
    _ => 'declined',
  }, reason);

  @override
  String toString() => 'TransferException($code${detail == null ? '' : ': $detail'})';
}

class EngineConfig {
  const EngineConfig({
    required this.deviceId,
    required this.deviceName,
    required this.code,
    required this.downloadDir,
  });

  final String deviceId;
  final String deviceName;

  /// Código que el otro lado debe presentar para emparejarse con nosotros.
  final String code;
  final Directory downloadDir;
}

/// Un archivo listo para enviar. `open` permite leer desde rutas o desde
/// proveedores de Android (fotos, documentos) sin cambiar el motor.
class OutgoingFile {
  const OutgoingFile({required this.name, required this.size, required this.open});

  factory OutgoingFile.fromFile(File file, {String? name}) => OutgoingFile(
    name: name ?? file.uri.pathSegments.last,
    size: file.lengthSync(),
    open: file.openRead,
  );

  /// Ruta relativa con `/` (las carpetas conservan su estructura).
  final String name;
  final int size;
  final Stream<List<int>> Function() open;
}
