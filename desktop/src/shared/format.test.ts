// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0.
// If a copy of the MPL was not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

import { describe, expect, it } from "vitest";
import { formatBytes, percent, plural } from "./format";

describe("formatBytes", () => {
  it.each([
    [0, "0 B"],
    [999, "999 B"],
    [1536, "1,5 KB"],
    [5 * 1024 * 1024, "5,0 MB"],
    [3.25 * 1024 ** 3, "3,3 GB"],
  ])("%d → %s", (bytes, text) => expect(formatBytes(bytes)).toBe(text));
});

describe("percent", () => {
  it("floors and clamps", () => {
    expect(percent(0, 100)).toBe(0);
    expect(percent(999, 1000)).toBe(99);
    expect(percent(1000, 1000)).toBe(100);
    expect(percent(5, 0)).toBe(100);
  });
});

describe("plural", () => {
  it("picks the right form", () => {
    expect(plural(1, "archivo", "archivos")).toBe("1 archivo");
    expect(plural(3, "archivo", "archivos")).toBe("3 archivos");
  });
});
