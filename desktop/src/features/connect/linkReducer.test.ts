// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0.
// If a copy of the MPL was not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

import { describe, expect, it } from "vitest";
import { initialLink, linkReducer } from "./linkReducer";

const peer = { name: "Pixel", ip: "192.168.1.20", port: 47520 };

describe("linkReducer", () => {
  it("follows the link through connect, reconnect and disconnect", () => {
    let state = linkReducer(initialLink, {
      type: "event",
      event: { kind: "link", status: "connected", peer },
    });
    expect(state.peer).toEqual(peer);
    expect(state.status).toBe("connected");

    state = linkReducer(state, {
      type: "event",
      event: { kind: "link", status: "reconnecting", peer },
    });
    expect(state.status).toBe("reconnecting");
    expect(state.peer?.name).toBe("Pixel");

    state = linkReducer(state, {
      type: "event",
      event: { kind: "link", status: "disconnected", peer: null },
    });
    expect(state.peer).toBeNull();
  });

  it("shows a connection request until it is answered or expires", () => {
    const asked = linkReducer(initialLink, {
      type: "event",
      event: { kind: "linkRequest", requestId: "r1", peerName: "Pixel" },
    });
    expect(asked.request).toEqual({ id: "r1", peerName: "Pixel" });

    // El fin de otra petición no la cierra.
    const other = linkReducer(asked, {
      type: "event",
      event: { kind: "linkRequestEnded", requestId: "r0" },
    });
    expect(other.request?.id).toBe("r1");

    expect(
      linkReducer(asked, { type: "event", event: { kind: "linkRequestEnded", requestId: "r1" } })
        .request,
    ).toBeNull();
    expect(linkReducer(asked, { type: "answered" }).request).toBeNull();
  });

  it("keeps the nearby list and the initial state", () => {
    const devices = [{ id: "a", name: "Pixel", ip: "192.168.1.20", port: 47520 }];
    const state = linkReducer(initialLink, { type: "nearby", devices });
    expect(state.nearby).toEqual(devices);
    expect(linkReducer(state, { type: "loaded", status: "connected", peer }).nearby).toEqual(
      devices,
    );
  });
});
