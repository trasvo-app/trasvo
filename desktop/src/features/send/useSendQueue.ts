// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0.
// If a copy of the MPL was not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

import { isTauri } from "@tauri-apps/api/core";
import { getCurrentWebview } from "@tauri-apps/api/webview";
import { useEffect, useState } from "react";

export type QueueItem = { path: string; kind: "file" | "folder" };

/** Sin extensión → probablemente carpeta (al soltar no sabemos el tipo). */
function guessKind(path: string): QueueItem["kind"] {
  const name = path.split(/[\\/]/).pop() ?? "";
  return /\.[^.]+$/.test(name) ? "file" : "folder";
}

/** Cola de envío: archivos soltados sobre la ventana o elegidos con el selector. */
export function useSendQueue() {
  const [items, setItems] = useState<QueueItem[]>([]);
  const [dragging, setDragging] = useState(false);

  const add = (paths: string[], kind?: QueueItem["kind"]) =>
    setItems((current) => {
      const known = new Set(current.map((i) => i.path));
      const fresh = paths
        .filter((p) => !known.has(p))
        .map((path) => ({ path, kind: kind ?? guessKind(path) }));
      return [...current, ...fresh];
    });

  useEffect(() => {
    // En el navegador (vista previa de diseño) no hay ventana de Tauri.
    if (!isTauri()) return;
    const unlisten = getCurrentWebview().onDragDropEvent((event) => {
      const { type } = event.payload;
      if (type === "enter" || type === "over") setDragging(true);
      if (type === "leave") setDragging(false);
      if (type === "drop") {
        setDragging(false);
        add(event.payload.paths);
      }
    });
    return () => {
      void unlisten.then((fn) => fn());
    };
  }, []);

  const remove = (path: string) =>
    setItems((current) => current.filter((i) => i.path !== path));

  const clear = () => setItems([]);

  return { items, dragging, add, remove, clear };
}
