// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0.
// If a copy of the MPL was not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

import { createContext, useContext, useEffect, useReducer, type ReactNode } from "react";
import { isTauri } from "@tauri-apps/api/core";
import { commands, type Target } from "../../ipc/commands";
import { isLinkEvent, onEngineEvent, onNearbyDevices, type NearbyDevice } from "../../ipc/events";
import { initialLink, linkReducer, type LinkState } from "./linkReducer";

type LinkContextValue = LinkState & {
  /** Se enlaza con IP y código. Lanza el código de error si falla. */
  connect: (target: Target) => Promise<void>;
  /** Se enlaza con un dispositivo cercano; el otro lado tiene que aceptar. */
  connectNearby: (device: NearbyDevice) => Promise<void>;
  disconnect: () => Promise<void>;
  /** Respuesta a una petición de conexión sin código. */
  answer: (accept: boolean) => Promise<void>;
};

const LinkContext = createContext<LinkContextValue | null>(null);

/** Enlace con el celular: vive arriba de todo para no perderlo al cambiar de pantalla. */
export function LinkProvider({ children }: { children: ReactNode }) {
  const [state, dispatch] = useReducer(linkReducer, initialLink);

  useEffect(() => {
    const offEngine = onEngineEvent((event) => {
      if (isLinkEvent(event)) dispatch({ type: "event", event });
    });
    const offNearby = onNearbyDevices((devices) => dispatch({ type: "nearby", devices }));
    if (isTauri()) {
      void commands.linkState().then((v) => dispatch({ type: "loaded", ...v }));
      void commands.nearbyDevices().then((devices) => dispatch({ type: "nearby", devices }));
    }
    return () => {
      offEngine();
      offNearby();
    };
  }, []);

  // El estado nuevo llega como evento `link`.
  const connect = async (target: Target) => {
    await commands.connect(target);
  };

  const connectNearby = async (device: NearbyDevice) => {
    await commands.connectNearby(device);
  };

  const disconnect = () => commands.disconnect();

  const answer = async (accept: boolean) => {
    const request = state.request;
    if (!request) return;
    dispatch({ type: "answered" });
    await commands.respondOffer(request.id, accept);
  };

  return (
    <LinkContext.Provider value={{ ...state, connect, connectNearby, disconnect, answer }}>
      {children}
    </LinkContext.Provider>
  );
}

export function useLink() {
  const value = useContext(LinkContext);
  if (!value) throw new Error("useLink must be used inside LinkProvider");
  return value;
}
