// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0.
// If a copy of the MPL was not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

import { invoke } from "@tauri-apps/api/core";
import type { LinkStatus, NearbyDevice, Peer } from "./events";

/** Cliente tipado hacia los comandos de Tauri. La UI no llama `invoke` directo. */

export type ConnectionInfo = {
  deviceName: string;
  ip: string | null;
  /** `null` si el servidor no pudo abrir ningún puerto. */
  port: number | null;
  code: string;
  downloadDir: string;
};

/** Códigos de error que devuelve el backend (ver `TransferError::code`). */
export type ErrorCode =
  | "invalid_code"
  | "invalid_ip"
  | "invalid_port"
  | "invalid_folder"
  | "unreachable"
  | "locked"
  | "version_mismatch"
  | "declined"
  | "timeout"
  | "hash_mismatch"
  | "cancelled"
  | "invalid_name"
  | "empty"
  | "not_connected"
  | "io"
  | "protocol";

export type Target = { ip: string; port: number; code: string };

export type LinkView = { status: LinkStatus; peer: Peer | null };

export const commands = {
  protocolVersion: () => invoke<number>("protocol_version"),
  connectionInfo: () => invoke<ConnectionInfo>("connection_info"),
  /** Se enlaza con IP y código; devuelve el nombre del otro dispositivo. */
  connect: (target: Target) => invoke<string>("connect", target),
  /** Se enlaza con un dispositivo encontrado en el Wi-Fi (el otro lado debe aceptar). */
  connectNearby: (device: Pick<NearbyDevice, "ip" | "port">) =>
    invoke<string>("connect_nearby", { ip: device.ip, port: device.port }),
  /** Cierra el enlace en los dos lados. */
  disconnect: () => invoke<void>("disconnect"),
  linkState: () => invoke<LinkView>("link_state"),
  nearbyDevices: () => invoke<NearbyDevice[]>("nearby_devices"),
  /** Empieza a enviar al dispositivo enlazado y devuelve el id; el progreso llega por eventos. */
  sendFiles: (paths: string[]) => invoke<string>("send_files", { paths }),
  /** Responde a una oferta de archivos o a una petición de conexión. */
  respondOffer: (transferId: string, accept: boolean) =>
    invoke<boolean>("respond_offer", { transferId, accept }),
  cancelTransfer: (transferId: string) => invoke<boolean>("cancel_transfer", { transferId }),
  /** Cambia la carpeta de descargas; devuelve la ruta guardada. */
  setDownloadDir: (path: string) => invoke<string>("set_download_dir", { path }),
  resetDownloadDir: () => invoke<string>("reset_download_dir"),
  openDownloadDir: () => invoke<void>("open_download_dir"),
};
