// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0.
// If a copy of the MPL was not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

import logo from "../../assets/trasvo-icon.svg";
import { useTheme } from "../../shared/theme/ThemeProvider";
import type { Theme } from "../../shared/theme/theme";
import { Icon } from "../../shared/ui/Icon";
import "./onboarding.css";

const options: { id: Theme; label: string; hint: string }[] = [
  { id: "light", label: "Claro", hint: "Fondo blanco, ideal de día" },
  { id: "dark", label: "Oscuro", hint: "Fondo negro, descansa la vista" },
];

/** Primer inicio: el usuario elige el tema. Al tocar una opción se ve en vivo. */
export function ThemeChoice() {
  const { theme, preview, choose } = useTheme();

  return (
    <div className="onboarding" role="dialog" aria-modal="true" aria-labelledby="onb-title">
      <div className="onboarding__panel">
        <div className="onboarding__intro stagger" style={{ "--i": 0 } as React.CSSProperties}>
          <img className="brand__logo" src={logo} alt="" width={36} height={36} />
          <h1 id="onb-title">¡Bienvenido a Trasvo!</h1>
          <p>¿Cómo prefieres ver la app? Puedes cambiarlo cuando quieras en Ajustes.</p>
        </div>

        <div
          className="onboarding__options stagger"
          role="radiogroup"
          aria-label="Tema"
          style={{ "--i": 1 } as React.CSSProperties}
        >
          {options.map((option) => (
            <button
              key={option.id}
              type="button"
              role="radio"
              aria-checked={theme === option.id}
              aria-label={`${option.label}: ${option.hint}`}
              className="theme-option"
              onClick={() => preview(option.id)}
            >
              <span className={`theme-preview theme-preview--${option.id}`} aria-hidden="true">
                <span className="theme-preview__side">
                  <i />
                  <i />
                  <i />
                </span>
                <span className="theme-preview__main">
                  <b />
                  <span className="theme-preview__card">
                    <i />
                    <em />
                  </span>
                </span>
              </span>
              <span className="theme-option__text">
                <strong>{option.label}</strong>
                <span>{option.hint}</span>
              </span>
              <span className="theme-option__check">
                <Icon name="check" size={16} />
              </span>
            </button>
          ))}
        </div>

        <button
          className="btn btn--primary btn--block stagger"
          type="button"
          style={{ "--i": 2 } as React.CSSProperties}
          onClick={() => choose(theme)}
        >
          Continuar
        </button>
      </div>
    </div>
  );
}
