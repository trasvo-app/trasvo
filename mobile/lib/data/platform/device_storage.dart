// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0.
// If a copy of the MPL was not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

import 'package:flutter/services.dart';

/// Acceso a lo que solo Android sabe hacer: guardar en Descargas y el nombre del equipo.
abstract interface class DeviceStorage {
  /// Mueve `path` a Descargas/Trasvo/`subfolder`. Devuelve la ruta visible.
  Future<String> saveToDownloads(String path, {String subfolder = ''});

  Future<String> deviceName();
}

/// Implementación real (ver `MainActivity.kt` y `DownloadsSaver.kt`).
class MethodChannelDeviceStorage implements DeviceStorage {
  const MethodChannelDeviceStorage();

  static const _channel = MethodChannel('com.filetransfer/storage');

  @override
  Future<String> saveToDownloads(String path, {String subfolder = ''}) async {
    final saved = await _channel.invokeMethod<String>(
      'saveToDownloads',
      {'path': path, 'subfolder': subfolder},
    );
    return saved ?? path;
  }

  @override
  Future<String> deviceName() async {
    try {
      return await _channel.invokeMethod<String>('deviceName') ?? 'Celular';
    } on MissingPluginException {
      return 'Celular';
    }
  }
}
