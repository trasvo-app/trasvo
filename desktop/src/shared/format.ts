// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0.
// If a copy of the MPL was not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

const UNITS = ["B", "KB", "MB", "GB", "TB"];

/** 1536 → "1,5 KB". Base 1024, un decimal desde KB, coma decimal. */
export function formatBytes(bytes: number) {
  let value = Math.max(0, bytes);
  let unit = 0;
  while (value >= 1024 && unit < UNITS.length - 1) {
    value /= 1024;
    unit += 1;
  }
  const text = unit === 0 ? String(Math.round(value)) : value.toFixed(1).replace(".", ",");
  return `${text} ${UNITS[unit]}`;
}

/** Porcentaje entero entre 0 y 100; un total de 0 cuenta como completo. */
export function percent(done: number, total: number) {
  if (total <= 0) return 100;
  return Math.min(100, Math.floor((done / total) * 100));
}

export function plural(count: number, one: string, many: string) {
  return `${count} ${count === 1 ? one : many}`;
}
