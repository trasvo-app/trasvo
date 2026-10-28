// Envía archivos con el motor del celular, desde la terminal.
//
// dart run tool/send.dart <ip> <puerto> <código> <archivo o carpeta>...

import 'dart:io';

import 'package:file_transfer/data/transfer/file_names.dart';
import 'package:file_transfer/data/transfer/transfer_engine.dart';

Future<void> main(List<String> args) async {
  if (args.length < 4) {
    stderr.writeln('uso: send <ip> <puerto> <código> <archivo o carpeta>...');
    exit(2);
  }
  final [host, port, code, ...paths] = args;
  final engine = TransferEngine(EngineConfig(
    deviceId: 'dart-cli',
    deviceName: 'Celular (terminal)',
    code: '',
    downloadDir: Directory.systemTemp,
  ));
  engine.events.listen((event) {
    switch (event) {
      case WaitingEvent(:final peerName):
        stdout.writeln('Esperando que $peerName acepte…');
      case ProgressEvent(:final bytesDone, :final bytesTotal, :final currentFile):
        final pct = bytesTotal == 0 ? 100 : bytesDone * 100 ~/ bytesTotal;
        stdout.writeln('${pct.toString().padLeft(3)}%  $currentFile');
      case CompletedEvent(:final files):
        stdout.writeln('Listo: ${files.length} archivo(s)');
      case OfferEvent() || FailedEvent():
        break;
    }
  });
  try {
    await engine.send(newTransferId(), host, int.parse(port), code, collectPaths(paths));
  } on TransferException catch (e) {
    stderr.writeln('Falló: ${e.code}');
    exit(1);
  }
  exit(0);
}
