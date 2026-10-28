// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0.
// If a copy of the MPL was not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

import { formatBytes, percent, plural } from "../../shared/format";
import { Icon } from "../../shared/ui/Icon";
import { reasonText } from "./reasons";
import type { Transfer } from "./transfersReducer";
import "./transfers.css";

function statusLine(t: Transfer) {
  switch (t.status) {
    case "offer":
      return "Esperando tu respuesta…";
    case "waiting":
      return "Esperando que acepte en el otro dispositivo…";
    case "active":
      return `${t.currentFile || "Preparando…"} · ${formatBytes(t.bytesDone)} de ${formatBytes(t.bytesTotal)}`;
    case "done":
      return `${plural(t.fileCount, "archivo", "archivos")} · ${formatBytes(t.bytesTotal)}`;
    case "declined":
      return t.direction === "receive" ? "Lo rechazaste." : reasonText("declined");
    case "failed":
      return reasonText(t.reason);
  }
}

function title(t: Transfer) {
  const peer = t.peerName || "dispositivo";
  const inProgress = t.status === "active" || t.status === "waiting" || t.status === "offer";
  if (t.direction === "send") {
    return t.status === "done" ? `Enviado a ${peer}` : inProgress ? `Enviando a ${peer}` : `Envío a ${peer}`;
  }
  return t.status === "done"
    ? `Recibido de ${peer}`
    : inProgress
      ? `Recibiendo de ${peer}`
      : `Recepción de ${peer}`;
}

export function TransferList({
  transfers,
  onCancel,
}: {
  transfers: Transfer[];
  /** Si se pasa, las transferencias en curso muestran «Cancelar». */
  onCancel?: (id: string) => void;
}) {
  return (
    <ul className="transfers">
      {transfers.map((t) => {
        const pct = percent(t.bytesDone, t.bytesTotal);
        const showBar = t.status === "active" || t.status === "waiting";
        return (
          <li className="transfer" key={t.id} data-status={t.status}>
            <span className="transfer__icon">
              <Icon
                name={t.status === "done" ? "check" : t.direction === "send" ? "upload" : "download"}
                size={18}
              />
            </span>
            <div className="transfer__body">
              <div className="transfer__top">
                <strong className="transfer__title">{title(t)}</strong>
                {t.status === "active" && <span className="transfer__pct">{pct}%</span>}
                {showBar && onCancel && (
                  <button
                    className="link transfer__cancel"
                    type="button"
                    onClick={() => onCancel(t.id)}
                    aria-label={`Cancelar: ${title(t)}`}
                  >
                    Cancelar
                  </button>
                )}
              </div>
              <span className="transfer__status">{statusLine(t)}</span>
              {showBar && (
                <div
                  className="progress"
                  role="progressbar"
                  aria-valuemin={0}
                  aria-valuemax={100}
                  aria-valuenow={t.status === "active" ? pct : undefined}
                  aria-label={title(t)}
                  data-indeterminate={t.status === "waiting"}
                >
                  <div
                    className="progress__fill"
                    style={{ transform: `scaleX(${t.status === "active" ? pct / 100 : 0.3})` }}
                  />
                </div>
              )}
            </div>
          </li>
        );
      })}
    </ul>
  );
}
