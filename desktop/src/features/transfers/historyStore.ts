// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0.
// If a copy of the MPL was not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

import { isFinished, type Transfer, type TransfersState } from "./transfersReducer";

/** Historial guardado en este equipo: solo transferencias terminadas, las más nuevas. */

const STORAGE_KEY = "ft.history";
export const HISTORY_LIMIT = 200;

type Storage = Pick<globalThis.Storage, "getItem" | "setItem">;

function isTransfer(value: unknown): value is Transfer {
  const t = value as Transfer;
  return (
    typeof t === "object" &&
    t !== null &&
    typeof t.id === "string" &&
    (t.direction === "send" || t.direction === "receive") &&
    typeof t.status === "string" &&
    Array.isArray(t.files) &&
    isFinished(t)
  );
}

export function loadHistory(storage: Storage | undefined = safeStorage()): TransfersState {
  try {
    const raw = storage?.getItem(STORAGE_KEY);
    const parsed: unknown = raw ? JSON.parse(raw) : [];
    const list = Array.isArray(parsed) ? parsed.filter(isTransfer) : [];
    return {
      byId: Object.fromEntries(list.map((t) => [t.id, t])),
      order: list.map((t) => t.id),
    };
  } catch {
    return { byId: {}, order: [] };
  }
}

export function saveHistory(state: TransfersState, storage: Storage | undefined = safeStorage()) {
  const finished = state.order
    .map((id) => state.byId[id])
    .filter(isFinished)
    .slice(0, HISTORY_LIMIT);
  try {
    storage?.setItem(STORAGE_KEY, JSON.stringify(finished));
  } catch {
    // Sin almacenamiento: el historial dura lo que dure la sesión.
  }
}

function safeStorage(): Storage | undefined {
  try {
    return globalThis.localStorage;
  } catch {
    return undefined;
  }
}
