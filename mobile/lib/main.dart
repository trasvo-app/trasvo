// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0.
// If a copy of the MPL was not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'core/di/app_scope.dart';
import 'core/theme/theme_controller.dart';
import 'data/discovery/nearby_service.dart';
import 'data/files/document_picker.dart';
import 'data/media/media_library.dart';
import 'data/platform/device_storage.dart';
import 'data/platform/network_info.dart';
import 'data/settings/settings_repository.dart';
import 'data/transfer/transfer_engine.dart';
import 'features/connect/application/connection_controller.dart';
import 'features/transfers/application/transfer_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  const storage = MethodChannelDeviceStorage();
  final deviceName = await storage.deviceName();

  // Lo recibido llega primero a la caché y después se mueve a Descargas.
  final cache = await getTemporaryDirectory();
  final incoming = Directory('${cache.path}${Platform.pathSeparator}incoming')
    ..createSync(recursive: true);

  // Fijo entre inicios, para que la PC no vea un dispositivo nuevo cada vez.
  final deviceId = prefs.getString('device_id') ?? newTransferId();
  await prefs.setString('device_id', deviceId);
  final engine = TransferEngine(
    EngineConfig(
      deviceId: deviceId,
      deviceName: deviceName,
      code: _pairingCode(),
      downloadDir: incoming,
    ),
  );
  final transfers = TransferController(engine: engine, storage: storage, prefs: prefs);
  await transfers.start();

  // Anunciarse en el Wi-Fi para que la PC nos encuentre en «Cerca».
  final localIp = await localIpv4();
  final nearby = NsdNearbyService(ownId: deviceId, localIp: localIp);
  final port = transfers.port;
  if (port != null) {
    unawaited(
      nearby.advertise(id: deviceId, name: deviceName, port: port).catchError((Object _) {}),
    );
  }

  runApp(
    App(
      services: AppServices(
        theme: ThemeController(SettingsRepository(prefs)),
        transfers: transfers,
        connection: ConnectionController(engine, nearby: nearby),
        media: PhotoManagerLibrary(prefs),
        documents: const SystemDocumentPicker(),
        deviceName: deviceName,
        localIp: localIp,
      ),
    ),
  );
}

/// Código de 6 dígitos que la PC debe escribir para enviarnos archivos (nuevo en cada inicio).
String _pairingCode() => Random.secure().nextInt(1000000).toString().padLeft(6, '0');
