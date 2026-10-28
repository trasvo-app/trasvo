// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0.
// If a copy of the MPL was not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

import 'package:file_picker/file_picker.dart';

import '../transfer/transfer_types.dart';

/// Selector de documentos del sistema (PDF, ZIP, música, lo que sea).
abstract interface class DocumentPicker {
  /// Lista vacía si el usuario cancela.
  Future<List<OutgoingFile>> pick();
}

class SystemDocumentPicker implements DocumentPicker {
  const SystemDocumentPicker();

  @override
  Future<List<OutgoingFile>> pick() async {
    final picked = await FilePicker.pickFiles(type: FileType.any);
    return [
      for (final file in picked)
        // Se lee por el URI del sistema: sirve también para archivos de la nube o de otras apps.
        OutgoingFile(name: file.name, size: await file.length() ?? 0, open: file.readAsByteStream),
    ];
  }
}
