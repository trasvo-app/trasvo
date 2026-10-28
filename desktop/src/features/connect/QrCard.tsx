// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0.
// If a copy of the MPL was not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

import QRCode from "qrcode";
import { useEffect, useState } from "react";
import type { ConnectionInfo } from "../../ipc/commands";
import { pairingUri } from "./pairingUri";

/** QR + código + IP de esta PC, para conectarse desde el celular. */
export function QrCard({ info }: { info: ConnectionInfo | null }) {
  const [src, setSrc] = useState<string | null>(null);
  const ip = info?.ip;
  const port = info?.port;

  useEffect(() => {
    if (!info || !ip || !port) return;
    let alive = true;
    QRCode.toDataURL(pairingUri({ ...info, ip, port }), {
      margin: 1,
      width: 440,
      color: { dark: "#111113", light: "#ffffff" },
    }).then((url) => alive && setSrc(url));
    return () => {
      alive = false;
    };
  }, [info, ip, port]);

  if (info && !ip) {
    return (
      <div className="notice notice--error">
        Esta PC no está conectada a ninguna red Wi-Fi. Conéctala al mismo Wi-Fi que tu celular.
      </div>
    );
  }
  if (info && !port) {
    return (
      <div className="notice notice--error">
        No se pudo abrir la conexión para recibir archivos. Reinicia la app.
      </div>
    );
  }

  return (
    <div className="qr">
      <div className="qr__frame">
        {src ? (
          <img src={src} alt="Código QR para conectar el celular" />
        ) : (
          <div className="qr__placeholder" />
        )}
      </div>
      <dl className="qr__data">
        <div>
          <dt>Código</dt>
          <dd className="code qr__code">{info?.code ?? "······"}</dd>
        </div>
        <div>
          <dt>IP de esta PC</dt>
          <dd className="code">{ip && port ? `${ip}:${port}` : "…"}</dd>
        </div>
      </dl>
    </div>
  );
}
