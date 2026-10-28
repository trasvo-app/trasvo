// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0.
// If a copy of the MPL was not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

import { open } from "@tauri-apps/plugin-dialog";
import { useState } from "react";
import { commands } from "../../ipc/commands";
import { useTheme } from "../../shared/theme/ThemeProvider";
import type { Theme } from "../../shared/theme/theme";
import { Icon } from "../../shared/ui/Icon";
import { PageHeader } from "../../shared/ui/PageHeader";
import { refreshConnectionInfo, useConnectionInfo } from "../connect/useConnectionInfo";
import { reasonText } from "../transfers/reasons";
import "./settings.css";

const themes: { id: Theme; label: string }[] = [
  { id: "light", label: "Claro" },
  { id: "dark", label: "Oscuro" },
];

export function SettingsPage() {
  const info = useConnectionInfo();
  const { theme, choose } = useTheme();

  const rows = [
    { label: "Nombre de esta PC", value: info?.deviceName ?? "…" },
    { label: "Puerto", value: info?.port ? String(info.port) : "…" },
  ];

  return (
    <>
      <PageHeader title="Ajustes" subtitle="Preferencias de esta PC." />
      <div className="stack">
        <section className="card" aria-labelledby="look-title">
          <h2 className="card__title" id="look-title">
            Apariencia
          </h2>
          <div className="settings__row settings__row--control">
            <span>Tema</span>
            <div className="tabs settings__tabs" role="group" aria-label="Tema">
              {themes.map((t) => (
                <button
                  key={t.id}
                  type="button"
                  className="tabs__tab"
                  aria-pressed={theme === t.id}
                  onClick={() => choose(t.id)}
                >
                  {t.label}
                </button>
              ))}
            </div>
          </div>
        </section>

        <DownloadFolder path={info?.downloadDir} />

        <section className="card" aria-labelledby="device-title">
          <h2 className="card__title" id="device-title">
            Esta PC
          </h2>
          <dl className="settings">
            {rows.map((row) => (
              <div className="settings__row" key={row.label}>
                <dt>{row.label}</dt>
                <dd>{row.value}</dd>
              </div>
            ))}
          </dl>
        </section>
      </div>
    </>
  );
}

/** Dónde se guarda lo que llega del celular. */
function DownloadFolder({ path }: { path: string | undefined }) {
  const [error, setError] = useState<string | null>(null);

  async function run(action: () => Promise<unknown>) {
    setError(null);
    try {
      await action();
      await refreshConnectionInfo();
    } catch (e) {
      setError(reasonText(String(e)));
    }
  }

  async function change() {
    const picked = await open({ directory: true, defaultPath: path });
    if (typeof picked === "string") await run(() => commands.setDownloadDir(picked));
  }

  return (
    <section className="card" aria-labelledby="folder-title">
      <h2 className="card__title" id="folder-title">
        Carpeta de descargas
      </h2>
      <p className="card__subtitle">Lo que recibas del celular se guarda aquí.</p>
      <div className="folder">
        <span className="folder__icon">
          <Icon name="folder" size={20} />
        </span>
        <span className="folder__path code" title={path}>
          {path ?? "…"}
        </span>
      </div>
      {error && (
        <p className="notice notice--error" role="alert" style={{ marginTop: 12 }}>
          {error}
        </p>
      )}
      <div className="folder__actions">
        <button className="btn btn--primary" type="button" onClick={() => void change()}>
          Cambiar carpeta…
        </button>
        <button
          className="btn btn--secondary"
          type="button"
          onClick={() => void run(commands.openDownloadDir)}
        >
          Abrir carpeta
        </button>
        <button
          className="btn btn--secondary"
          type="button"
          onClick={() => void run(commands.resetDownloadDir)}
        >
          Usar Descargas
        </button>
      </div>
    </section>
  );
}
