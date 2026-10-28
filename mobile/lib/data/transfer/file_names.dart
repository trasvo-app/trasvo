// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0.
// If a copy of the MPL was not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

import 'dart:io';

import 'transfer_types.dart';

/// Nombres de archivo: qué se ofrece al enviar y dónde se guarda al recibir.
/// Mismas reglas que `ft_transfer::files` en Rust.

const _reserved = {
  'CON', 'PRN', 'AUX', 'NUL', //
  'COM1', 'COM2', 'COM3', 'COM4', 'COM5', 'COM6', 'COM7', 'COM8', 'COM9',
  'LPT1', 'LPT2', 'LPT3', 'LPT4', 'LPT5', 'LPT6', 'LPT7', 'LPT8', 'LPT9',
};
final _badChar = RegExp(r'[<>:"\\|?*\x00-\x1f\x7f]');

/// Convierte el nombre que manda el otro lado en componentes de ruta seguros.
/// Rechaza rutas absolutas, `..`, `\`, caracteres prohibidos y nombres reservados.
List<String> sanitizeName(String name) {
  if (name.isEmpty || name.length > 1024) throw TransferException('invalid_name', name);
  final parts = name.split('/');
  for (final part in parts) {
    final stem = part.split('.').first.toUpperCase();
    if (part.isEmpty ||
        part == '.' ||
        part == '..' ||
        part.endsWith('.') ||
        part.endsWith(' ') ||
        _badChar.hasMatch(part) ||
        _reserved.contains(stem)) {
      throw TransferException('invalid_name', name);
    }
  }
  return parts;
}

String partPath(String dest) => '$dest.part';

/// Ruta libre dentro de `dir`: si ya existe, agrega " (1)", " (2)"… antes de la extensión.
String uniqueDestination(Directory dir, List<String> parts) {
  final sep = Platform.pathSeparator;
  final first = [dir.path, ...parts].join(sep);
  bool taken(String p) => File(p).existsSync() || File(partPath(p)).existsSync();
  if (!taken(first)) return first;

  final parent = [dir.path, ...parts.sublist(0, parts.length - 1)].join(sep);
  final last = parts.last;
  final dot = last.lastIndexOf('.');
  final stem = dot > 0 ? last.substring(0, dot) : last;
  final ext = dot > 0 ? last.substring(dot) : '';
  for (var n = 1;; n++) {
    final candidate = '$parent$sep$stem ($n)$ext';
    if (!taken(candidate)) return candidate;
  }
}

/// Expande carpetas (recursivo, ordenado) en la lista plana de archivos a enviar.
List<OutgoingFile> collectPaths(List<String> paths) {
  final out = <OutgoingFile>[];
  void walk(Directory dir, String prefix) {
    final entries = dir.listSync(followLinks: false)
      ..sort((a, b) => a.path.compareTo(b.path));
    for (final entry in entries) {
      final name = '$prefix/${entry.uri.pathSegments.where((s) => s.isNotEmpty).last}';
      if (entry is Directory) {
        walk(entry, name);
      } else if (entry is File) {
        out.add(OutgoingFile.fromFile(entry, name: name));
      }
      // Los enlaces simbólicos se omiten a propósito.
    }
  }

  for (final path in paths) {
    final type = FileSystemEntity.typeSync(path, followLinks: false);
    final base = Uri.file(path).pathSegments.where((s) => s.isNotEmpty).last;
    switch (type) {
      case FileSystemEntityType.directory:
        walk(Directory(path), base);
      case FileSystemEntityType.file:
        out.add(OutgoingFile.fromFile(File(path), name: base));
      default:
        throw TransferException('io', 'No existe: $path');
    }
  }
  return out;
}
