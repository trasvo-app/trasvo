// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0.
// If a copy of the MPL was not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

import { describe, expect, it } from "vitest";
import { isValidCode, isValidIpv4, isValidPort } from "./validation";

describe("isValidIpv4", () => {
  it.each(["192.168.1.20", "10.0.0.1", " 172.16.5.4 ", "0.0.0.0"])(
    "accepts %s",
    (ip) => expect(isValidIpv4(ip)).toBe(true),
  );

  it.each(["", "192.168.1", "192.168.1.256", "a.b.c.d", "1.2.3.4.5", "1..2.3"])(
    "rejects %s",
    (ip) => expect(isValidIpv4(ip)).toBe(false),
  );
});

describe("isValidPort", () => {
  it("accepts the usual range", () => {
    expect(isValidPort("1")).toBe(true);
    expect(isValidPort("47520")).toBe(true);
    expect(isValidPort("65535")).toBe(true);
  });

  it("rejects out of range or non numeric", () => {
    for (const port of ["", "0", "65536", "80a", "-1"]) {
      expect(isValidPort(port)).toBe(false);
    }
  });
});

describe("isValidCode", () => {
  it("needs exactly six digits", () => {
    expect(isValidCode("012345")).toBe(true);
    expect(isValidCode("12345")).toBe(false);
    expect(isValidCode("1234567")).toBe(false);
    expect(isValidCode("12a456")).toBe(false);
  });
});
