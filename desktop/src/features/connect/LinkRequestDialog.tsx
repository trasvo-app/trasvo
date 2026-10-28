// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0.
// If a copy of the MPL was not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

import { useEffect, useRef } from "react";
import { Icon } from "../../shared/ui/Icon";
import { useLink } from "./LinkProvider";
import "../transfers/transfers.css";

/** Aparece en cualquier pantalla cuando un celular cercano pide conectarse. */
export function LinkRequestDialog() {
  const { request, answer } = useLink();
  const acceptRef = useRef<HTMLButtonElement>(null);

  useEffect(() => {
    acceptRef.current?.focus();
  }, [request?.id]);

  if (!request) return null;

  return (
    <div className="offer-backdrop">
      <div className="offer" role="alertdialog" aria-modal="true" aria-labelledby="link-request-title">
        <span className="dropzone__icon">
          <Icon name="phone" size={26} />
        </span>
        <div>
          <h2 id="link-request-title">{request.peerName} quiere conectarse</h2>
          <p className="card__subtitle" style={{ margin: "4px 0 0" }}>
            Si aceptas, podrán enviarse archivos en ambos sentidos hasta que alguno toque
            «Desconectar». Acepta solo si es tu celular.
          </p>
        </div>
        <div className="offer__actions">
          <button className="btn btn--secondary" type="button" onClick={() => void answer(false)}>
            Rechazar
          </button>
          <button
            ref={acceptRef}
            className="btn btn--primary"
            type="button"
            onClick={() => void answer(true)}
          >
            Aceptar
          </button>
        </div>
      </div>
    </div>
  );
}
