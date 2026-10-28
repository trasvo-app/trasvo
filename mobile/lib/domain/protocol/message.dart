// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0.
// If a copy of the MPL was not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

/// Mensajes de control (ver docs/protocol.md).
library;

const protocolVersion = 1;
const defaultPort = 47520;
const maxControlMessageBytes = 1024 * 1024;

class FileInfo {
  const FileInfo({required this.name, required this.size});

  factory FileInfo.fromJson(Map<String, dynamic> json) =>
      FileInfo(name: json['name'] as String, size: json['size'] as int);

  /// Ruta relativa con `/` (p. ej. `Fotos/playa.jpg`).
  final String name;
  final int size;

  Map<String, dynamic> toJson() => {'name': name, 'size': size};
}

sealed class Message {
  const Message();

  factory Message.fromJson(Map<String, dynamic> json) {
    String s(String key) => json[key] as String;
    return switch (json['type']) {
      'hello' => Hello(
        version: json['version'] as int,
        deviceId: s('device_id'),
        deviceName: s('device_name'),
      ),
      'pair_request' => PairRequest(token: s('token'), fingerprint: s('fingerprint')),
      'pair_accept' => PairAccept(deviceId: s('device_id')),
      'pair_reject' => PairReject(reason: s('reason')),
      'transfer_offer' => TransferOffer(
        transferId: s('transfer_id'),
        files: [
          for (final f in json['files'] as List<dynamic>)
            FileInfo.fromJson(f as Map<String, dynamic>),
        ],
      ),
      'transfer_accept' => TransferAccept(transferId: s('transfer_id')),
      'transfer_reject' => TransferReject(transferId: s('transfer_id'), reason: s('reason')),
      'file_end' => FileEnd(
        transferId: s('transfer_id'),
        index: json['index'] as int,
        hash: s('hash'),
      ),
      'transfer_done' => TransferDone(transferId: s('transfer_id')),
      'transfer_complete' => TransferComplete(transferId: s('transfer_id')),
      'transfer_error' => TransferError(transferId: s('transfer_id'), reason: s('reason')),
      'cancel' => Cancel(transferId: s('transfer_id')),
      'link_open' => LinkOpen(token: s('token'), port: json['port'] as int),
      'link_accept' => const LinkAccept(),
      'ping' => const Ping(),
      'link_close' => const LinkClose(),
      final other => throw FormatException('Unknown message type: $other'),
    };
  }

  Map<String, dynamic> toJson();
}

class Hello extends Message {
  const Hello({required this.version, required this.deviceId, required this.deviceName});

  final int version;
  final String deviceId;
  final String deviceName;

  @override
  Map<String, dynamic> toJson() => {
    'type': 'hello',
    'version': version,
    'device_id': deviceId,
    'device_name': deviceName,
  };
}

class PairRequest extends Message {
  const PairRequest({required this.token, required this.fingerprint});

  final String token;
  final String fingerprint;

  @override
  Map<String, dynamic> toJson() => {
    'type': 'pair_request',
    'token': token,
    'fingerprint': fingerprint,
  };
}

class PairAccept extends Message {
  const PairAccept({required this.deviceId});

  final String deviceId;

  @override
  Map<String, dynamic> toJson() => {'type': 'pair_accept', 'device_id': deviceId};
}

class PairReject extends Message {
  const PairReject({required this.reason});

  final String reason;

  @override
  Map<String, dynamic> toJson() => {'type': 'pair_reject', 'reason': reason};
}

class TransferOffer extends Message {
  const TransferOffer({required this.transferId, required this.files});

  final String transferId;
  final List<FileInfo> files;

  @override
  Map<String, dynamic> toJson() => {
    'type': 'transfer_offer',
    'transfer_id': transferId,
    'files': [for (final f in files) f.toJson()],
  };
}

class TransferAccept extends Message {
  const TransferAccept({required this.transferId});

  final String transferId;

  @override
  Map<String, dynamic> toJson() => {'type': 'transfer_accept', 'transfer_id': transferId};
}

class TransferReject extends Message {
  const TransferReject({required this.transferId, required this.reason});

  final String transferId;
  final String reason;

  @override
  Map<String, dynamic> toJson() => {
    'type': 'transfer_reject',
    'transfer_id': transferId,
    'reason': reason,
  };
}

class FileEnd extends Message {
  const FileEnd({required this.transferId, required this.index, required this.hash});

  final String transferId;
  final int index;

  /// SHA-256 del archivo en hexadecimal (minúsculas).
  final String hash;

  @override
  Map<String, dynamic> toJson() => {
    'type': 'file_end',
    'transfer_id': transferId,
    'index': index,
    'hash': hash,
  };
}

class TransferDone extends Message {
  const TransferDone({required this.transferId});

  final String transferId;

  @override
  Map<String, dynamic> toJson() => {'type': 'transfer_done', 'transfer_id': transferId};
}

class TransferComplete extends Message {
  const TransferComplete({required this.transferId});

  final String transferId;

  @override
  Map<String, dynamic> toJson() => {'type': 'transfer_complete', 'transfer_id': transferId};
}

class TransferError extends Message {
  const TransferError({required this.transferId, required this.reason});

  final String transferId;
  final String reason;

  @override
  Map<String, dynamic> toJson() => {
    'type': 'transfer_error',
    'transfer_id': transferId,
    'reason': reason,
  };
}

class Cancel extends Message {
  const Cancel({required this.transferId});

  final String transferId;

  @override
  Map<String, dynamic> toJson() => {'type': 'cancel', 'transfer_id': transferId};
}

/// Abre un enlace persistente. `token` autentica las transferencias en ambos sentidos
/// mientras dure; `port` es donde escucha quien abre el enlace.
class LinkOpen extends Message {
  const LinkOpen({required this.token, required this.port});

  final String token;
  final int port;

  @override
  Map<String, dynamic> toJson() => {'type': 'link_open', 'token': token, 'port': port};
}

class LinkAccept extends Message {
  const LinkAccept();

  @override
  Map<String, dynamic> toJson() => {'type': 'link_accept'};
}

/// Latido del enlace, en ambos sentidos.
class Ping extends Message {
  const Ping();

  @override
  Map<String, dynamic> toJson() => {'type': 'ping'};
}

/// Cierre del enlace pedido por el usuario.
class LinkClose extends Message {
  const LinkClose();

  @override
  Map<String, dynamic> toJson() => {'type': 'link_close'};
}
