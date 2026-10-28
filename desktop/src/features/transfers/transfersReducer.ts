// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0.
// If a copy of the MPL was not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

import type { Direction, TransferEvent } from "../../ipc/events";

/** Estado de las transferencias de esta sesión, derivado de los eventos del motor. */

export type TransferStatus = "offer" | "waiting" | "active" | "done" | "failed" | "declined";

export type Transfer = {
  id: string;
  direction: Direction;
  peerName: string;
  fileCount: number;
  /** Nombres ofrecidos; al terminar, rutas guardadas (recibir) o nombres enviados. */
  files: string[];
  bytesTotal: number;
  bytesDone: number;
  currentFile: string;
  status: TransferStatus;
  reason?: string;
  startedAt: number;
  finishedAt?: number;
};

export type TransfersState = {
  byId: Record<string, Transfer>;
  /** Ids de la más nueva a la más vieja. */
  order: string[];
};

export type TransfersAction =
  | { type: "event"; event: TransferEvent; now: number }
  | { type: "started"; id: string; peerName: string; fileCount: number; now: number }
  | { type: "responded"; id: string; accept: boolean; now: number };

export const initialTransfers: TransfersState = { byId: {}, order: [] };

const FINISHED: TransferStatus[] = ["done", "failed", "declined"];

export function isFinished(t: Transfer) {
  return FINISHED.includes(t.status);
}

function upsert(
  state: TransfersState,
  id: string,
  create: () => Transfer,
  patch: (t: Transfer) => Partial<Transfer>,
): TransfersState {
  const current = state.byId[id] ?? create();
  const next = { ...current, ...patch(current) };
  return {
    byId: { ...state.byId, [id]: next },
    order: state.byId[id] ? state.order : [id, ...state.order],
  };
}

function blank(id: string, direction: Direction, now: number): Transfer {
  return {
    id,
    direction,
    peerName: "",
    fileCount: 0,
    files: [],
    bytesTotal: 0,
    bytesDone: 0,
    currentFile: "",
    status: "waiting",
    startedAt: now,
  };
}

export function transfersReducer(state: TransfersState, action: TransfersAction): TransfersState {
  switch (action.type) {
    case "started":
      return upsert(state, action.id, () => blank(action.id, "send", action.now), () => ({
        peerName: action.peerName,
        fileCount: action.fileCount,
      }));

    case "responded":
      if (!state.byId[action.id]) return state;
      return upsert(state, action.id, () => state.byId[action.id], () =>
        action.accept
          ? { status: "active" }
          : { status: "declined", finishedAt: action.now },
      );

    case "event": {
      const { event, now } = action;
      const id = event.transferId;
      switch (event.kind) {
        case "offer":
          return upsert(state, id, () => blank(id, "receive", now), () => ({
            peerName: event.peerName,
            files: event.files.map((f) => f.name),
            fileCount: event.files.length,
            bytesTotal: event.totalBytes,
            status: "offer",
          }));
        case "waiting":
          return upsert(state, id, () => blank(id, "send", now), () => ({
            peerName: event.peerName,
            fileCount: event.fileCount,
            bytesTotal: event.totalBytes,
            status: "waiting",
          }));
        case "progress":
          return upsert(state, id, () => blank(id, event.direction, now), (t) => ({
            bytesDone: event.bytesDone,
            bytesTotal: event.bytesTotal,
            currentFile: event.currentFile,
            status: isFinished(t) ? t.status : "active",
          }));
        case "completed":
          return upsert(state, id, () => blank(id, event.direction, now), (t) => ({
            files: event.files,
            fileCount: event.files.length,
            bytesDone: t.bytesTotal,
            status: "done",
            finishedAt: now,
          }));
        case "failed":
          return upsert(state, id, () => blank(id, event.direction, now), () => ({
            status: event.reason === "declined" ? "declined" : "failed",
            reason: event.reason,
            finishedAt: now,
          }));
      }
    }
  }
}
