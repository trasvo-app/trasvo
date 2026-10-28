// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0.
// If a copy of the MPL was not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/ui/format.dart';
import '../../../core/ui/surface_card.dart';
import '../application/transfer_controller.dart';
import '../application/transfer_item.dart';

/// Muestra «X quiere enviarte archivos» en cualquier pantalla, una oferta a la vez.
class OfferListener extends StatefulWidget {
  const OfferListener({
    super.key,
    required this.transfers,
    required this.navigatorKey,
    required this.child,
  });

  final TransferController transfers;
  final GlobalKey<NavigatorState> navigatorKey;
  final Widget child;

  @override
  State<OfferListener> createState() => _OfferListenerState();
}

class _OfferListenerState extends State<OfferListener> {
  String? _showing;

  @override
  void initState() {
    super.initState();
    widget.transfers.addListener(_check);
  }

  @override
  void dispose() {
    widget.transfers.removeListener(_check);
    super.dispose();
  }

  void _check() {
    final offer = widget.transfers.pendingOffer;
    if (offer == null || _showing != null) return;
    final context = widget.navigatorKey.currentContext;
    if (context == null) return;
    _showing = offer.id;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => OfferDialog(offer: offer, transfers: widget.transfers),
    ).whenComplete(() {
      _showing = null;
      // Puede haber llegado otra mientras tanto.
      WidgetsBinding.instance.addPostFrameCallback((_) => _check());
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class OfferDialog extends StatelessWidget {
  const OfferDialog({super.key, required this.offer, required this.transfers});

  static const _maxListed = 5;

  final TransferItem offer;
  final TransferController transfers;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final text = Theme.of(context).textTheme;
    final extra = offer.files.length - _maxListed;

    return Dialog(
      backgroundColor: c.surface,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const TintedIcon(Icons.download_rounded, size: 52),
            const SizedBox(height: 16),
            Text(
              '${offer.peerName} quiere enviarte archivos',
              style: text.titleLarge?.copyWith(color: c.text, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text(
              '${plural(offer.fileCount, 'archivo', 'archivos')} · ${formatBytes(offer.bytesTotal)}',
              style: text.bodyMedium?.copyWith(color: c.textSecondary),
            ),
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: c.sunken, borderRadius: BorderRadius.circular(12)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final name in offer.files.take(_maxListed))
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Row(
                        children: [
                          Icon(Icons.insert_drive_file_outlined, size: 16, color: c.textSecondary),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(color: c.text)),
                          ),
                        ],
                      ),
                    ),
                  if (extra > 0)
                    Text('y ${plural(extra, 'archivo más', 'archivos más')}',
                        style: TextStyle(color: c.textSecondary)),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () {
                      transfers.reject(offer.id);
                      Navigator.of(context).pop();
                    },
                    child: const Text('Rechazar'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    autofocus: true,
                    onPressed: () {
                      transfers.accept(offer.id);
                      Navigator.of(context).pop();
                    },
                    child: const Text('Aceptar'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
