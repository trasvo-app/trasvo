// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0.
// If a copy of the MPL was not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

import { open } from "@tauri-apps/plugin-dialog";
import { useState } from "react";
import type { PageProps } from "../../app/routes";
import { plural } from "../../shared/format";
import { Icon } from "../../shared/ui/Icon";
import { PageHeader } from "../../shared/ui/PageHeader";
import { LinkStatusCard } from "../connect/LinkStatusCard";
import { useLink } from "../connect/LinkProvider";
import { reasonText } from "../transfers/reasons";
import { TransferList } from "../transfers/TransferList";
import { useTransfers } from "../transfers/TransfersProvider";
import { isFinished } from "../transfers/transfersReducer";
import { useSendQueue, type QueueItem } from "./useSendQueue";
import "./send.css";

function splitPath(path: string) {
  const parts = path.split(/[\\/]/);
  const name = parts.pop() ?? path;
  return { name, folder: parts.join("\\") };
}

export function SendPage({ navigate }: PageProps) {
  const queue = useSendQueue();
  const transfers = useTransfers();
  const { peer: connection } = useLink();
  const [sending, setSending] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function pick(kind: QueueItem["kind"]) {
    const picked = await open({ multiple: true, directory: kind === "folder" });
    if (picked) queue.add(picked, kind);
  }

  async function send() {
    if (!connection) return;
    setSending(true);
    setError(null);
    try {
      await transfers.startSend(connection.name, queue.items.map((i) => i.path));
      queue.clear();
    } catch (e) {
      setError(reasonText(String(e)));
    } finally {
      setSending(false);
    }
  }

  const count = queue.items.length;
  const sendHint = !count
    ? "Agrega archivos para enviar."
    : !connection
      ? "Conecta tu celular para enviar."
      : `Se enviarán a ${connection.name}.`;

  // Envíos en curso y los terminados recientemente, para ver cómo fue.
  const sends = transfers.list
    .filter((t) => t.direction === "send")
    .filter((t) => !isFinished(t) || Date.now() - (t.finishedAt ?? 0) < 10 * 60 * 1000)
    .slice(0, 5);

  return (
    <>
      <PageHeader
        title="Enviar archivos"
        subtitle="Agrega lo que quieras pasar al celular conectado."
      />

      <div className="page-grid">
        <div className="stack">
          <section
            className="dropzone"
            data-active={queue.dragging}
            aria-label="Zona para soltar archivos"
          >
            <span className="dropzone__icon">
              <Icon name="upload" size={26} />
            </span>
            <strong>{queue.dragging ? "Suelta aquí para agregar" : "Arrastra archivos aquí"}</strong>
            <span className="dropzone__hint">Desde el Escritorio o cualquier carpeta de tu PC.</span>
            <div className="dropzone__actions">
              <button className="btn btn--primary" type="button" onClick={() => pick("file")}>
                <Icon name="file" size={18} /> Elegir archivos
              </button>
              <button className="btn btn--secondary" type="button" onClick={() => pick("folder")}>
                <Icon name="folder" size={18} /> Elegir carpeta
              </button>
            </div>
          </section>

          <section className="card" aria-labelledby="queue-title">
            <div className="queue__header">
              <h2 className="card__title" id="queue-title">
                Para enviar
                {count > 0 && <span className="chip">{count}</span>}
              </h2>
              {count > 0 && (
                <button className="link" type="button" onClick={queue.clear}>
                  Quitar todo
                </button>
              )}
            </div>

            {count === 0 ? (
              <div className="empty">
                <span className="empty__icon">
                  <Icon name="file" />
                </span>
                Todavía no agregaste archivos.
              </div>
            ) : (
              <ul className="queue">
                {queue.items.map((item) => {
                  const { name, folder } = splitPath(item.path);
                  return (
                    <li className="queue__item" key={item.path}>
                      <span className="queue__icon" data-kind={item.kind}>
                        <Icon name={item.kind} size={18} />
                      </span>
                      <span className="queue__text">
                        <span className="queue__name">{name}</span>
                        <span className="queue__folder">{folder}</span>
                      </span>
                      <button
                        className="icon-btn"
                        type="button"
                        onClick={() => queue.remove(item.path)}
                        aria-label={`Quitar ${name}`}
                      >
                        <Icon name="close" size={16} />
                      </button>
                    </li>
                  );
                })}
              </ul>
            )}

            {error && (
              <p className="notice notice--error" role="alert" style={{ marginTop: 12 }}>
                {error}
              </p>
            )}
            <button
              className="btn btn--primary btn--block queue__send"
              type="button"
              disabled={!count || !connection || sending}
              onClick={send}
            >
              <Icon name="upload" size={18} />
              {count > 0 ? `Enviar ${plural(count, "elemento", "elementos")}` : "Enviar"}
            </button>
            <p className="queue__hint">{sendHint}</p>
          </section>

          {sends.length > 0 && (
            <section className="card" aria-labelledby="sends-title">
              <h2 className="card__title" id="sends-title" style={{ marginBottom: 12 }}>
                Envíos
              </h2>
              <TransferList transfers={sends} onCancel={transfers.cancel} />
            </section>
          )}
        </div>

        <section className="card" aria-labelledby="link-title">
          <h2 className="card__title" id="link-title">
            <Icon name="phone" size={18} />
            Celular
          </h2>
          {connection ? (
            <>
              <p className="card__subtitle">Todo lo que envíes llega a este celular.</p>
              <LinkStatusCard />
            </>
          ) : (
            <>
              <p className="card__subtitle">
                Todavía no hay ningún celular conectado. Conéctalo una vez y queda enlazado.
              </p>
              <button
                className="btn btn--primary btn--block"
                type="button"
                onClick={() => navigate("connect")}
              >
                <Icon name="wifi" size={18} /> Conectar celular
              </button>
            </>
          )}
        </section>
      </div>
    </>
  );
}
