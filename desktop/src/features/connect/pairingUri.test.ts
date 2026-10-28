// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0.
// If a copy of the MPL was not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

import { describe, expect, it } from "vitest";
import { pairingUri } from "./pairingUri";

describe("pairingUri", () => {
  it("encodes every field so the phone can parse it back", () => {
    const uri = pairingUri({
      deviceName: "PC de Ana & Co",
      ip: "192.168.1.20",
      port: 47520,
      code: "012345",
    });

    const url = new URL(uri);
    expect(url.protocol).toBe("ftransfer:");
    expect(url.searchParams.get("ip")).toBe("192.168.1.20");
    expect(url.searchParams.get("port")).toBe("47520");
    expect(url.searchParams.get("code")).toBe("012345");
    expect(url.searchParams.get("name")).toBe("PC de Ana & Co");
  });
});
