// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0.
// If a copy of the MPL was not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

import { createContext, useContext, useState, type ReactNode } from "react";
import { applyTheme, loadTheme, saveTheme, systemTheme, type Theme } from "./theme";

type ThemeContextValue = {
  theme: Theme;
  /** `false` en el primer inicio, hasta que el usuario confirma su elección. */
  chosen: boolean;
  /** Cambia el tema en pantalla sin guardarlo (vista previa). */
  preview: (theme: Theme) => void;
  /** Cambia y guarda el tema. */
  choose: (theme: Theme) => void;
};

const ThemeContext = createContext<ThemeContextValue | null>(null);

export function ThemeProvider({ children }: { children: ReactNode }) {
  const [saved] = useState(loadTheme);
  const [theme, setTheme] = useState<Theme>(() => saved ?? systemTheme());
  const [chosen, setChosen] = useState(saved !== null);

  const preview = (next: Theme) => {
    applyTheme(next);
    setTheme(next);
  };

  const choose = (next: Theme) => {
    preview(next);
    saveTheme(next);
    setChosen(true);
  };

  return (
    <ThemeContext.Provider value={{ theme, chosen, preview, choose }}>
      {children}
    </ThemeContext.Provider>
  );
}

export function useTheme() {
  const value = useContext(ThemeContext);
  if (!value) throw new Error("useTheme must be used inside ThemeProvider");
  return value;
}
