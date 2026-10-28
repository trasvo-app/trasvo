// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0.
// If a copy of the MPL was not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

import { Icon } from "../../shared/ui/Icon";
import { PageHeader } from "../../shared/ui/PageHeader";
import { TransferList } from "../transfers/TransferList";
import { useTransfers } from "../transfers/TransfersProvider";
import { ConnectPanel } from "./ConnectPanel";
import { useConnectionInfo } from "./useConnectionInfo";
import "./connect.css";

export function ConnectPage() {
  const info = useConnectionInfo();
  const { list, cancel } = useTransfers();
  const received = list.filter((t) => t.direction === "receive" && t.status !== "offer");

  return (
    <>
      <PageHeader
        title="Conectar"
        subtitle="Enlaza tu celular una vez y pásense archivos en ambos sentidos."
        aside={
          <span className="chip" title={info?.downloadDir}>
            <Icon name="folder" size={14} /> Lo recibido va a {folderName(info?.downloadDir)}
          </span>
        }
      />

      <div className="page-grid">
        <ConnectPanel />

        <section className="card" aria-labelledby="incoming-title">
          <h2 className="card__title" id="incoming-title" style={{ marginBottom: 12 }}>
            Recibidos
          </h2>
          {received.length === 0 ? (
            <>
              <ol className="steps" style={{ marginTop: 0 }}>
                <li>Conecta tu celular (Cerca, QR o IP).</li>
                <li>En el celular, elige fotos o archivos y toca «Enviar».</li>
                <li>Acepta aquí y se guardan en tu carpeta de descargas.</li>
              </ol>
              <p className="field__hint" style={{ marginTop: 12 }}>
                Te preguntaremos antes de guardar nada.
              </p>
            </>
          ) : (
            <TransferList transfers={received} onCancel={cancel} />
          )}
        </section>
      </div>
    </>
  );
}

function folderName(path: string | undefined) {
  if (!path) return "Descargas";
  return path.split(/[\\/]/).filter(Boolean).pop() ?? path;
}
