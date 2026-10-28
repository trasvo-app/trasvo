// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0.
// If a copy of the MPL was not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

import type { ReactNode } from "react";

export function PageHeader({
  title,
  subtitle,
  aside,
}: {
  title: string;
  subtitle: string;
  aside?: ReactNode;
}) {
  return (
    <header className="page-header">
      <div>
        <h1>{title}</h1>
        <p>{subtitle}</p>
      </div>
      {aside}
    </header>
  );
}
