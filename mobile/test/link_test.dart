// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0.
// If a copy of the MPL was not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

import 'dart:async';
import 'dart:io';

import 'package:file_transfer/data/transfer/transfer_engine.dart';
import 'package:flutter_test/flutter_test.dart';

/// Motor en localhost que acepta todas las ofertas y responde `approve` a las
/// peticiones de conexión sin código.
class Device {
  Device._(this.engine, this.port, this.dir);

  final TransferEngine engine;
  final int port;
  final Directory dir;
  final links = <LinkState>[];
  final received = <CompletedEvent>[];

  static Future<Device> start(Directory root, String name, String code, {bool? approve}) async {
    final dir = Directory('${root.path}/$name')..createSync();
    final engine = TransferEngine(
      EngineConfig(deviceId: '$name-id', deviceName: name, code: code, downloadDir: dir),
    );
    final port = await engine.listen(port: 0, address: InternetAddress.loopbackIPv4);
    final device = Device._(engine, port, dir);
    engine.linkChanges.listen(device.links.add);
    engine.events.listen((event) {
      if (event is OfferEvent) engine.respond(event.transferId, true);
      if (event is CompletedEvent && event.direction == Direction.receive) {
        device.received.add(event);
      }
    });
    engine.linkPrompts.listen((event) {
      if (event is LinkRequested && approve != null) engine.respond(event.requestId, approve);
    });
    return device;
  }

  LinkStatus get status => engine.linkState.status;

  Future<void> until(
    bool Function() condition, {
    Duration max = const Duration(seconds: 10),
  }) async {
    final end = DateTime.now().add(max);
    while (!condition()) {
      if (DateTime.now().isAfter(end)) throw TimeoutException('condición no cumplida');
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
  }
}

OutgoingFile textFile(String name, String body) =>
    OutgoingFile(name: name, size: body.length, open: () => Stream.value(body.codeUnits));

void main() {
  late Directory tmp;
  final devices = <Device>[];

  Future<Device> device(String name, String code, {bool? approve}) async {
    final d = await Device.start(tmp, name, code, approve: approve);
    devices.add(d);
    return d;
  }

  setUp(() => tmp = Directory.systemTemp.createTempSync('ft_link'));

  tearDown(() async {
    for (final d in devices) {
      await d.engine.close();
    }
    devices.clear();
    tmp.deleteSync(recursive: true);
  });

  test('one pairing allows sending both ways many times', () async {
    final phone = await device('Celular', '111111');
    final pc = await device('PC', '222222');

    expect(await phone.engine.link('127.0.0.1', pc.port, '222222'), 'PC');
    await pc.until(() => pc.status == LinkStatus.connected);
    expect(pc.engine.linkState.peer?.name, 'Celular');

    for (var round = 0; round < 2; round++) {
      await pc.engine.sendLinked(newTransferId(), [textFile('a$round.txt', 'desde la PC')]);
      await phone.until(() => phone.received.length == round + 1);
      expect(File('${phone.dir.path}/a$round.txt').readAsStringSync(), 'desde la PC');
    }
    await phone.engine.sendLinked(newTransferId(), [textFile('b.txt', 'desde el celular')]);
    await pc.until(() => pc.received.length == 1);
    expect(File('${pc.dir.path}/b.txt').readAsStringSync(), 'desde el celular');

    expect(phone.status, LinkStatus.connected);
    expect(pc.status, LinkStatus.connected);
  });

  test('disconnecting on one side disconnects both', () async {
    final phone = await device('Celular', '111111');
    final pc = await device('PC', '222222');
    await pc.engine.link('127.0.0.1', phone.port, '111111');
    await phone.until(() => phone.status == LinkStatus.connected);

    phone.engine.unlink();
    expect(phone.status, LinkStatus.disconnected);
    await pc.until(() => pc.status == LinkStatus.disconnected);

    await expectLater(
      pc.engine.sendLinked(newTransferId(), [textFile('a.txt', 'a')]),
      throwsA(isA<TransferException>().having((e) => e.code, 'code', 'not_connected')),
    );
  });

  test('reconnects by itself after the connection drops', () async {
    final phone = await device('Celular', '111111');
    final pc = await device('PC', '222222');
    await phone.engine.link('127.0.0.1', pc.port, '222222');
    await pc.until(() => pc.status == LinkStatus.connected);

    phone.engine.debugDropLinkConnection();
    await phone.until(() => phone.links.any((l) => l.status == LinkStatus.reconnecting));
    await phone.until(() => phone.links.last.status == LinkStatus.connected);
    await pc.until(() => pc.links.last.status == LinkStatus.connected);

    await pc.engine.sendLinked(newTransferId(), [textFile('a.txt', 'otra vez')]);
    await phone.until(() => phone.received.length == 1);
  });

  test('old link token stops working and does not lock the code', () async {
    final phone = await device('Celular', '111111');
    final pc = await device('PC', '222222');
    await phone.engine.link('127.0.0.1', pc.port, '222222');
    await pc.until(() => pc.status == LinkStatus.connected);
    pc.engine.unlink();
    await phone.until(() => phone.status == LinkStatus.disconnected);

    for (var i = 0; i < 12; i++) {
      await expectLater(
        phone.engine.send(newTransferId(), '127.0.0.1', pc.port, '0' * 32, [
          textFile('a.txt', 'a'),
        ]),
        throwsA(isA<TransferException>().having((e) => e.code, 'code', 'invalid_code')),
      );
    }
    expect(await phone.engine.checkPairing('127.0.0.1', pc.port, '222222'), 'PC');
  });

  test('nearby device connects only if the other user accepts', () async {
    final yes = await device('Acepta', '111111', approve: true);
    final no = await device('Rechaza', '333333', approve: false);
    final pc = await device('PC', '222222');

    expect(await pc.engine.linkNearby('127.0.0.1', yes.port), 'Acepta');
    await yes.until(() => yes.status == LinkStatus.connected);

    await expectLater(
      pc.engine.linkNearby('127.0.0.1', no.port),
      throwsA(isA<TransferException>().having((e) => e.code, 'code', 'declined')),
    );
    expect(no.status, LinkStatus.disconnected);
  });

  test('a new link replaces the previous one', () async {
    final pc = await device('PC', '222222');
    final phone1 = await device('Celular 1', '111111');
    final phone2 = await device('Celular 2', '333333');

    await phone1.engine.link('127.0.0.1', pc.port, '222222');
    await pc.until(() => pc.status == LinkStatus.connected);
    await phone2.engine.link('127.0.0.1', pc.port, '222222');

    await pc.until(() => pc.engine.linkState.peer?.name == 'Celular 2');
    await phone1.until(() => phone1.status == LinkStatus.disconnected);
  });
}
