// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0.
// If a copy of the MPL was not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

import 'dart:io';
import 'dart:typed_data';

import 'package:file_transfer/data/transfer/file_names.dart';
import 'package:file_transfer/data/transfer/transfer_engine.dart';
import 'package:flutter_test/flutter_test.dart';

const code = '123456';

TransferEngine engine(String name, String code, Directory dir) => TransferEngine(EngineConfig(
      deviceId: '$name-id',
      deviceName: name,
      code: code,
      downloadDir: dir,
    ));

/// Receptor en localhost que responde a cada oferta con `decide`.
Future<(TransferEngine, int, List<TransferEvent>)> receiver(
  Directory downloads, {
  bool Function(OfferEvent offer)? decide,
  void Function(TransferEngine engine, TransferEvent event)? onEvent,
}) async {
  final e = engine('PC', code, downloads);
  final events = <TransferEvent>[];
  e.events.listen((event) {
    events.add(event);
    if (event is OfferEvent) e.respond(event.transferId, decide?.call(event) ?? true);
    onEvent?.call(e, event);
  });
  final port = await e.listen(port: 0, address: InternetAddress.loopbackIPv4);
  return (e, port, events);
}

Uint8List pseudoRandom(int length) {
  var x = 2463534242;
  return Uint8List.fromList(List.generate(length, (_) {
    x ^= (x << 13) & 0xffffffff;
    x ^= x >> 17;
    x ^= (x << 5) & 0xffffffff;
    return x & 0xff;
  }));
}

List<String> allFiles(Directory dir) =>
    dir.listSync(recursive: true).whereType<File>().map((f) => f.path).toList();

Future<T> eventually<T>(List<TransferEvent> events, T? Function(TransferEvent) pick) async {
  for (var i = 0; i < 200; i++) {
    for (final e in events) {
      final found = pick(e);
      if (found != null) return found;
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
  throw StateError('event not found');
}

void main() {
  late Directory tmp;
  late Directory downloads;
  late Directory src;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('ft_test');
    downloads = Directory('${tmp.path}/downloads')..createSync();
    src = Directory('${tmp.path}/src')..createSync();
  });

  tearDown(() => tmp.deleteSync(recursive: true));

  test('sends files and folders end to end', () async {
    final (_, port, received) = await receiver(downloads);
    final big = pseudoRandom(1024 * 1024 + 123);
    File('${src.path}/video.bin').writeAsBytesSync(big);
    File('${src.path}/vacio.txt').writeAsBytesSync([]);
    Directory('${src.path}/Album/Día 1').createSync(recursive: true);
    File('${src.path}/Album/Día 1/foto.jpg').writeAsStringSync('jpeg!');

    final sender = engine('Celular', '000000', tmp);
    final sent = <TransferEvent>[];
    sender.events.listen(sent.add);
    final files = collectPaths(['${src.path}/video.bin', '${src.path}/vacio.txt', '${src.path}/Album']);
    expect(files.map((f) => f.name), ['video.bin', 'vacio.txt', 'Album/Día 1/foto.jpg']);

    await sender.send(newTransferId(), '127.0.0.1', port, code, files);

    expect(File('${downloads.path}/video.bin').readAsBytesSync(), big);
    expect(File('${downloads.path}/vacio.txt').lengthSync(), 0);
    expect(File('${downloads.path}/Album/Día 1/foto.jpg').readAsStringSync(), 'jpeg!');
    final done = await eventually(received, (e) => e is CompletedEvent ? e : null);
    expect(done.files, hasLength(3));
    expect(sent.first, isA<WaitingEvent>().having((e) => e.peerName, 'peer', 'PC'));
    expect(sent.whereType<CompletedEvent>(), hasLength(1));
    expect(allFiles(downloads).where((p) => p.endsWith('.part')), isEmpty);
  });

  test('existing files are not overwritten', () async {
    File('${downloads.path}/nota.txt').writeAsStringSync('vieja');
    final (_, port, _) = await receiver(downloads);
    File('${src.path}/nota.txt').writeAsStringSync('nueva');

    await engine('Celular', '', tmp)
        .send(newTransferId(), '127.0.0.1', port, code, collectPaths(['${src.path}/nota.txt']));

    expect(File('${downloads.path}/nota.txt').readAsStringSync(), 'vieja');
    expect(File('${downloads.path}/nota (1).txt').readAsStringSync(), 'nueva');
  });

  test('wrong code is rejected and nothing is written', () async {
    final (_, port, _) = await receiver(downloads);
    File('${src.path}/a.txt').writeAsStringSync('a');

    await expectLater(
      engine('Celular', '', tmp)
          .send(newTransferId(), '127.0.0.1', port, '999999', collectPaths(['${src.path}/a.txt'])),
      throwsA(isA<TransferException>().having((e) => e.code, 'code', 'invalid_code')),
    );
    expect(allFiles(downloads), isEmpty);
  });

  test('declined offer is reported to the sender', () async {
    final (_, port, _) = await receiver(downloads, decide: (_) => false);
    File('${src.path}/a.txt').writeAsStringSync('a');

    await expectLater(
      engine('Celular', '', tmp)
          .send(newTransferId(), '127.0.0.1', port, code, collectPaths(['${src.path}/a.txt'])),
      throwsA(isA<TransferException>().having((e) => e.code, 'code', 'declined')),
    );
  });

  test('check pairing returns the peer name and locks after 10 wrong codes', () async {
    final (_, port, _) = await receiver(downloads);
    final client = engine('Celular', '', tmp);

    expect(await client.checkPairing('127.0.0.1', port, code), 'PC');
    for (var i = 0; i < 10; i++) {
      await expectLater(client.checkPairing('127.0.0.1', port, '000000'), throwsA(anything));
    }
    await expectLater(
      client.checkPairing('127.0.0.1', port, code),
      throwsA(isA<TransferException>().having((e) => e.code, 'code', 'locked')),
    );
  });

  test('sender can cancel mid transfer', () async {
    final (_, port, received) = await receiver(downloads);
    File('${src.path}/grande.bin').writeAsBytesSync(Uint8List(32 * 1024 * 1024));

    final sender = engine('Celular', '', tmp);
    final id = newTransferId();
    sender.events.listen((e) {
      if (e is ProgressEvent) sender.cancel(id);
    });

    await expectLater(
      sender.send(id, '127.0.0.1', port, code, collectPaths(['${src.path}/grande.bin'])),
      throwsA(isA<TransferException>().having((e) => e.code, 'code', 'cancelled')),
    );
    final failed = await eventually(received, (e) => e is FailedEvent ? e : null);
    expect(failed.reason, 'cancelled');
    expect(allFiles(downloads), isEmpty);
  });

  test('receiver can cancel mid transfer', () async {
    final (_, port, received) = await receiver(downloads, onEvent: (engine, e) {
      if (e is ProgressEvent) engine.cancel(e.transferId);
    });
    File('${src.path}/grande.bin').writeAsBytesSync(Uint8List(32 * 1024 * 1024));

    await expectLater(
      engine('Celular', '', tmp).send(
          newTransferId(), '127.0.0.1', port, code, collectPaths(['${src.path}/grande.bin'])),
      throwsA(isA<TransferException>().having((e) => e.code, 'code', 'cancelled')),
    );
    final failed = await eventually(received, (e) => e is FailedEvent ? e : null);
    expect(failed.reason, 'cancelled');
    expect(allFiles(downloads), isEmpty);
  });

  test('unreachable address fails fast', () async {
    final closed = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = closed.port;
    await closed.close();
    await expectLater(
      engine('Celular', '', tmp).checkPairing('127.0.0.1', port, code),
      throwsA(isA<TransferException>().having((e) => e.code, 'code', 'unreachable')),
    );
  });

  group('file names', () {
    test('sanitize accepts normal names and blocks escapes', () {
      expect(sanitizeName('Viaje/Día 1/video.mp4'), ['Viaje', 'Día 1', 'video.mp4']);
      for (final bad in [
        '', '../x', 'a/../b', '/etc/passwd', 'C:/x', r'a\b', 'a//b', 'con.txt', 'NUL', 'x?.jpg',
        'fin.', 'fin ', 'tab\there', //
      ]) {
        expect(() => sanitizeName(bad), throwsA(isA<TransferException>()), reason: bad);
      }
    });

    test('unique destination avoids overwrites', () {
      final sep = Platform.pathSeparator;
      expect(uniqueDestination(downloads, ['foto.jpg']), '${downloads.path}${sep}foto.jpg');
      File('${downloads.path}/foto.jpg').writeAsStringSync('x');
      expect(uniqueDestination(downloads, ['foto.jpg']), '${downloads.path}${sep}foto (1).jpg');
    });
  });
}
