// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0.
// If a copy of the MPL was not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

/** Tema de la app: se elige en el primer inicio y se recuerda en este equipo. */

export type Theme = "light" | "dark";

const STORAGE_KEY = "ft.theme";

export function parseTheme(value: unknown): Theme | null {
  return value === "light" || value === "dark" ? value : null;
}

/** Tema guardado, o `null` si el usuario todavía no eligió (primer inicio). */
export function loadTheme(): Theme | null {
  try {
    return parseTheme(localStorage.getItem(STORAGE_KEY));
  } catch {
    return null;
  }
}

export function saveTheme(theme: Theme) {
  try {
    localStorage.setItem(STORAGE_KEY, theme);
  } catch {
    // Sin almacenamiento: el tema vale solo para esta sesión.
  }
}

export function systemTheme(): Theme {
  return window.matchMedia?.("(prefers-color-scheme: dark)").matches ? "dark" : "light";
}

/** Aplica el tema sin animar los colores (se reactivan las transiciones al siguiente frame). */
export function applyTheme(theme: Theme) {
  const root = document.documentElement;
  root.classList.add("no-transitions");
  root.dataset.theme = theme;
  void getComputedStyle(root).opacity;
  requestAnimationFrame(() => root.classList.remove("no-transitions"));
}
