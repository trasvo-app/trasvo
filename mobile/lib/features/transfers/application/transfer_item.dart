// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0.
// If a copy of the MPL was not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

import '../../../data/transfer/transfer_types.dart';

enum TransferStatus { offer, waiting, active, done, failed, declined }

/// Una transferencia tal como la muestra la interfaz.
class TransferItem {
  const TransferItem({
    required this.id,
    required this.direction,
    required this.status,
    required this.startedAt,
    this.peerName = '',
    this.files = const [],
    this.fileCount = 0,
    this.bytesTotal = 0,
    this.bytesDone = 0,
    this.currentFile = '',
    this.reason,
    this.finishedAt,
  });

  factory TransferItem.fromJson(Map<String, dynamic> json) => TransferItem(
        id: json['id'] as String,
        direction: Direction.values.byName(json['direction'] as String),
        status: TransferStatus.values.byName(json['status'] as String),
        startedAt: DateTime.fromMillisecondsSinceEpoch(json['startedAt'] as int),
        finishedAt: json['finishedAt'] == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(json['finishedAt'] as int),
        peerName: json['peerName'] as String? ?? '',
        files: (json['files'] as List<dynamic>? ?? []).cast<String>(),
        fileCount: json['fileCount'] as int? ?? 0,
        bytesTotal: json['bytesTotal'] as int? ?? 0,
        bytesDone: json['bytesDone'] as int? ?? 0,
        reason: json['reason'] as String?,
      );

  final String id;
  final Direction direction;
  final TransferStatus status;
  final DateTime startedAt;
  final DateTime? finishedAt;
  final String peerName;

  /// Nombres ofrecidos; al terminar, dónde quedaron (recibir) o qué se envió.
  final List<String> files;
  final int fileCount;
  final int bytesTotal;
  final int bytesDone;
  final String currentFile;
  final String? reason;

  bool get isFinished =>
      status == TransferStatus.done ||
      status == TransferStatus.failed ||
      status == TransferStatus.declined;

  bool get inProgress => status == TransferStatus.waiting || status == TransferStatus.active;

  double get fraction => bytesTotal == 0 ? (isFinished ? 1 : 0) : bytesDone / bytesTotal;

  TransferItem copyWith({
    TransferStatus? status,
    String? peerName,
    List<String>? files,
    int? fileCount,
    int? bytesTotal,
    int? bytesDone,
    String? currentFile,
    String? reason,
    DateTime? finishedAt,
  }) =>
      TransferItem(
        id: id,
        direction: direction,
        startedAt: startedAt,
        status: status ?? this.status,
        peerName: peerName ?? this.peerName,
        files: files ?? this.files,
        fileCount: fileCount ?? this.fileCount,
        bytesTotal: bytesTotal ?? this.bytesTotal,
        bytesDone: bytesDone ?? this.bytesDone,
        currentFile: currentFile ?? this.currentFile,
        reason: reason ?? this.reason,
        finishedAt: finishedAt ?? this.finishedAt,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'direction': direction.name,
        'status': status.name,
        'startedAt': startedAt.millisecondsSinceEpoch,
        'finishedAt': finishedAt?.millisecondsSinceEpoch,
        'peerName': peerName,
        'files': files,
        'fileCount': fileCount,
        'bytesTotal': bytesTotal,
        'bytesDone': bytesDone,
        'reason': reason,
      };
}
