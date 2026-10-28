// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0.
// If a copy of the MPL was not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';

import '../../../core/di/app_scope.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/ui/format.dart';
import '../../../data/media/media_library.dart';
import '../../connect/presentation/connect_page.dart';
import '../application/send_selection.dart';
import 'media_grid.dart';

/// Elegir fotos, videos o documentos y enviarlos a la PC conectada.
class SendPage extends StatefulWidget {
  const SendPage({super.key});

  @override
  State<SendPage> createState() => _SendPageState();
}

class _SendPageState extends State<SendPage> {
  final _selection = SendSelection();
  bool _preparing = false;

  @override
  void dispose() {
    _selection.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final services = AppScope.of(context);
    if (services.connection.peer == null) {
      await Navigator.of(context)
          .push<bool>(MaterialPageRoute(builder: (_) => const ConnectPage()));
      if (services.connection.peer == null || !mounted) return;
    }
    setState(() => _preparing = true);
    try {
      final files = await _selection.resolve(services.media);
      services.transfers.send(files);
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (!mounted) return;
      setState(() => _preparing = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(reasonText('io'))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Elegir qué enviar'),
          bottom: const TabBar(
            tabs: [
              Tab(icon: Icon(Icons.photo_outlined), text: 'Fotos'),
              Tab(icon: Icon(Icons.videocam_outlined), text: 'Videos'),
              Tab(icon: Icon(Icons.folder_outlined), text: 'Archivos'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            MediaGrid(kind: MediaKind.photo, library: services.media, selection: _selection),
            MediaGrid(kind: MediaKind.video, library: services.media, selection: _selection),
            _DocumentsTab(selection: _selection),
          ],
        ),
        bottomNavigationBar: ListenableBuilder(
          listenable: Listenable.merge([_selection, services.connection]),
          builder: (context, _) => _SendBar(
            count: _selection.count,
            peerName: services.connection.peer?.name,
            preparing: _preparing,
            onSend: _send,
            onClear: _selection.clear,
          ),
        ),
      ),
    );
  }
}

class _SendBar extends StatelessWidget {
  const _SendBar({
    required this.count,
    required this.peerName,
    required this.preparing,
    required this.onSend,
    required this.onClear,
  });

  final int count;
  final String? peerName;
  final bool preparing;
  final VoidCallback onSend;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      decoration: BoxDecoration(
        color: c.surface,
        border: Border(top: BorderSide(color: c.border)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      count == 0
                          ? 'Toca las fotos o archivos que quieras enviar.'
                          : peerName == null
                          ? '${plural(count, 'elegido', 'elegidos')} · conecta tu PC para enviar'
                          : '${plural(count, 'elegido', 'elegidos')} · se enviarán a $peerName',
                      style: TextStyle(color: c.textSecondary),
                    ),
                  ),
                  if (count > 0) TextButton(onPressed: onClear, child: const Text('Quitar todo')),
                ],
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: count == 0 || preparing ? null : onSend,
                  icon: preparing
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.upload_rounded),
                  label: Text(
                    preparing
                        ? 'Preparando…'
                        : count == 0
                        ? 'Enviar'
                        : 'Enviar ${plural(count, 'elemento', 'elementos')}',
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DocumentsTab extends StatelessWidget {
  const _DocumentsTab({required this.selection});

  final SendSelection selection;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final picker = AppScope.of(context).documents;
    return ListenableBuilder(
      listenable: selection,
      builder: (context, _) => ListView(
        padding: const EdgeInsets.all(16),
        children: [
          OutlinedButton.icon(
            onPressed: () async => selection.addDocuments(await picker.pick()),
            icon: const Icon(Icons.add),
            label: const Text('Elegir documentos'),
          ),
          const SizedBox(height: 8),
          Text(
            'PDF, música, ZIP o cualquier otro archivo.',
            textAlign: TextAlign.center,
            style: TextStyle(color: c.textSecondary),
          ),
          const SizedBox(height: 16),
          for (final file in selection.documents)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Container(
                decoration: BoxDecoration(
                  color: c.sunken,
                  borderRadius: BorderRadius.circular(Tokens.radiusMd),
                ),
                child: ListTile(
                  leading: Icon(Icons.insert_drive_file_outlined, color: c.primary),
                  title: Text(file.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text(formatBytes(file.size)),
                  trailing: IconButton(
                    tooltip: 'Quitar ${file.name}',
                    icon: const Icon(Icons.close),
                    onPressed: () => selection.removeDocument(file),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
