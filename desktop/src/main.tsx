// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0.
// If a copy of the MPL was not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

import React from "react";
import ReactDOM from "react-dom/client";
import { App } from "./app/App";
import { LinkProvider } from "./features/connect/LinkProvider";
import { TransfersProvider } from "./features/transfers/TransfersProvider";
import { ThemeProvider } from "./shared/theme/ThemeProvider";
import { applyTheme, loadTheme, systemTheme } from "./shared/theme/theme";
import "./shared/styles/tokens.css";
import "./shared/ui/ui.css";
import "./app/app.css";

// Antes del primer render, para que no parpadee el tema equivocado.
applyTheme(loadTheme() ?? systemTheme());

ReactDOM.createRoot(document.getElementById("root") as HTMLElement).render(
  <React.StrictMode>
    <ThemeProvider>
      <LinkProvider>
        <TransfersProvider>
          <App />
        </TransfersProvider>
      </LinkProvider>
    </ThemeProvider>
  </React.StrictMode>,
);
