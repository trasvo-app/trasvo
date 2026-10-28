// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0.
// If a copy of the MPL was not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/ui/format.dart';
import '../../../data/transfer/transfer_types.dart';
import '../application/transfer_item.dart';

/// Una transferencia en la lista de actividad: estado, progreso y «Cancelar».
class TransferTile extends StatelessWidget {
  const TransferTile({super.key, required this.item, this.onCancel});

  final TransferItem item;
  final VoidCallback? onCancel;

  String get _title {
    final peer = item.peerName.isEmpty ? 'la PC' : item.peerName;
    final send = item.direction == Direction.send;
    return switch (item.status) {
      TransferStatus.done => send ? 'Enviado a $peer' : 'Recibido de $peer',
      TransferStatus.offer || TransferStatus.waiting || TransferStatus.active =>
        send ? 'Enviando a $peer' : 'Recibiendo de $peer',
      _ => send ? 'Envío a $peer' : 'Recepción de $peer',
    };
  }

  String get _subtitle => switch (item.status) {
        TransferStatus.offer => 'Esperando tu respuesta…',
        TransferStatus.waiting => 'Esperando que acepte en la PC…',
        TransferStatus.active =>
          '${item.currentFile.isEmpty ? 'Preparando…' : item.currentFile} · '
              '${formatBytes(item.bytesDone)} de ${formatBytes(item.bytesTotal)}',
        TransferStatus.done => item.direction == Direction.receive
            ? 'Guardado en Descargas/Trasvo'
            : '${plural(item.fileCount, 'archivo', 'archivos')} · ${formatBytes(item.bytesTotal)}',
        TransferStatus.declined =>
          item.direction == Direction.receive ? 'Lo rechazaste.' : reasonText('declined'),
        TransferStatus.failed => reasonText(item.reason),
      };

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final text = Theme.of(context).textTheme;
    final (icon, fg, bg) = switch (item.status) {
      TransferStatus.done => (Icons.check_rounded, c.success, c.successTint),
      TransferStatus.failed || TransferStatus.declined => (Icons.close_rounded, c.error, c.errorTint),
      _ => (
          item.direction == Direction.send ? Icons.upload_rounded : Icons.download_rounded,
          c.primary,
          c.primaryTint,
        ),
    };

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: c.sunken,
        borderRadius: BorderRadius.circular(Tokens.radiusMd),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(Tokens.radiusSm)),
            child: Icon(icon, color: fg, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        _title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: text.titleSmall?.copyWith(color: c.text, fontWeight: FontWeight.w600),
                      ),
                    ),
                    if (item.status == TransferStatus.active)
                      Text(
                        '${(item.fraction * 100).floor()}%',
                        style: TextStyle(
                          color: c.text,
                          fontWeight: FontWeight.w600,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  _subtitle,
                  maxLines: item.status == TransferStatus.failed ? 3 : 1,
                  overflow: TextOverflow.ellipsis,
                  style: text.bodySmall?.copyWith(
                    color: item.status == TransferStatus.failed ? c.error : c.textSecondary,
                  ),
                ),
                if (item.inProgress) ...[
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: LinearProgressIndicator(
                      minHeight: 6,
                      value: item.status == TransferStatus.active ? item.fraction : null,
                      backgroundColor: c.border,
                      color: c.primary,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (item.inProgress && onCancel != null)
            TextButton(onPressed: onCancel, child: const Text('Cancelar')),
        ],
      ),
    );
  }
}
