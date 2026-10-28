// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0.
// If a copy of the MPL was not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

import type { LinkEvent, LinkStatus, NearbyDevice, Peer } from "../../ipc/events";

/** Enlace con el otro dispositivo, derivado de los eventos del motor. */

export type LinkState = {
  status: LinkStatus;
  peer: Peer | null;
  /** Petición de conexión sin código esperando respuesta. */
  request: { id: string; peerName: string } | null;
  nearby: NearbyDevice[];
};

export type LinkAction =
  | { type: "event"; event: LinkEvent }
  | { type: "loaded"; status: LinkStatus; peer: Peer | null }
  | { type: "nearby"; devices: NearbyDevice[] }
  | { type: "answered" };

export const initialLink: LinkState = {
  status: "disconnected",
  peer: null,
  request: null,
  nearby: [],
};

export function linkReducer(state: LinkState, action: LinkAction): LinkState {
  switch (action.type) {
    case "loaded":
      return { ...state, status: action.status, peer: action.peer };
    case "nearby":
      return { ...state, nearby: action.devices };
    case "answered":
      return { ...state, request: null };
    case "event": {
      const { event } = action;
      switch (event.kind) {
        case "link":
          return { ...state, status: event.status, peer: event.peer };
        case "linkRequest":
          return { ...state, request: { id: event.requestId, peerName: event.peerName } };
        case "linkRequestEnded":
          return state.request?.id === event.requestId ? { ...state, request: null } : state;
      }
    }
  }
}
