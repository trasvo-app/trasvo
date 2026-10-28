// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0.
// If a copy of the MPL was not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

import { describe, expect, it } from "vitest";
import { HISTORY_LIMIT, loadHistory, saveHistory } from "./historyStore";
import type { Transfer, TransfersState } from "./transfersReducer";

function memoryStorage(initial: Record<string, string> = {}) {
  const data = { ...initial };
  return {
    data,
    getItem: (key: string) => data[key] ?? null,
    setItem: (key: string, value: string) => {
      data[key] = value;
    },
  };
}

function transfer(id: string, status: Transfer["status"]): Transfer {
  return {
    id,
    direction: "send",
    peerName: "Celular",
    fileCount: 1,
    files: ["a.jpg"],
    bytesTotal: 10,
    bytesDone: 10,
    currentFile: "",
    status,
    startedAt: 1,
    finishedAt: 2,
  };
}

function state(...transfers: Transfer[]): TransfersState {
  return {
    byId: Object.fromEntries(transfers.map((t) => [t.id, t])),
    order: transfers.map((t) => t.id),
  };
}

describe("history store", () => {
  it("saves only finished transfers and loads them back in order", () => {
    const storage = memoryStorage();
    saveHistory(
      state(transfer("a", "done"), transfer("b", "active"), transfer("c", "failed")),
      storage,
    );

    const loaded = loadHistory(storage);
    expect(loaded.order).toEqual(["a", "c"]);
    expect(loaded.byId.a.status).toBe("done");
  });

  it("keeps at most the newest entries", () => {
    const storage = memoryStorage();
    const many = Array.from({ length: HISTORY_LIMIT + 5 }, (_, i) => transfer(`t${i}`, "done"));
    saveHistory(state(...many), storage);
    const loaded = loadHistory(storage);
    expect(loaded.order).toHaveLength(HISTORY_LIMIT);
    expect(loaded.order[0]).toBe("t0");
  });

  it("ignores corrupt or foreign data", () => {
    expect(loadHistory(memoryStorage({ "ft.history": "{not json" })).order).toEqual([]);
    const junk = JSON.stringify([{ id: 1 }, null, transfer("ok", "declined")]);
    expect(loadHistory(memoryStorage({ "ft.history": junk })).order).toEqual(["ok"]);
    expect(loadHistory(undefined).order).toEqual([]);
  });
});
