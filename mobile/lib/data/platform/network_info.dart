// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0.
// If a copy of the MPL was not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

import 'dart:io';

/// IP del celular en la red local. Prefiere la interfaz Wi-Fi (`wlan`).
Future<String?> localIpv4() async {
  try {
    final interfaces = await NetworkInterface.list(type: InternetAddressType.IPv4);
    interfaces.sort((a, b) => _rank(a.name).compareTo(_rank(b.name)));
    for (final interface in interfaces) {
      for (final address in interface.addresses) {
        if (!address.isLoopback && !address.isLinkLocal) return address.address;
      }
    }
  } on SocketException {
    // Sin red.
  }
  return null;
}

int _rank(String name) {
  final n = name.toLowerCase();
  if (n.startsWith('wlan') || n.contains('wi-fi') || n.contains('wifi')) return 0;
  if (n.startsWith('eth') || n.startsWith('rndis') || n.startsWith('usb')) return 1;
  return 2;
}
