// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0.
// If a copy of the MPL was not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

import { Icon } from "../../shared/ui/Icon";
import { PageHeader } from "../../shared/ui/PageHeader";
import { TransferList } from "../transfers/TransferList";
import { useTransfers } from "../transfers/TransfersProvider";
import { isFinished } from "../transfers/transfersReducer";

export function HistoryPage() {
  const { list } = useTransfers();
  const finished = list.filter(isFinished);

  return (
    <>
      <PageHeader title="Historial" subtitle="Lo que enviaste y recibiste en esta PC." />
      <section className="card">
        {finished.length === 0 ? (
          <div className="empty">
            <span className="empty__icon">
              <Icon name="history" />
            </span>
            <strong style={{ color: "var(--color-text)" }}>Aún no hay transferencias</strong>
            Cuando envíes o recibas archivos, aparecerán aquí.
          </div>
        ) : (
          <TransferList transfers={finished} />
        )}
      </section>
    </>
  );
}
