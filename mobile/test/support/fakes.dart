// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0.
// If a copy of the MPL was not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_transfer/core/di/app_scope.dart';
import 'package:file_transfer/core/theme/theme_controller.dart';
import 'package:file_transfer/data/discovery/nearby_service.dart';
import 'package:file_transfer/data/files/document_picker.dart';
import 'package:file_transfer/data/media/media_library.dart';
import 'package:file_transfer/data/platform/device_storage.dart';
import 'package:file_transfer/data/settings/settings_repository.dart';
import 'package:file_transfer/data/transfer/transfer_engine.dart';
import 'package:file_transfer/features/connect/application/connection_controller.dart';
import 'package:file_transfer/features/transfers/application/transfer_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// PNG de 1×1 para las miniaturas falsas.
final onePixelPng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==',
);

class FakeMediaLibrary implements MediaLibrary {
  FakeMediaLibrary({this.access = MediaAccess.full, this.photos = 6});

  MediaAccess access;
  final int photos;
  int requests = 0;

  @override
  Future<MediaAccess> currentAccess() async => access;

  @override
  Future<MediaAccess> requestAccess() async {
    requests++;
    if (access == MediaAccess.notAsked) access = MediaAccess.full;
    return access;
  }

  @override
  Future<void> chooseMore() async {}

  @override
  Future<void> openSettings() async {}

  @override
  Future<List<MediaItem>> list(MediaKind kind, {required int page, int pageSize = 90}) async {
    if (page > 0 || kind == MediaKind.video) return [];
    return [
      for (var i = 0; i < photos; i++)
        MediaItem(id: 'p$i', kind: kind, created: DateTime(2026, 10, 1 + i)),
    ];
  }

  @override
  Future<Uint8List?> thumbnail(MediaItem item) async => onePixelPng;

  @override
  Future<OutgoingFile> toOutgoing(MediaItem item) async =>
      OutgoingFile(name: 'IMG_${item.id}.jpg', size: 3, open: () => Stream.value([1, 2, 3]));
}

class FakeDocumentPicker implements DocumentPicker {
  @override
  Future<List<OutgoingFile>> pick() async => [
    OutgoingFile(name: 'informe.pdf', size: 2048, open: () => Stream.value(List.filled(2048, 0))),
  ];
}

class FakeDeviceStorage implements DeviceStorage {
  final saved = <String>[];

  @override
  Future<String> deviceName() async => 'Celular de prueba';

  @override
  Future<String> saveToDownloads(String path, {String subfolder = ''}) async {
    final shown =
        'Download/Trasvo/${subfolder.isEmpty ? '' : '$subfolder/'}'
        '${path.split(Platform.pathSeparator).last}';
    saved.add(shown);
    return shown;
  }
}

class FakeNearbyService implements NearbyService {
  FakeNearbyService([this.devices = const []]);

  final List<NearbyDevice> devices;
  bool browsing = false;

  @override
  Future<void> advertise({required String id, required String name, required int port}) async {}

  @override
  Future<void> startBrowsing(void Function(List<NearbyDevice> devices) onChange) async {
    browsing = true;
    onChange(devices);
  }

  @override
  Future<void> stopBrowsing() async => browsing = false;
}

/// Servicios completos con dobles. El motor es real pero no abre ningún puerto
/// (salvo que se llame a `transfers.start()`).
Future<AppServices> fakeServices({
  Map<String, Object> prefs = const {'theme': 'light'},
  FakeMediaLibrary? media,
  FakeNearbyService? nearby,
}) async {
  SharedPreferences.setMockInitialValues(prefs);
  final sp = await SharedPreferences.getInstance();
  final engine = TransferEngine(
    EngineConfig(
      deviceId: 'test',
      deviceName: 'Celular de prueba',
      code: '424242',
      downloadDir: Directory.systemTemp,
    ),
  );
  return AppServices(
    theme: ThemeController(SettingsRepository(sp)),
    transfers: TransferController(engine: engine, storage: FakeDeviceStorage(), prefs: sp),
    connection: ConnectionController(engine, nearby: nearby ?? FakeNearbyService()),
    media: media ?? FakeMediaLibrary(),
    documents: FakeDocumentPicker(),
    deviceName: 'Celular de prueba',
    localIp: '192.168.1.50',
  );
}
