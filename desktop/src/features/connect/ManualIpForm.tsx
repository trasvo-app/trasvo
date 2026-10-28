// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0.
// If a copy of the MPL was not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

import { useState, type FormEvent } from "react";
import { reasonText } from "../transfers/reasons";
import { useLink } from "./LinkProvider";
import { isValidCode, isValidIpv4, isValidPort } from "./validation";

export function ManualIpForm({ defaultPort }: { defaultPort: number }) {
  const { connect } = useLink();
  const [ip, setIp] = useState("");
  const [port, setPort] = useState(String(defaultPort));
  const [code, setCode] = useState("");
  const [touched, setTouched] = useState(false);
  const [connecting, setConnecting] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const ipOk = isValidIpv4(ip);
  const portOk = isValidPort(port);
  const codeOk = isValidCode(code);

  async function submit(event: FormEvent) {
    event.preventDefault();
    setTouched(true);
    if (!ipOk || !portOk || !codeOk) return;

    setConnecting(true);
    setError(null);
    try {
      // Al conectar, el panel pasa a mostrar el celular enlazado.
      await connect({ ip: ip.trim(), port: Number(port), code });
    } catch (e) {
      setError(reasonText(String(e)));
      setConnecting(false);
    }
  }

  const fieldError = !ipOk ? "invalid_ip" : !portOk ? "invalid_port" : "invalid_code";

  return (
    <form onSubmit={submit} noValidate>
      <div className="field-row">
        <label className="field">
          <span className="field__label">IP del celular</span>
          <input
            className="field__input"
            inputMode="decimal"
            placeholder="192.168.1.20"
            value={ip}
            onChange={(e) => setIp(e.target.value)}
            aria-invalid={touched && !ipOk}
          />
        </label>
        <label className="field">
          <span className="field__label">Puerto</span>
          <input
            className="field__input"
            inputMode="numeric"
            value={port}
            onChange={(e) => setPort(e.target.value.replace(/\D/g, ""))}
            aria-invalid={touched && !portOk}
          />
        </label>
      </div>

      <label className="field">
        <span className="field__label">Código que muestra el celular</span>
        <input
          className="field__input code"
          inputMode="numeric"
          maxLength={6}
          placeholder="000000"
          value={code}
          onChange={(e) => setCode(e.target.value.replace(/\D/g, ""))}
          aria-invalid={touched && !codeOk}
        />
        <span className="field__hint">Lo ves en el inicio de la app del celular.</span>
      </label>

      {touched && (!ipOk || !portOk || !codeOk) && (
        <p className="notice notice--error" role="alert">
          {reasonText(fieldError)}
        </p>
      )}
      {error && (
        <p className="notice notice--error" role="alert">
          {error}
        </p>
      )}

      <button className="btn btn--primary btn--block" type="submit" disabled={connecting}>
        {connecting ? "Conectando…" : "Conectar"}
      </button>
    </form>
  );
}
