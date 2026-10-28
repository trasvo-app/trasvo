// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0.
// If a copy of the MPL was not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

/** Validaciones del formulario de conexión por IP (el backend vuelve a validar). */

export function isValidIpv4(value: string) {
  const parts = value.trim().split(".");
  return (
    parts.length === 4 &&
    parts.every((p) => /^\d{1,3}$/.test(p) && Number(p) <= 255)
  );
}

export function isValidPort(value: string) {
  return /^\d{1,5}$/.test(value) && Number(value) >= 1 && Number(value) <= 65535;
}

export function isValidCode(value: string) {
  return /^\d{6}$/.test(value);
}
