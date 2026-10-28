// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0.
// If a copy of the MPL was not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

import logo from "../assets/trasvo-icon.svg";
import { useLink } from "../features/connect/LinkProvider";
import { useConnectionInfo } from "../features/connect/useConnectionInfo";
import { Icon } from "../shared/ui/Icon";
import { routes, type RouteId } from "./routes";

export function Sidebar({
  current,
  onNavigate,
}: {
  current: RouteId;
  onNavigate: (id: RouteId) => void;
}) {
  const info = useConnectionInfo();
  const link = useLink();

  return (
    <aside className="sidebar">
      <div className="brand">
        <img className="brand__logo" src={logo} alt="" width={36} height={36} />
        <span className="brand__name">Trasvo</span>
      </div>

      <nav aria-label="Principal">
        {routes.map((route) => (
          <button
            key={route.id}
            type="button"
            className="nav__item"
            aria-current={current === route.id ? "page" : undefined}
            onClick={() => onNavigate(route.id)}
            title={route.label}
          >
            <Icon name={route.icon} />
            <span className="nav__label">{route.label}</span>
          </button>
        ))}
      </nav>

      <div className="sidebar__footer">
        <strong>{info?.deviceName ?? "Esta PC"}</strong>
        <span>{info?.ip ? `${info.ip}:${info.port ?? "…"}` : "Sin conexión Wi-Fi"}</span>
        <span className="sidebar__link" data-status={link.status}>
          <span className="dot" />
          {link.peer
            ? link.status === "reconnecting"
              ? `Reconectando con ${link.peer.name}…`
              : `Conectado con ${link.peer.name}`
            : "Ningún celular conectado"}
        </span>
      </div>
    </aside>
  );
}
