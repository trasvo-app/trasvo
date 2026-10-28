// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0.
// If a copy of the MPL was not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

import { createContext, useContext, useEffect, useReducer, type ReactNode } from "react";
import { commands } from "../../ipc/commands";
import { isLinkEvent, onEngineEvent } from "../../ipc/events";
import { loadHistory, saveHistory } from "./historyStore";
import { transfersReducer, type Transfer, type TransfersState } from "./transfersReducer";

type TransfersContextValue = TransfersState & {
  list: Transfer[];
  /** Empieza a enviar al dispositivo enlazado. Lanza el código de error si el backend
   *  lo rechaza de entrada. */
  startSend: (peerName: string, paths: string[]) => Promise<void>;
  respond: (id: string, accept: boolean) => Promise<void>;
  cancel: (id: string) => Promise<void>;
};

const TransfersContext = createContext<TransfersContextValue | null>(null);

/** Vive arriba de todo para no perder eventos al cambiar de pantalla. */
export function TransfersProvider({ children }: { children: ReactNode }) {
  const [state, dispatch] = useReducer(transfersReducer, undefined, () => loadHistory());

  useEffect(
    () =>
      onEngineEvent((event) => {
        if (!isLinkEvent(event)) dispatch({ type: "event", event, now: Date.now() });
      }),
    [],
  );

  useEffect(() => saveHistory(state), [state]);

  const startSend = async (peerName: string, paths: string[]) => {
    const id = await commands.sendFiles(paths);
    dispatch({ type: "started", id, peerName, fileCount: paths.length, now: Date.now() });
  };

  const respond = async (id: string, accept: boolean) => {
    dispatch({ type: "responded", id, accept, now: Date.now() });
    await commands.respondOffer(id, accept);
  };

  // El estado final llega del motor como evento `failed` con motivo `cancelled`.
  const cancel = async (id: string) => {
    await commands.cancelTransfer(id);
  };

  const list = state.order.map((id) => state.byId[id]);

  return (
    <TransfersContext.Provider value={{ ...state, list, startSend, respond, cancel }}>
      {children}
    </TransfersContext.Provider>
  );
}

export function useTransfers() {
  const value = useContext(TransfersContext);
  if (!value) throw new Error("useTransfers must be used inside TransfersProvider");
  return value;
}
