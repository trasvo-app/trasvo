// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0.
// If a copy of the MPL was not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

import 'package:flutter/widgets.dart';

import '../../data/files/document_picker.dart';
import '../../data/media/media_library.dart';
import '../../features/connect/application/connection_controller.dart';
import '../../features/transfers/application/transfer_controller.dart';
import '../theme/theme_controller.dart';

/// Todo lo que las pantallas necesitan. Se arma una vez en `main.dart`
/// (o con dobles en los tests) y se lee con `AppScope.of(context)`.
class AppServices {
  const AppServices({
    required this.theme,
    required this.transfers,
    required this.connection,
    required this.media,
    required this.documents,
    required this.deviceName,
    required this.localIp,
  });

  final ThemeController theme;
  final TransferController transfers;
  final ConnectionController connection;
  final MediaLibrary media;
  final DocumentPicker documents;
  final String deviceName;

  /// IP del celular en el Wi-Fi (`null` sin red).
  final String? localIp;
}

class AppScope extends InheritedWidget {
  const AppScope({super.key, required this.services, required super.child});

  final AppServices services;

  static AppServices of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppScope>()!.services;

  /// Como [of], sin suscribirse (se puede usar en `initState`).
  static AppServices read(BuildContext context) =>
      context.getInheritedWidgetOfExactType<AppScope>()!.services;

  @override
  bool updateShouldNotify(AppScope oldWidget) => services != oldWidget.services;
}
