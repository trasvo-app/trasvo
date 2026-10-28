// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0.
// If a copy of the MPL was not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/ui/format.dart';
import '../../../core/ui/surface_card.dart';
import '../../../data/media/media_library.dart';
import '../application/send_selection.dart';

/// Galería con miniaturas reales para elegir fotos o videos.
/// Antes de pedir el permiso explica para qué es.
class MediaGrid extends StatefulWidget {
  const MediaGrid({super.key, required this.kind, required this.library, required this.selection});

  final MediaKind kind;
  final MediaLibrary library;
  final SendSelection selection;

  @override
  State<MediaGrid> createState() => _MediaGridState();
}

class _MediaGridState extends State<MediaGrid> with AutomaticKeepAliveClientMixin {
  static const _pageSize = 90;

  MediaAccess? _access;
  final _items = <MediaItem>[];
  final _thumbs = <String, Future<Uint8List?>>{};
  int _page = 0;
  bool _loading = false;
  bool _done = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final access = await widget.library.currentAccess();
    if (!mounted) return;
    setState(() => _access = access);
    if (_canRead(access)) await _loadMore();
  }

  bool _canRead(MediaAccess? a) => a == MediaAccess.full || a == MediaAccess.limited;

  Future<void> _request() async {
    final access = await widget.library.requestAccess();
    if (!mounted) return;
    setState(() => _access = access);
    if (_canRead(access)) await _reload();
  }

  Future<void> _reload() async {
    setState(() {
      _items.clear();
      _thumbs.clear();
      _page = 0;
      _done = false;
    });
    await _loadMore();
  }

  Future<void> _loadMore() async {
    if (_loading || _done) return;
    setState(() => _loading = true);
    final page = await widget.library.list(widget.kind, page: _page, pageSize: _pageSize);
    if (!mounted) return;
    setState(() {
      _items.addAll(page);
      _page++;
      _done = page.length < _pageSize;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final access = _access;
    if (access == null) return const Center(child: CircularProgressIndicator());
    if (!_canRead(access)) {
      return _PermissionPrompt(
        kind: widget.kind,
        denied: access == MediaAccess.denied,
        onAllow: _request,
        onSettings: widget.library.openSettings,
      );
    }

    final c = context.colors;
    return Column(
      children: [
        if (access == MediaAccess.limited)
          Material(
            color: c.warningTint,
            child: ListTile(
              dense: true,
              leading: Icon(Icons.info_outline, color: c.text),
              title: Text('Solo ves las fotos que permitiste.', style: TextStyle(color: c.text)),
              trailing: TextButton(
                onPressed: () async {
                  await widget.library.chooseMore();
                  await _reload();
                },
                child: const Text('Elegir más'),
              ),
            ),
          ),
        Expanded(
          child: _items.isEmpty && !_loading
              ? _Empty(kind: widget.kind)
              : NotificationListener<ScrollNotification>(
                  onNotification: (n) {
                    if (n.metrics.extentAfter < 600) _loadMore();
                    return false;
                  },
                  child: ListenableBuilder(
                    listenable: widget.selection,
                    builder: (context, _) => GridView.builder(
                      padding: const EdgeInsets.all(4),
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 3,
                        mainAxisSpacing: 4,
                        crossAxisSpacing: 4,
                      ),
                      itemCount: _items.length,
                      itemBuilder: (context, i) {
                        final item = _items[i];
                        return _Thumb(
                          item: item,
                          bytes: _thumbs.putIfAbsent(item.id, () => widget.library.thumbnail(item)),
                          selected: widget.selection.isSelected(item),
                          onTap: () => widget.selection.toggle(item),
                        );
                      },
                    ),
                  ),
                ),
        ),
      ],
    );
  }
}

class _Thumb extends StatelessWidget {
  const _Thumb({required this.item, required this.bytes, required this.selected, required this.onTap});

  final MediaItem item;
  final Future<Uint8List?> bytes;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final label = item.kind == MediaKind.video ? 'Video' : 'Foto';
    return Semantics(
      label: '$label del ${item.created.day}/${item.created.month}/${item.created.year}',
      selected: selected,
      button: true,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedScale(
          // Seleccionado se achica un poco: se nota sin taparlo.
          scale: selected ? 0.88 : 1,
          duration: Tokens.fastDuration,
          curve: Curves.easeOut,
          child: Stack(
            fit: StackFit.expand,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(Tokens.radiusSm),
                child: FutureBuilder<Uint8List?>(
                  future: bytes,
                  builder: (context, snap) => snap.data == null
                      ? ColoredBox(color: c.sunken)
                      : Image.memory(snap.data!, fit: BoxFit.cover, gaplessPlayback: true),
                ),
              ),
              if (item.kind == MediaKind.video)
                Positioned(
                  left: 6,
                  bottom: 6,
                  child: _Badge(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.play_arrow_rounded, size: 14, color: Colors.white),
                        Text(formatDuration(item.duration),
                            style: const TextStyle(color: Colors.white, fontSize: 11)),
                      ],
                    ),
                  ),
                ),
              Positioned(
                right: 6,
                top: 6,
                child: Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: selected ? c.primary : const Color(0x55000000),
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                  child: selected ? const Icon(Icons.check, size: 14, color: Colors.white) : null,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(color: const Color(0x99000000), borderRadius: BorderRadius.circular(6)),
        child: child,
      );
}

class _PermissionPrompt extends StatelessWidget {
  const _PermissionPrompt({
    required this.kind,
    required this.denied,
    required this.onAllow,
    required this.onSettings,
  });

  final MediaKind kind;
  final bool denied;
  final VoidCallback onAllow;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final what = kind == MediaKind.photo ? 'tus fotos' : 'tus videos';
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: SurfaceCard(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const TintedIcon(Icons.photo_library_outlined, size: 56),
              const SizedBox(height: 16),
              Text(
                'Para mostrarte $what necesitamos acceso',
                textAlign: TextAlign.center,
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(color: c.text, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              Text(
                denied
                    ? 'Lo rechazaste antes. Puedes darlo en Ajustes, o enviar documentos desde «Archivos».'
                    : 'Solo las vemos en este teléfono para que elijas cuáles enviar. Nada se sube a internet.',
                textAlign: TextAlign.center,
                style: TextStyle(color: c.textSecondary),
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: denied ? onSettings : onAllow,
                child: Text(denied ? 'Abrir Ajustes' : 'Permitir acceso'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.kind});

  final MediaKind kind;

  @override
  Widget build(BuildContext context) => Center(
        child: Text(
          kind == MediaKind.photo ? 'No hay fotos en este teléfono.' : 'No hay videos en este teléfono.',
          style: TextStyle(color: context.colors.textSecondary),
        ),
      );
}
