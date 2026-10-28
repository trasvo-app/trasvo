// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0.
// If a copy of the MPL was not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

const _units = ['B', 'KB', 'MB', 'GB', 'TB'];

/// 1536 → "1,5 KB". Igual que `desktop/src/shared/format.ts`.
String formatBytes(int bytes) {
  var value = bytes < 0 ? 0.0 : bytes.toDouble();
  var unit = 0;
  while (value >= 1024 && unit < _units.length - 1) {
    value /= 1024;
    unit++;
  }
  final text = unit == 0 ? value.round().toString() : value.toStringAsFixed(1).replaceAll('.', ',');
  return '$text ${_units[unit]}';
}

String plural(int count, String one, String many) => '$count ${count == 1 ? one : many}';

String formatDuration(Duration d) {
  final minutes = d.inMinutes;
  final seconds = (d.inSeconds % 60).toString().padLeft(2, '0');
  return '$minutes:$seconds';
}

/// Texto para cada código de error del motor (los mismos que en la PC).
String reasonText(String? code) => switch (code) {
  'declined' => 'La PC lo rechazó.',
  'invalid_code' => 'El código no es correcto.',
  'invalid_ip' => 'Revisa la IP: debe verse como 192.168.1.20.',
  'invalid_qr' => 'Ese QR no es de Trasvo. Escanea el de la app de la PC.',
  'unreachable' =>
    'No encontramos la PC. Revisa que la app esté abierta y que ambos estén en el mismo Wi-Fi.',
  'locked' => 'Demasiados intentos con código incorrecto. Reinicia la app de la PC.',
  'version_mismatch' => 'Las apps tienen versiones distintas. Actualiza ambas.',
  'timeout' => 'La PC no respondió a tiempo.',
  'hash_mismatch' => 'Un archivo llegó dañado. Vuelve a intentarlo.',
  'cancelled' => 'Se canceló la transferencia.',
  'invalid_name' => 'Uno de los archivos tiene un nombre no válido.',
  'empty' => 'No hay archivos para enviar.',
  'io' => 'No se pudo leer o guardar un archivo.',
  'protocol' => 'Se cortó la comunicación con la PC.',
  'not_connected' => 'No hay ninguna PC conectada. Conéctate primero.',
  _ => 'Algo salió mal. Vuelve a intentarlo.',
};
