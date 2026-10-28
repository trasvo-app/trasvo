// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0.
// If a copy of the MPL was not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:nsd/nsd.dart' as nsd;

/// Tipo de servicio que anuncian la PC y el celular (igual que `ft_discovery` en Rust).
const serviceType = '_ftransfer._tcp';

/// Otro dispositivo con la app, encontrado en el mismo Wi-Fi.
class NearbyDevice {
  const NearbyDevice({
    required this.id,
    required this.name,
    required this.host,
    required this.port,
  });

  final String id;
  final String name;
  final String host;
  final int port;
}

/// Búsqueda automática en el Wi-Fi (mDNS / DNS-SD). Interfaz propia para probar las
/// pantallas sin red. Encontrar un dispositivo no da acceso: hay que emparejar igual.
abstract interface class NearbyService {
  /// Anuncia este dispositivo para que la PC lo encuentre.
  Future<void> advertise({required String id, required String name, required int port});

  /// Busca a los demás; `onChange` recibe la lista completa cada vez que cambia.
  Future<void> startBrowsing(void Function(List<NearbyDevice> devices) onChange);

  Future<void> stopBrowsing();
}

class NsdNearbyService implements NearbyService {
  NsdNearbyService({required this.ownId, this.localIp});

  final String ownId;

  /// Nuestra IP, para elegir la del otro que esté en la misma red.
  final String? localIp;
  nsd.Discovery? _discovery;
  nsd.Registration? _registration;

  @override
  Future<void> advertise({required String id, required String name, required int port}) async {
    if (_registration != null) return;
    _registration = await nsd.register(
      nsd.Service(
        name: id,
        type: serviceType,
        port: port,
        txt: {'id': _bytes(id), 'name': _bytes(name), 'v': _bytes('1')},
      ),
    );
  }

  @override
  Future<void> startBrowsing(void Function(List<NearbyDevice> devices) onChange) async {
    await stopBrowsing();
    final discovery = await nsd.startDiscovery(serviceType, ipLookupType: nsd.IpLookupType.v4);
    _discovery = discovery;
    void notify() => onChange(_devices(discovery.services));
    discovery.addListener(notify);
    notify();
  }

  @override
  Future<void> stopBrowsing() async {
    final discovery = _discovery;
    _discovery = null;
    if (discovery != null) await nsd.stopDiscovery(discovery);
  }

  List<NearbyDevice> _devices(List<nsd.Service> services) {
    final found = <String, NearbyDevice>{};
    for (final service in services) {
      final id = _text(service.txt?['id']) ?? service.name ?? '';
      final host = pickAddress(service.addresses ?? const [], localIp);
      final port = service.port;
      if (id.isEmpty || id == ownId || host == null || port == null) continue;
      // Un anuncio viejo de la misma app (cerrada sin despedirse) queda un rato en la
      // red: uno por IP y puerto.
      found['$host:$port'] = NearbyDevice(
        id: id,
        name: _text(service.txt?['name']) ?? id,
        host: host,
        port: port,
      );
    }
    return found.values.toList()..sort((a, b) => a.name.compareTo(b.name));
  }
}

Uint8List _bytes(String text) => Uint8List.fromList(utf8.encode(text));

String? _text(Uint8List? bytes) =>
    bytes == null || bytes.isEmpty ? null : utf8.decode(bytes, allowMalformed: true);

/// Si el otro anuncia varias IPs, la de nuestra misma red (/24) primero.
String? pickAddress(List<InternetAddress> addresses, String? localIp) {
  final v4 = [
    for (final a in addresses)
      if (a.type == InternetAddressType.IPv4) a.address,
  ];
  if (v4.isEmpty) return null;
  if (localIp != null) {
    final prefix = localIp.substring(0, localIp.lastIndexOf('.') + 1);
    for (final address in v4) {
      if (address.startsWith(prefix)) return address;
    }
  }
  return v4.first;
}
