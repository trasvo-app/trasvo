// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0.
// If a copy of the MPL was not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

import { useEffect, useRef } from "react";
import { formatBytes, plural } from "../../shared/format";
import { Icon } from "../../shared/ui/Icon";
import { useTransfers } from "./TransfersProvider";
import "./transfers.css";

const MAX_LISTED = 6;

/** Aparece en cualquier pantalla cuando alguien quiere enviarnos archivos. */
export function IncomingOfferDialog() {
  const { list, respond } = useTransfers();
  // La más vieja primero: se responden en el orden en que llegaron.
  const offer = [...list].reverse().find((t) => t.status === "offer");
  const acceptRef = useRef<HTMLButtonElement>(null);

  useEffect(() => {
    acceptRef.current?.focus();
  }, [offer?.id]);

  if (!offer) return null;
  const extra = offer.files.length - MAX_LISTED;

  return (
    <div className="offer-backdrop">
      <div className="offer" role="alertdialog" aria-modal="true" aria-labelledby="offer-title">
        <span className="dropzone__icon">
          <Icon name="download" size={26} />
        </span>
        <div>
          <h2 id="offer-title">{offer.peerName} quiere enviarte archivos</h2>
          <p className="card__subtitle" style={{ margin: "4px 0 0" }}>
            {plural(offer.fileCount, "archivo", "archivos")} · {formatBytes(offer.bytesTotal)}
          </p>
        </div>
        <ul className="offer__files">
          {offer.files.slice(0, MAX_LISTED).map((name) => (
            <li key={name}>
              <Icon name="file" size={16} />
              {name}
            </li>
          ))}
          {extra > 0 && <li>y {plural(extra, "archivo más", "archivos más")}</li>}
        </ul>
        <div className="offer__actions">
          <button className="btn btn--secondary" type="button" onClick={() => respond(offer.id, false)}>
            Rechazar
          </button>
          <button
            ref={acceptRef}
            className="btn btn--primary"
            type="button"
            onClick={() => respond(offer.id, true)}
          >
            Aceptar
          </button>
        </div>
      </div>
    </div>
  );
}
