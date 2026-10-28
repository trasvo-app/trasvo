// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0.
// If a copy of the MPL was not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

import { isTauri } from "@tauri-apps/api/core";
import { listen } from "@tauri-apps/api/event";

/** Eventos del motor (ver `ft_transfer::Event`) y de la búsqueda en el Wi-Fi. */

export type Direction = "send" | "receive";

export type TransferEvent =
  | {
      kind: "offer";
      transferId: string;
      peerName: string;
      files: { name: string; size: number }[];
      totalBytes: number;
    }
  | {
      kind: "waiting";
      transferId: string;
      peerName: string;
      fileCount: number;
      totalBytes: number;
    }
  | {
      kind: "progress";
      transferId: string;
      direction: Direction;
      bytesDone: number;
      bytesTotal: number;
      currentFile: string;
    }
  | { kind: "completed"; transferId: string; direction: Direction; files: string[] }
  | { kind: "failed"; transferId: string; direction: Direction; reason: string };

export type LinkStatus = "connected" | "reconnecting" | "disconnected";

/** El otro dispositivo del enlace. */
export type Peer = { name: string; ip: string; port: number };

export type LinkEvent =
  | { kind: "link"; status: LinkStatus; peer: Peer | null }
  /** Un dispositivo cercano pide conectarse: responder con `respondOffer(requestId, …)`. */
  | { kind: "linkRequest"; requestId: string; peerName: string }
  | { kind: "linkRequestEnded"; requestId: string };

export type EngineEvent = TransferEvent | LinkEvent;

/** Otro dispositivo con la app, encontrado en el mismo Wi-Fi. */
export type NearbyDevice = { id: string; name: string; ip: string; port: number };

const LINK_KINDS: EngineEvent["kind"][] = ["link", "linkRequest", "linkRequestEnded"];

export function isLinkEvent(event: EngineEvent): event is LinkEvent {
  return LINK_KINDS.includes(event.kind);
}

function subscribe<T>(name: string, handler: (payload: T) => void): () => void {
  if (!isTauri()) return () => {};
  const unlisten = listen<T>(name, (e) => handler(e.payload));
  return () => {
    void unlisten.then((fn) => fn());
  };
}

/** Se suscribe a los eventos del motor. Devuelve la función para desuscribirse. */
export function onEngineEvent(handler: (event: EngineEvent) => void): () => void {
  return subscribe("transfer-event", handler);
}

/** Lista completa de dispositivos cercanos cada vez que cambia. */
export function onNearbyDevices(handler: (devices: NearbyDevice[]) => void): () => void {
  return subscribe("nearby-devices", handler);
}
