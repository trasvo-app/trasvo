// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0.
// If a copy of the MPL was not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

import { useEffect, useRef, useState } from "react";
import { ConnectPage } from "../features/connect/ConnectPage";
import { LinkRequestDialog } from "../features/connect/LinkRequestDialog";
import { useLink } from "../features/connect/LinkProvider";
import { HistoryPage } from "../features/history/HistoryPage";
import { ThemeChoice } from "../features/onboarding/ThemeChoice";
import { SendPage } from "../features/send/SendPage";
import { SettingsPage } from "../features/settings/SettingsPage";
import { IncomingOfferDialog } from "../features/transfers/IncomingOfferDialog";
import { useTheme } from "../shared/theme/ThemeProvider";
import type { PageProps, RouteId } from "./routes";
import { Sidebar } from "./Sidebar";

const pages: Record<RouteId, (props: PageProps) => React.JSX.Element> = {
  connect: ConnectPage,
  send: SendPage,
  history: HistoryPage,
  settings: SettingsPage,
};

export function App() {
  const [route, setRoute] = useState<RouteId>("connect");
  const { chosen } = useTheme();
  const { peer } = useLink();
  const Page = pages[route];

  // Al enlazarse estando en «Conectar», lo siguiente es elegir qué enviar.
  const wasLinked = useRef(false);
  useEffect(() => {
    const linked = peer !== null;
    if (linked && !wasLinked.current && route === "connect") setRoute("send");
    wasLinked.current = linked;
  }, [peer, route]);

  return (
    <>
      <div className="layout" inert={!chosen}>
        <Sidebar current={route} onNavigate={setRoute} />
        <main className="main">
          <Page navigate={setRoute} />
        </main>
      </div>
      {chosen ? (
        <>
          <IncomingOfferDialog />
          <LinkRequestDialog />
        </>
      ) : (
        <ThemeChoice />
      )}
    </>
  );
}
