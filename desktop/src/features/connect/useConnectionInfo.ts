// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0.
// If a copy of the MPL was not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

import { useEffect, useState } from "react";
import { commands, type ConnectionInfo } from "../../ipc/commands";

// Una sola petición compartida por todas las pantallas.
let pending: Promise<ConnectionInfo> | null = null;
const listeners = new Set<(info: ConnectionInfo) => void>();

/** Vuelve a pedir los datos (p. ej. tras cambiar la carpeta) y avisa a todas las pantallas. */
export async function refreshConnectionInfo() {
  pending = commands.connectionInfo();
  const info = await pending;
  listeners.forEach((listener) => listener(info));
}

/** Datos de esta PC (nombre, IP, puerto, código, carpeta). `null` mientras cargan. */
export function useConnectionInfo() {
  const [info, setInfo] = useState<ConnectionInfo | null>(null);

  useEffect(() => {
    let alive = true;
    const update = (value: ConnectionInfo) => alive && setInfo(value);
    listeners.add(update);
    pending ??= commands.connectionInfo();
    pending.then(update).catch(() => {
      pending = null;
    });
    return () => {
      alive = false;
      listeners.delete(update);
    };
  }, []);

  return info;
}
