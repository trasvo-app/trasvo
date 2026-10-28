// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0.
// If a copy of the MPL was not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

import 'dart:typed_data';

import 'package:photo_manager/photo_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../transfer/transfer_types.dart';

enum MediaKind { photo, video }

enum MediaAccess {
  /// Acceso a toda la galería.
  full,

  /// Android 14+: el usuario eligió solo algunas fotos.
  limited,
  denied,

  /// Todavía no se preguntó: primero se muestra la explicación.
  notAsked,
}

class MediaItem {
  const MediaItem({
    required this.id,
    required this.kind,
    required this.created,
    this.duration = Duration.zero,
    this.handle,
  });

  final String id;
  final MediaKind kind;
  final DateTime created;
  final Duration duration;

  /// Objeto de la implementación (p. ej. `AssetEntity`).
  final Object? handle;
}

/// Galería del teléfono. Interfaz propia para poder probar las pantallas sin Android.
abstract interface class MediaLibrary {
  /// Estado actual del permiso, sin mostrar ningún diálogo.
  Future<MediaAccess> currentAccess();

  /// Muestra el diálogo del sistema (si hace falta) y devuelve el resultado.
  Future<MediaAccess> requestAccess();

  /// Permite elegir más fotos cuando el acceso es parcial.
  Future<void> chooseMore();

  Future<void> openSettings();

  /// Elementos más recientes primero, de a páginas.
  Future<List<MediaItem>> list(MediaKind kind, {required int page, int pageSize = 90});

  Future<Uint8List?> thumbnail(MediaItem item);

  /// Archivo listo para enviar (con su nombre real y tamaño).
  Future<OutgoingFile> toOutgoing(MediaItem item);
}

class PhotoManagerLibrary implements MediaLibrary {
  const PhotoManagerLibrary(this._prefs);

  static const _askedKey = 'media_permission_asked';

  final SharedPreferences _prefs;

  @override
  Future<MediaAccess> currentAccess() async {
    final access = _map(
      await PhotoManager.getPermissionState(requestOption: const PermissionRequestOption()),
    );
    // Android no distingue «nunca se preguntó» de «rechazado»: lo recordamos nosotros.
    final asked = _prefs.getBool(_askedKey) ?? false;
    return access == MediaAccess.denied && !asked ? MediaAccess.notAsked : access;
  }

  @override
  Future<MediaAccess> requestAccess() async {
    await _prefs.setBool(_askedKey, true);
    final access = _map(await PhotoManager.requestPermissionExtend());
    return access == MediaAccess.notAsked ? MediaAccess.denied : access;
  }

  static MediaAccess _map(PermissionState state) => switch (state) {
        PermissionState.authorized => MediaAccess.full,
        PermissionState.limited => MediaAccess.limited,
        PermissionState.notDetermined => MediaAccess.notAsked,
        _ => MediaAccess.denied,
      };

  @override
  Future<void> chooseMore() => PhotoManager.presentLimited();

  @override
  Future<void> openSettings() => PhotoManager.openSetting();

  @override
  Future<List<MediaItem>> list(MediaKind kind, {required int page, int pageSize = 90}) async {
    final type = kind == MediaKind.photo ? RequestType.image : RequestType.video;
    final albums = await PhotoManager.getAssetPathList(type: type, onlyAll: true);
    if (albums.isEmpty) return [];
    final assets = await albums.first.getAssetListPaged(page: page, size: pageSize);
    return [
      for (final asset in assets)
        MediaItem(
          id: asset.id,
          kind: kind,
          created: asset.createDateTime,
          duration: Duration(seconds: asset.duration),
          handle: asset,
        ),
    ];
  }

  @override
  Future<Uint8List?> thumbnail(MediaItem item) =>
      (item.handle! as AssetEntity).thumbnailDataWithSize(const ThumbnailSize.square(240));

  @override
  Future<OutgoingFile> toOutgoing(MediaItem item) async {
    final asset = item.handle! as AssetEntity;
    final file = await asset.originFile;
    if (file == null) throw const TransferException('io', 'No se pudo leer el archivo');
    final title = await asset.titleAsync;
    return OutgoingFile(
      name: title.isNotEmpty ? title : file.uri.pathSegments.last,
      size: await file.length(),
      open: file.openRead,
    );
  }
}
