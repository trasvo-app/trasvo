// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0.
// If a copy of the MPL was not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

import { useState } from "react";
import { DEFAULT_PORT } from "../../ipc/constants";
import type { NearbyDevice } from "../../ipc/events";
import { Icon, type IconName } from "../../shared/ui/Icon";
import { reasonText } from "../transfers/reasons";
import { LinkStatusCard } from "./LinkStatusCard";
import { useLink } from "./LinkProvider";
import { ManualIpForm } from "./ManualIpForm";
import { QrCard } from "./QrCard";
import { useConnectionInfo } from "./useConnectionInfo";
import "./connect.css";

type Tab = "nearby" | "qr" | "ip";

const tabs: { id: Tab; label: string; icon: IconName }[] = [
  { id: "nearby", label: "Cerca", icon: "wifi" },
  { id: "qr", label: "QR", icon: "qr" },
  { id: "ip", label: "IP", icon: "keyboard" },
];

/** Conectar con el celular una sola vez; después se envía en ambos sentidos. */
export function ConnectPanel() {
  const link = useLink();
  const [tab, setTab] = useState<Tab>("nearby");
  const info = useConnectionInfo();
  const address = info?.ip && info.port ? `${info.ip}:${info.port}` : "…";

  return (
    <section className="card" aria-labelledby="connect-title">
      <h2 className="card__title" id="connect-title">
        <Icon name="phone" size={18} />
        Conectar celular
      </h2>
      <p className="card__subtitle">
        Conéctalo una vez: quedan enlazados para enviar en ambos sentidos hasta que toques
        «Desconectar».
      </p>

      {link.peer ? (
        <LinkStatusCard />
      ) : (
        <>
          <div className="tabs" role="tablist">
            {tabs.map((t) => (
              <button
                key={t.id}
                type="button"
                role="tab"
                className="tabs__tab"
                aria-selected={tab === t.id}
                onClick={() => setTab(t.id)}
              >
                <Icon name={t.icon} size={16} />
                {t.label}
              </button>
            ))}
          </div>

          {tab === "nearby" && <NearbyList devices={link.nearby} />}

          {tab === "qr" && (
            <>
              <QrCard info={info} />
              <p className="field__hint" style={{ marginTop: 12 }}>
                En el celular: «Escanear QR» y apunta la cámara a este código.
              </p>
            </>
          )}

          {tab === "ip" && (
            <>
              <ManualIpForm defaultPort={DEFAULT_PORT} />
              <div className="notice notice--info" style={{ marginTop: 12, marginBottom: 0 }}>
                <span>
                  O desde el celular, con IP <strong className="code">{address}</strong> y
                  código <strong className="code">{info?.code ?? "······"}</strong>.
                </span>
              </div>
            </>
          )}
        </>
      )}
    </section>
  );
}

function NearbyList({ devices }: { devices: NearbyDevice[] }) {
  const { connectNearby } = useLink();
  const [waiting, setWaiting] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);

  async function connect(device: NearbyDevice) {
    setWaiting(device.id);
    setError(null);
    try {
      await connectNearby(device);
    } catch (e) {
      setError(reasonText(String(e)));
    } finally {
      setWaiting(null);
    }
  }

  return (
    <div className="nearby">
      <p className="nearby__searching">
        <span className="spinner" aria-hidden="true" />
        Buscando celulares con la app abierta en tu Wi-Fi…
      </p>
      {error && (
        <p className="notice notice--error" role="alert">
          {error}
        </p>
      )}
      {devices.length === 0 ? (
        <ol className="steps">
          <li>Abre la app en tu celular.</li>
          <li>Conéctalo al mismo Wi-Fi que esta PC.</li>
          <li>Aparecerá aquí: tócalo y acepta en el celular.</li>
        </ol>
      ) : (
        <ul className="nearby__list">
          {devices.map((device) => (
            <li key={device.id}>
              <button
                type="button"
                className="nearby__item"
                data-waiting={waiting === device.id}
                disabled={waiting !== null}
                onClick={() => connect(device)}
              >
                <span className="nearby__icon">
                  <Icon name="phone" size={18} />
                </span>
                <span className="nearby__text">
                  <strong>{device.name}</strong>
                  <span>{waiting === device.id ? "Acepta la conexión en el celular…" : device.ip}</span>
                </span>
                {waiting === device.id ? (
                  <span className="spinner" aria-hidden="true" />
                ) : (
                  <span className="nearby__action">Conectar</span>
                )}
              </button>
            </li>
          ))}
        </ul>
      )}
    </div>
  );
}
