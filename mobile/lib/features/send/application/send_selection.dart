// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0.
// If a copy of the MPL was not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

import 'package:flutter/foundation.dart';

import '../../../data/media/media_library.dart';
import '../../../data/transfer/transfer_types.dart';

/// Lo que el usuario eligió para enviar: fotos/videos de la galería y documentos.
class SendSelection extends ChangeNotifier {
  final _media = <String, MediaItem>{};
  final _documents = <OutgoingFile>[];

  List<MediaItem> get media => _media.values.toList();
  List<OutgoingFile> get documents => List.unmodifiable(_documents);
  int get count => _media.length + _documents.length;
  bool get isEmpty => count == 0;

  bool isSelected(MediaItem item) => _media.containsKey(item.id);

  void toggle(MediaItem item) {
    if (_media.remove(item.id) == null) _media[item.id] = item;
    notifyListeners();
  }

  void addDocuments(List<OutgoingFile> files) {
    final known = {for (final f in _documents) f.name};
    _documents.addAll(files.where((f) => known.add(f.name)));
    notifyListeners();
  }

  void removeDocument(OutgoingFile file) {
    _documents.remove(file);
    notifyListeners();
  }

  void clear() {
    _media.clear();
    _documents.clear();
    notifyListeners();
  }

  /// Archivos listos para enviar (lee el nombre real y el tamaño de cada foto).
  Future<List<OutgoingFile>> resolve(MediaLibrary library) async => [
        for (final item in _media.values) await library.toOutgoing(item),
        ..._documents,
      ];
}
