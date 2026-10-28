// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0.
// If a copy of the MPL was not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

import type { IconName } from "../shared/ui/Icon";

export type RouteId = "connect" | "send" | "history" | "settings";

export const routes: { id: RouteId; label: string; icon: IconName }[] = [
  { id: "connect", label: "Conectar", icon: "wifi" },
  { id: "send", label: "Enviar", icon: "upload" },
  { id: "history", label: "Historial", icon: "history" },
  { id: "settings", label: "Ajustes", icon: "settings" },
];

/** Las páginas reciben cómo navegar a otra (p. ej. «Conectar» desde «Enviar»). */
export type PageProps = { navigate: (id: RouteId) => void };
