// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0.
// If a copy of the MPL was not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

//! Enlace persistente entre dos motores reales por TCP en localhost.

use std::fs;
use std::net::SocketAddr;
use std::path::Path;
use std::time::Duration;

use ft_transfer::{
    new_transfer_id, Direction, Engine, EngineConfig, Event, LinkStatus, TransferError,
};
use tokio::sync::mpsc;
use tokio::time::timeout;

/// Motor escuchando en localhost que acepta todas las ofertas. Si `approve` es
/// `Some`, responde así a las peticiones de conexión sin código.
struct Device {
    engine: Engine,
    addr: SocketAddr,
    events: mpsc::UnboundedReceiver<Event>,
    _dir: tempfile::TempDir,
}

impl Device {
    async fn new(name: &str, code: &str, approve: Option<bool>) -> Self {
        let dir = tempfile::tempdir().unwrap();
        let (tx, mut raw) = mpsc::unbounded_channel();
        let config = EngineConfig {
            device_id: format!("{name}-id"),
            device_name: name.to_owned(),
            code: code.to_owned(),
            download_dir: dir.path().to_path_buf(),
        };
        let engine = Engine::new(config, tx);
        let addr = engine.listen("127.0.0.1:0".parse().unwrap()).await.unwrap();

        let (out, events) = mpsc::unbounded_channel();
        let responder = engine.clone();
        tokio::spawn(async move {
            while let Some(event) = raw.recv().await {
                match &event {
                    Event::Offer { transfer_id, .. } => {
                        responder.respond(transfer_id, true);
                    }
                    Event::LinkRequest { request_id, .. } => {
                        if let Some(accept) = approve {
                            responder.respond(request_id, accept);
                        }
                    }
                    _ => {}
                }
                let _ = out.send(event);
            }
        });
        Self { engine, addr, events, _dir: dir }
    }

    fn dir(&self) -> std::path::PathBuf {
        self.engine.download_dir()
    }

    /// Espera el siguiente cambio de enlace.
    async fn next_link(&mut self) -> (LinkStatus, Option<String>) {
        let wait = timeout(Duration::from_secs(10), async {
            loop {
                if let Event::Link { status, peer } = self.events.recv().await.unwrap() {
                    return (status, peer.map(|p| p.name));
                }
            }
        });
        wait.await.expect("no llegó el cambio de enlace")
    }

    async fn received(&mut self) -> Vec<String> {
        let wait = timeout(Duration::from_secs(10), async {
            loop {
                match self.events.recv().await.unwrap() {
                    Event::Completed { direction: Direction::Receive, files, .. } => return files,
                    Event::Failed { reason, .. } => panic!("falló: {reason}"),
                    _ => {}
                }
            }
        });
        wait.await.expect("no llegó la transferencia")
    }
}

fn file(dir: &Path, name: &str, body: &[u8]) -> std::path::PathBuf {
    let path = dir.join(name);
    fs::write(&path, body).unwrap();
    path
}

#[tokio::test(flavor = "multi_thread")]
async fn one_pairing_allows_sending_both_ways_many_times() {
    let mut phone = Device::new("Celular", "111111", None).await;
    let mut pc = Device::new("PC", "222222", None).await;

    // El celular escanea el QR de la PC: se enlazan una sola vez.
    assert_eq!(phone.engine.link(pc.addr, "222222").await.unwrap(), "PC");
    assert_eq!(phone.next_link().await, (LinkStatus::Connected, Some("PC".into())));
    assert_eq!(pc.next_link().await, (LinkStatus::Connected, Some("Celular".into())));

    let src = tempfile::tempdir().unwrap();
    // PC → celular sin escribir IP ni código, dos veces seguidas.
    for round in 0..2 {
        let name = format!("a{round}.txt");
        let path = file(src.path(), &name, b"desde la PC");
        pc.engine.send_linked(new_transfer_id(), vec![path]).await.unwrap();
        phone.received().await;
        assert_eq!(fs::read(phone.dir().join(&name)).unwrap(), b"desde la PC");
    }
    // Celular → PC por el mismo enlace.
    let path = file(src.path(), "b.txt", b"desde el celular");
    phone.engine.send_linked(new_transfer_id(), vec![path]).await.unwrap();
    pc.received().await;
    assert_eq!(fs::read(pc.dir().join("b.txt")).unwrap(), b"desde el celular");

    // Sigue conectado después de enviar.
    assert_eq!(pc.engine.link_state().0, LinkStatus::Connected);
    assert_eq!(phone.engine.link_state().0, LinkStatus::Connected);
}

#[tokio::test(flavor = "multi_thread")]
async fn disconnecting_on_one_side_disconnects_both() {
    let mut phone = Device::new("Celular", "111111", None).await;
    let mut pc = Device::new("PC", "222222", None).await;
    pc.engine.link(phone.addr, "111111").await.unwrap();
    phone.next_link().await;
    pc.next_link().await;

    // Desconecta el que NO abrió el enlace.
    phone.engine.unlink();
    assert_eq!(phone.next_link().await, (LinkStatus::Disconnected, None));
    assert_eq!(pc.next_link().await, (LinkStatus::Disconnected, None));

    let src = tempfile::tempdir().unwrap();
    let path = file(src.path(), "a.txt", b"a");
    let error = pc.engine.send_linked(new_transfer_id(), vec![path]).await.unwrap_err();
    assert!(matches!(error, TransferError::NotConnected), "{error:?}");
}

#[tokio::test(flavor = "multi_thread")]
async fn old_link_token_stops_working_after_disconnect() {
    let mut phone = Device::new("Celular", "111111", None).await;
    let mut pc = Device::new("PC", "222222", None).await;
    phone.engine.link(pc.addr, "222222").await.unwrap();
    pc.next_link().await;
    phone.next_link().await;

    pc.engine.unlink();
    pc.next_link().await;
    phone.next_link().await;

    // Un token cualquiera de 32 caracteres tampoco sirve, ni bloquea el código real.
    let src = tempfile::tempdir().unwrap();
    let path = file(src.path(), "a.txt", b"a");
    for _ in 0..12 {
        let token = "0".repeat(32);
        let error = phone.engine.send(new_transfer_id(), pc.addr, token, vec![path.clone()]).await;
        assert!(matches!(error, Err(TransferError::WrongCode)));
    }
    assert_eq!(phone.engine.check_pairing(pc.addr, "222222").await.unwrap(), "PC");
}

#[tokio::test(flavor = "multi_thread")]
async fn nearby_device_connects_when_the_other_user_accepts() {
    let mut phone = Device::new("Celular", "111111", Some(true)).await;
    let mut pc = Device::new("PC", "222222", None).await;

    assert_eq!(pc.engine.link_nearby(phone.addr).await.unwrap(), "Celular");
    assert_eq!(phone.next_link().await, (LinkStatus::Connected, Some("PC".into())));
    assert_eq!(pc.next_link().await.0, LinkStatus::Connected);
}

#[tokio::test(flavor = "multi_thread")]
async fn nearby_device_is_rejected_when_the_other_user_declines() {
    let phone = Device::new("Celular", "111111", Some(false)).await;
    let pc = Device::new("PC", "222222", None).await;

    let error = pc.engine.link_nearby(phone.addr).await.unwrap_err();
    assert_eq!(error.code(), "declined");
    assert_eq!(phone.engine.link_state().0, LinkStatus::Disconnected);
    assert_eq!(pc.engine.link_state().0, LinkStatus::Disconnected);
}

#[tokio::test(flavor = "multi_thread")]
async fn approval_without_code_cannot_send_files_directly() {
    let phone = Device::new("Celular", "111111", Some(true)).await;
    let src = tempfile::tempdir().unwrap();
    let path = file(src.path(), "a.txt", b"a");
    let pc = Device::new("PC", "222222", None).await;

    // Pedir permiso solo sirve para enlazarse, no para mandar una oferta suelta.
    let result = pc.engine.send(new_transfer_id(), phone.addr, String::new(), vec![path]).await;
    assert!(result.is_err());
    assert!(fs::read_dir(phone.dir()).unwrap().next().is_none());
}

#[tokio::test(flavor = "multi_thread")]
async fn a_new_link_replaces_the_previous_one() {
    let mut pc = Device::new("PC", "222222", None).await;
    let mut phone1 = Device::new("Celular 1", "111111", None).await;
    let phone2 = Device::new("Celular 2", "333333", None).await;

    phone1.engine.link(pc.addr, "222222").await.unwrap();
    phone1.next_link().await;
    pc.next_link().await;

    phone2.engine.link(pc.addr, "222222").await.unwrap();
    assert_eq!(pc.next_link().await, (LinkStatus::Connected, Some("Celular 2".into())));
    // El primero se entera de que quedó desconectado.
    assert_eq!(phone1.next_link().await, (LinkStatus::Disconnected, None));
}

#[tokio::test(flavor = "multi_thread")]
async fn download_folder_can_change_at_runtime() {
    let mut pc = Device::new("PC", "222222", None).await;
    let phone = Device::new("Celular", "111111", None).await;
    phone.engine.link(pc.addr, "222222").await.unwrap();

    let other = tempfile::tempdir().unwrap();
    pc.engine.set_download_dir(other.path().to_path_buf());
    let src = tempfile::tempdir().unwrap();
    let path = file(src.path(), "a.txt", b"a");
    phone.engine.send_linked(new_transfer_id(), vec![path]).await.unwrap();
    pc.received().await;
    assert_eq!(fs::read(other.path().join("a.txt")).unwrap(), b"a");
}
