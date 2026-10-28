// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0.
// If a copy of the MPL was not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

import 'message.dart';

/// Datos del QR de la PC: `ftransfer://pair?ip=…&port=…&code=…&name=…`
/// (lo genera `desktop/src/features/connect/pairingUri.ts`).
class PairingInfo {
  const PairingInfo({
    required this.host,
    required this.port,
    required this.code,
    required this.name,
  });

  final String host;
  final int port;
  final String code;
  final String name;

  /// `null` si el texto no es un QR de esta app.
  static PairingInfo? tryParse(String raw) {
    final uri = Uri.tryParse(raw.trim());
    if (uri == null || uri.scheme != 'ftransfer' || uri.host != 'pair') return null;
    final q = uri.queryParameters;
    final host = q['ip'];
    final code = q['code'];
    final port = int.tryParse(q['port'] ?? '') ?? defaultPort;
    if (host == null || !isValidIpv4(host) || code == null || !isValidCode(code)) return null;
    if (port < 1 || port > 65535) return null;
    return PairingInfo(host: host, port: port, code: code, name: q['name'] ?? 'PC');
  }
}

bool isValidIpv4(String value) {
  final parts = value.trim().split('.');
  return parts.length == 4 &&
      parts.every((p) => RegExp(r'^\d{1,3}$').hasMatch(p) && int.parse(p) <= 255);
}

bool isValidCode(String value) => RegExp(r'^\d{6}$').hasMatch(value);

bool isValidPort(String value) {
  final port = int.tryParse(value);
  return port != null && port >= 1 && port <= 65535 && RegExp(r'^\d+$').hasMatch(value);
}
