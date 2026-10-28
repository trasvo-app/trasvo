// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0.
// If a copy of the MPL was not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

/** Contenido del QR que escanea el celular. Ver docs/protocol.md. */
export function pairingUri(info: { deviceName: string; ip: string; port: number; code: string }) {
  const params = new URLSearchParams({
    ip: info.ip,
    port: String(info.port),
    code: info.code,
    name: info.deviceName,
  });
  return `ftransfer://pair?${params}`;
}
