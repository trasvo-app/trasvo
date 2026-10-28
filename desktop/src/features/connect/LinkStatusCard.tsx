// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0.
// If a copy of the MPL was not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

import { Icon } from "../../shared/ui/Icon";
import { useLink } from "./LinkProvider";
import "./connect.css";

/** Celular enlazado (o reconectando) con el botón para desconectar en ambos lados. */
export function LinkStatusCard() {
  const { peer, status, disconnect } = useLink();
  if (!peer) return null;
  const reconnecting = status === "reconnecting";

  return (
    <div className="connected" data-reconnecting={reconnecting}>
      <span className="connected__icon">
        <Icon name={reconnecting ? "wifi" : "check"} size={20} />
      </span>
      <div className="connected__text">
        <strong>Conectado con {peer.name}</strong>
        <span>
          {reconnecting
            ? "Se cortó la red. Reconectando…"
            : "Pueden enviarse archivos en ambos sentidos"}
        </span>
      </div>
      <button className="btn btn--secondary" type="button" onClick={() => void disconnect()}>
        Desconectar
      </button>
    </div>
  );
}
