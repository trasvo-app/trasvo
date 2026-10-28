// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0.
// If a copy of the MPL was not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

import 'dart:io';

import 'package:file_transfer/app.dart';
import 'package:file_transfer/core/di/app_scope.dart';
import 'package:file_transfer/data/discovery/nearby_service.dart';
import 'package:file_transfer/data/media/media_library.dart';
import 'package:file_transfer/data/transfer/transfer_engine.dart';
import 'package:file_transfer/domain/protocol/message.dart';
import 'package:file_transfer/features/connect/presentation/connect_page.dart';
import 'package:file_transfer/features/transfers/application/transfer_item.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fakes.dart';

void main() {
  group('theme', () {
    testWidgets('first launch asks for a theme and remembers it', (tester) async {
      final services = await fakeServices(prefs: {});
      await pumpApp(tester, services);

      expect(find.text('¡Bienvenido!'), findsOneWidget);
      await tester.tap(find.text('Oscuro'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Continuar'));
      await tester.pumpAndSettle();

      expect(find.text('Enviar fotos y archivos'), findsOneWidget);
      expect(services.theme.mode, ThemeMode.dark);
      expect((await SharedPreferences.getInstance()).getString('theme'), 'dark');
    });

    testWidgets('home toggle switches the theme', (tester) async {
      final services = await fakeServices();
      await pumpApp(tester, services);

      await tester.tap(find.byTooltip('Usar tema oscuro'));
      await tester.pumpAndSettle();
      expect(services.theme.mode, ThemeMode.dark);
    });
  });

  group('home', () {
    testWidgets('shows how to connect and what the PC must type to send here', (tester) async {
      final services = await fakeServices();
      await pumpApp(tester, services);

      expect(find.text('Conecta con tu PC'), findsOneWidget);
      expect(find.text('Escanear QR'), findsOneWidget);
      expect(find.text('424242'), findsOneWidget);
      // Sin `start()` no hay puerto todavía.
      expect(find.text('192.168.1.50:…'), findsOneWidget);
      expect(find.text('Lo que envíes o recibas aparecerá aquí.'), findsOneWidget);
    });

    testWidgets('incoming offer opens a dialog anywhere and can be accepted', (tester) async {
      final services = await fakeServices();
      await pumpApp(tester, services);

      services.transfers.handleEvent(
        const OfferEvent(
          't1',
          peerName: 'DESKTOP-PC',
          files: [
            FileInfo(name: 'informe.pdf', size: 2048),
            FileInfo(name: 'Fotos/playa.jpg', size: 1024),
          ],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('DESKTOP-PC quiere enviarte archivos'), findsOneWidget);
      expect(find.text('2 archivos · 3,0 KB'), findsOneWidget);
      expect(find.text('Fotos/playa.jpg'), findsOneWidget);

      await tester.tap(find.text('Aceptar'));
      await tester.pumpAndSettle();
      expect(find.text('DESKTOP-PC quiere enviarte archivos'), findsNothing);
      expect(services.transfers.items.single.status, TransferStatus.active);
      expect(find.text('Recibiendo de DESKTOP-PC'), findsOneWidget);
    });

    testWidgets('received files are moved to Downloads and shown as done', (tester) async {
      final services = await fakeServices();
      await pumpApp(tester, services);

      services.transfers.handleEvent(
        const OfferEvent(
          't1',
          peerName: 'PC',
          files: [FileInfo(name: 'a.txt', size: 1)],
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Aceptar'));
      await tester.pumpAndSettle();

      services.transfers.handleEvent(
        CompletedEvent('t1', direction: Direction.receive, files: ['${_tmp()}a.txt']),
      );
      await tester.pumpAndSettle();

      final item = services.transfers.items.single;
      expect(item.status, TransferStatus.done);
      expect(item.files.single, 'Download/Trasvo/a.txt');
      expect(find.text('Guardado en Descargas/Trasvo'), findsOneWidget);
    });
  });

  group('connect', () {
    /// PC de mentira: un motor real escuchando en localhost.
    Future<(TransferEngine, int)> fakePc(WidgetTester tester) async {
      final pc = TransferEngine(
        EngineConfig(
          deviceId: 'pc',
          deviceName: 'DESKTOP-PC',
          code: '111111',
          downloadDir: Directory.systemTemp,
        ),
      );
      final port = await tester.runAsync(
        () => pc.listen(port: 0, address: InternetAddress.loopbackIPv4),
      );
      addTearDown(() => tester.runAsync(pc.close));
      return (pc, port!);
    }

    testWidgets('stays connected until «Desconectar», which disconnects both', (tester) async {
      final services = await fakeServices();
      final (pc, port) = await fakePc(tester);
      await pumpApp(tester, services);
      expect(find.text('Conecta con tu PC'), findsOneWidget);

      final ok = await tester.runAsync(
        () => services.connection.connect('127.0.0.1', port, '111111'),
      );
      await tester.pumpAndSettle();

      expect(ok, isTrue);
      expect(find.text('Conectado con DESKTOP-PC'), findsOneWidget);
      expect(find.text('Pueden enviarse archivos en ambos sentidos'), findsOneWidget);
      // Ya enlazados, no hace falta mostrar IP y código para la PC.
      expect(find.text('O conéctate desde la PC'), findsNothing);

      await tester.tap(find.text('Desconectar'));
      await tester.pumpAndSettle();
      expect(find.text('Conecta con tu PC'), findsOneWidget);
      await tester.runAsync(() async {
        for (var i = 0; i < 100 && pc.linkState.peer != null; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }
      });
      expect(pc.linkState.status, LinkStatus.disconnected);
    });

    testWidgets('a nearby PC asks to connect and the phone accepts', (tester) async {
      final services = await fakeServices();
      final (pc, _) = await fakePc(tester);
      await tester.runAsync(services.transfers.start);
      await pumpApp(tester, services);

      // La PC toca este celular en «Cerca»: el celular pregunta.
      // En un registro, para que `runAsync` no espere a que termine de conectar.
      final linking = await tester.runAsync(() async {
        final future = pc.linkNearby('127.0.0.1', services.transfers.port!);
        for (var i = 0; i < 100 && services.connection.request == null; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }
        return (future,);
      });
      await tester.pumpAndSettle();
      expect(find.text('DESKTOP-PC quiere conectarse'), findsOneWidget);

      await tester.tap(find.text('Aceptar'));
      await tester.pumpAndSettle();
      expect(await tester.runAsync(() => linking!.$1), 'Celular de prueba');
      // El celular termina de instalar el enlace por la red real.
      final connected = find.text('Conectado con DESKTOP-PC');
      for (var i = 0; i < 50 && connected.evaluate().isEmpty; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
        await tester.pump();
      }

      expect(find.text('DESKTOP-PC quiere conectarse'), findsNothing);
      expect(find.text('Conectado con DESKTOP-PC'), findsOneWidget);
      await tester.runAsync(() async => services.connection.disconnect());
    });

    testWidgets('«Buscar mi PC» lists PCs found on the Wi-Fi', (tester) async {
      final nearby = FakeNearbyService(const [
        NearbyDevice(id: 'pc', name: 'DESKTOP-PC', host: '192.168.1.20', port: 47520),
      ]);
      final services = await fakeServices(nearby: nearby);
      await pumpApp(tester, services);

      // El indicador de «buscando» gira siempre: `pumpAndSettle` no terminaría.
      await tester.tap(find.text('Buscar mi PC'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(nearby.browsing, isTrue);
      expect(find.text('DESKTOP-PC'), findsOneWidget);
      expect(find.text('192.168.1.20'), findsOneWidget);

      await tester.pageBack();
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(nearby.browsing, isFalse);
    });

    testWidgets('IP form validates before connecting', (tester) async {
      final services = await fakeServices();
      await pumpApp(tester, services);
      await tester.tap(find.text('Escribir IP'));
      await tester.pumpAndSettle();

      expect(find.byType(ConnectPage), findsOneWidget);
      await tester.enterText(find.byKey(const Key('ip')), '192.168.1');
      await tester.enterText(find.byKey(const Key('code')), '1234');
      await tester.tap(find.widgetWithText(FilledButton, 'Conectar'));
      await tester.pumpAndSettle();
      expect(find.text('Revisa la IP: debe verse como 192.168.1.20.'), findsOneWidget);

      await tester.enterText(find.byKey(const Key('ip')), '192.168.1.20');
      await tester.pumpAndSettle();
      expect(find.text('El código debe tener 6 números.'), findsOneWidget);
    });
  });

  group('send', () {
    testWidgets('explains before asking for gallery access', (tester) async {
      final media = FakeMediaLibrary(access: MediaAccess.notAsked);
      final services = await fakeServices(media: media);
      await pumpApp(tester, services);
      await tester.tap(find.text('Enviar fotos y archivos'));
      await tester.pumpAndSettle();

      expect(find.text('Para mostrarte tus fotos necesitamos acceso'), findsOneWidget);
      expect(media.requests, 0);

      await tester.tap(find.text('Permitir acceso'));
      await tester.pumpAndSettle();
      expect(media.requests, 1);
      expect(find.byType(Image), findsNWidgets(6));
    });

    testWidgets('selecting thumbnails and documents updates the send button', (tester) async {
      final services = await fakeServices();
      await pumpApp(tester, services);
      await tester.tap(find.text('Enviar fotos y archivos'));
      await tester.pumpAndSettle();

      expect(find.byType(Image), findsNWidgets(6));
      expect(find.widgetWithText(FilledButton, 'Enviar'), findsOneWidget);

      await tester.tap(find.byType(Image).at(0));
      await tester.tap(find.byType(Image).at(2));
      await tester.pumpAndSettle();
      expect(find.text('Enviar 2 elementos'), findsOneWidget);
      expect(find.textContaining('conecta tu PC para enviar'), findsOneWidget);

      await tester.tap(find.text('Archivos'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Elegir documentos'));
      await tester.pumpAndSettle();
      expect(find.text('informe.pdf'), findsOneWidget);
      expect(find.text('Enviar 3 elementos'), findsOneWidget);

      await tester.tap(find.text('Quitar todo'));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(FilledButton, 'Enviar'), findsOneWidget);
    });
  });
}

/// Celular alto (360×1000) para que todo el inicio quede visible sin desplazar.
Future<void> pumpApp(WidgetTester tester, AppServices services) async {
  tester.view.physicalSize = const Size(1080, 3000);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(App(services: services));
}

String _tmp() {
  final dir = Directory.systemTemp.path;
  return dir.endsWith(Platform.pathSeparator) ? dir : '$dir${Platform.pathSeparator}';
}
