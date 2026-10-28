// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0.
// If a copy of the MPL was not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

import { describe, expect, it } from "vitest";
import type { TransferEvent } from "../../ipc/events";
import { initialTransfers, transfersReducer, type TransfersState } from "./transfersReducer";

function apply(state: TransfersState, ...events: TransferEvent[]) {
  return events.reduce((s, event) => transfersReducer(s, { type: "event", event, now: 1 }), state);
}

describe("transfersReducer", () => {
  it("follows a send from click to completion", () => {
    let state = transfersReducer(initialTransfers, {
      type: "started",
      id: "t1",
      peerName: "Celular",
      fileCount: 2,
      now: 0,
    });
    expect(state.byId.t1.status).toBe("waiting");

    state = apply(
      state,
      { kind: "waiting", transferId: "t1", peerName: "Celular de Ana", fileCount: 3, totalBytes: 300 },
      {
        kind: "progress",
        transferId: "t1",
        direction: "send",
        bytesDone: 100,
        bytesTotal: 300,
        currentFile: "a.jpg",
      },
    );
    expect(state.byId.t1).toMatchObject({
      status: "active",
      peerName: "Celular de Ana",
      fileCount: 3,
      bytesDone: 100,
      currentFile: "a.jpg",
    });

    state = apply(state, {
      kind: "completed",
      transferId: "t1",
      direction: "send",
      files: ["a.jpg", "b.jpg", "c.jpg"],
    });
    expect(state.byId.t1).toMatchObject({ status: "done", bytesDone: 300, finishedAt: 1 });
    expect(state.order).toEqual(["t1"]);
  });

  it("tracks an incoming offer and the user's answer", () => {
    let state = apply(initialTransfers, {
      kind: "offer",
      transferId: "r1",
      peerName: "Celular",
      files: [{ name: "foto.jpg", size: 10 }],
      totalBytes: 10,
    });
    expect(state.byId.r1).toMatchObject({ direction: "receive", status: "offer", files: ["foto.jpg"] });

    state = transfersReducer(state, { type: "responded", id: "r1", accept: false, now: 2 });
    expect(state.byId.r1).toMatchObject({ status: "declined", finishedAt: 2 });
  });

  it("keeps the newest transfer first and reports failures", () => {
    const state = apply(
      initialTransfers,
      { kind: "waiting", transferId: "a", peerName: "X", fileCount: 1, totalBytes: 1 },
      { kind: "waiting", transferId: "b", peerName: "Y", fileCount: 1, totalBytes: 1 },
      { kind: "failed", transferId: "a", direction: "send", reason: "invalid_code" },
    );
    expect(state.order).toEqual(["b", "a"]);
    expect(state.byId.a).toMatchObject({ status: "failed", reason: "invalid_code" });
  });

  it("does not revive a finished transfer with a late progress event", () => {
    const state = apply(
      initialTransfers,
      { kind: "failed", transferId: "a", direction: "send", reason: "cancelled" },
      {
        kind: "progress",
        transferId: "a",
        direction: "send",
        bytesDone: 1,
        bytesTotal: 2,
        currentFile: "x",
      },
    );
    expect(state.byId.a.status).toBe("failed");
  });
});
