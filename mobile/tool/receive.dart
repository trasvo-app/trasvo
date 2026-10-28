// Recibe archivos con el motor del celular, desde la terminal (acepta todo).
// Sirve para probar que la PC (Rust) y el celular (Dart) se entienden.
//
// dart run tool/receive.dart <carpeta destino> [código] [puerto]

import 'dart:io';

import 'package:file_transfer/data/transfer/transfer_engine.dart';

Future<void> main(List<String> args) async {
  if (args.isEmpty) {
    stderr.writeln('uso: receive <carpeta destino> [código] [puerto]');
    exit(2);
  }
  final dir = Directory(args[0])..createSync(recursive: true);
  final code = args.length > 1 ? args[1] : '123456';
  final port = args.length > 2 ? int.parse(args[2]) : 47521;

  final engine = TransferEngine(EngineConfig(
    deviceId: 'dart-cli',
    deviceName: 'Celular (terminal)',
    code: code,
    downloadDir: dir,
  ));
  engine.events.listen((event) {
    switch (event) {
      case OfferEvent(:final peerName, :final files):
        stdout.writeln('Oferta de $peerName: ${files.length} archivo(s). Aceptando.');
        engine.respond(event.transferId, true);
      case CompletedEvent(:final files):
        stdout.writeln('Recibido: ${files.join(', ')}');
      case FailedEvent(:final reason):
        stdout.writeln('Falló: $reason');
      case ProgressEvent() || WaitingEvent():
        break;
    }
  });
  final actual = await engine.listen(port: port);
  stdout.writeln('Escuchando en el puerto $actual con código $code');
}
