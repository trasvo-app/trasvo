// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0.
// If a copy of the MPL was not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

//! Enlace persistente: una vez emparejados (desde cualquiera de los dos lados), quedan
//! conectados y se envían archivos en ambos sentidos sin volver a emparejar, hasta que
//! alguno toca «Desconectar». Ver docs/protocol.md.

use std::net::SocketAddr;
use std::sync::atomic::Ordering;
use std::sync::Arc;
use std::time::Duration;

use ft_protocol::{Frame, Message};
use rand::RngCore;
use serde::Serialize;
use tokio::sync::watch;
use tokio::time::{interval, sleep, timeout, Instant, MissedTickBehavior};

use crate::codec::{read_frame_opt, read_message, send};
use crate::session::{connect, same_code, Reader, Writer};
use crate::{AbortOnDrop, Event, Inner, TransferError, HANDSHAKE_TIMEOUT, PROMPT_TIMEOUT};

/// Cada cuánto se manda `ping` por el enlace.
pub const PING_INTERVAL: Duration = Duration::from_secs(10);
/// Sin noticias del otro lado durante este tiempo, el enlace se da por cortado.
pub const LINK_TIMEOUT: Duration = Duration::from_secs(40);
const RECONNECT_EVERY: Duration = Duration::from_secs(3);
/// Tras un corte, cuánto tiempo se intenta (o se espera) reconectar.
pub const RESUME_WINDOW: Duration = Duration::from_secs(10 * 60);
/// Longitud del token de sesión en hexadecimal (128 bits).
pub(crate) const TOKEN_LEN: usize = 32;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
#[serde(rename_all = "lowercase")]
pub enum LinkStatus {
    Connected,
    /// Se cortó la red: se reintenta solo, sin pedir nada al usuario.
    Reconnecting,
    Disconnected,
}

/// El otro dispositivo del enlace, tal como lo ve la interfaz.
#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Peer {
    pub name: String,
    pub ip: String,
    pub port: u16,
}

pub(crate) struct Link {
    token: String,
    peer_name: String,
    /// Dónde escucha el otro lado: ahí se conectan los envíos.
    addr: SocketAddr,
    /// Quien abrió el enlace es quien reconecta si se corta.
    initiator: bool,
    status: LinkStatus,
    /// Para detener la tarea del enlace (y avisar `link_close` al otro lado).
    stop: Option<watch::Sender<bool>>,
}

impl Link {
    fn new(token: String, peer_name: String, addr: SocketAddr, initiator: bool) -> Self {
        Self { token, peer_name, addr, initiator, status: LinkStatus::Connected, stop: None }
    }

    fn peer(&self) -> Peer {
        Peer { name: self.peer_name.clone(), ip: self.addr.ip().to_string(), port: self.addr.port() }
    }

    fn stop(&self) {
        if let Some(stop) = &self.stop {
            let _ = stop.send(true);
        }
    }
}

/// Enlace actual. `epoch` cambia con cada enlace nuevo o cierre, para que las tareas
/// de un enlace viejo no toquen al nuevo.
#[derive(Default)]
pub(crate) struct Slot {
    current: Option<Link>,
    epoch: u64,
}

impl Slot {
    fn state(&self) -> (LinkStatus, Option<Peer>) {
        match &self.current {
            Some(link) => (link.status, Some(link.peer())),
            None => (LinkStatus::Disconnected, None),
        }
    }
}

fn emit_state(inner: &Inner, slot: &Slot) {
    let (status, peer) = slot.state();
    inner.emit(Event::Link { status, peer });
}

pub(crate) fn new_token() -> String {
    let mut bytes = [0u8; TOKEN_LEN / 2];
    rand::thread_rng().fill_bytes(&mut bytes);
    bytes.iter().map(|b| format!("{b:02x}")).collect()
}

pub(crate) fn state(inner: &Inner) -> (LinkStatus, Option<Peer>) {
    inner.link.lock().unwrap().state()
}

/// Dirección y token para enviar al otro lado, si hay enlace (aunque esté reconectando).
pub(crate) fn target(inner: &Inner) -> Option<(SocketAddr, String)> {
    let slot = inner.link.lock().unwrap();
    slot.current.as_ref().map(|link| (link.addr, link.token.clone()))
}

pub(crate) fn is_session_token(inner: &Inner, token: &str) -> bool {
    let slot = inner.link.lock().unwrap();
    slot.current.as_ref().is_some_and(|link| same_code(&link.token, token))
}

/// Abre un enlace con `addr`. `pair_token` es su código, o vacío para pedirle permiso
/// al usuario del otro lado (dispositivos encontrados en la red). Devuelve su nombre.
pub(crate) async fn open(
    inner: &Arc<Inner>,
    addr: SocketAddr,
    pair_token: &str,
) -> Result<String, TransferError> {
    let token = new_token();
    let (r, w, peer_name) = handshake(inner, addr, pair_token, &token).await?;
    install(inner, Link::new(token, peer_name.clone(), addr, true), r, w, None);
    Ok(peer_name)
}

async fn handshake(
    inner: &Inner,
    addr: SocketAddr,
    pair_token: &str,
    link_token: &str,
) -> Result<(Reader, Writer, String), TransferError> {
    // Pedir permiso espera a que el usuario del otro lado responda.
    let wait = if pair_token.is_empty() {
        PROMPT_TIMEOUT + Duration::from_secs(10)
    } else {
        HANDSHAKE_TIMEOUT
    };
    let (mut r, mut w, peer_name) = connect(inner, addr, pair_token, wait).await?;
    let port = inner.port.load(Ordering::Relaxed);
    send(&mut w, Message::LinkOpen { token: link_token.to_owned(), port }).await?;
    match timeout(HANDSHAKE_TIMEOUT, read_message(&mut r)).await.map_err(|_| TransferError::Timeout)?? {
        Message::LinkAccept => Ok((r, w, peer_name)),
        _ => Err(TransferError::Unexpected),
    }
}

/// Lado que recibió `link_open` (el emparejamiento ya se aceptó).
pub(crate) async fn accept(
    inner: Arc<Inner>,
    r: Reader,
    mut w: Writer,
    peer_name: String,
    addr: SocketAddr,
    token: String,
) -> Result<(), TransferError> {
    if token.len() != TOKEN_LEN {
        return Err(TransferError::Unexpected);
    }
    send(&mut w, Message::LinkAccept).await?;
    install(&inner, Link::new(token, peer_name, addr, false), r, w, None);
    Ok(())
}

/// Reemplaza el enlace actual (avisando al anterior) y arranca su tarea.
/// Con `expect_epoch`, no hace nada si el enlace cambió mientras tanto.
fn install(inner: &Arc<Inner>, mut link: Link, r: Reader, w: Writer, expect_epoch: Option<u64>) {
    let (stop_tx, stop_rx) = watch::channel(false);
    link.stop = Some(stop_tx);
    let epoch = {
        let mut slot = inner.link.lock().unwrap();
        if expect_epoch.is_some_and(|e| e != slot.epoch) {
            return;
        }
        if let Some(old) = slot.current.take() {
            old.stop();
        }
        slot.epoch += 1;
        slot.current = Some(link);
        emit_state(inner, &slot);
        slot.epoch
    };
    tokio::spawn(run(inner.clone(), r, w, epoch, stop_rx));
}

/// Cierre pedido por el usuario: avisa al otro lado.
pub(crate) fn close_by_user(inner: &Inner) {
    let mut slot = inner.link.lock().unwrap();
    if let Some(link) = slot.current.take() {
        link.stop();
        slot.epoch += 1;
        emit_state(inner, &slot);
    }
}

fn clear(inner: &Inner, epoch: u64) {
    let mut slot = inner.link.lock().unwrap();
    if slot.epoch == epoch && slot.current.is_some() {
        slot.current = None;
        slot.epoch += 1;
        emit_state(inner, &slot);
    }
}

enum End {
    /// Lo cerramos nosotros (usuario o reemplazo): quien lo cerró ya actualizó el estado.
    Stopped,
    /// El otro lado mandó `link_close`.
    Closed,
    /// Se cortó la conexión o dejó de responder.
    Lost,
}

async fn run(
    inner: Arc<Inner>,
    r: Reader,
    mut w: Writer,
    epoch: u64,
    mut stop: watch::Receiver<bool>,
) {
    let mut reader = AbortOnDrop(tokio::spawn(watch_peer(r)));
    let mut ping = interval(PING_INTERVAL);
    ping.set_missed_tick_behavior(MissedTickBehavior::Delay);
    ping.tick().await;

    let end = loop {
        tokio::select! {
            end = &mut reader.0 => break end.unwrap_or(End::Lost),
            _ = ping.tick() => {
                if send(&mut w, Message::Ping).await.is_err() {
                    break End::Lost;
                }
            }
            // Envuelto para no retener el `Ref` del watch (no es `Send`).
            () = async { let _ = stop.wait_for(|stopped| *stopped).await; } => {
                let _ = send(&mut w, Message::LinkClose).await;
                break End::Stopped;
            }
        }
    };
    drop(reader);
    match end {
        End::Stopped => {}
        End::Closed => clear(&inner, epoch),
        End::Lost => lost(&inner, epoch),
    }
}

/// Lee el enlace hasta que se cierra. Solo espera `ping` y `link_close`.
async fn watch_peer(mut r: Reader) -> End {
    loop {
        match timeout(LINK_TIMEOUT, read_frame_opt(&mut r)).await {
            Ok(Ok(Some(Frame::Control(Message::Ping)))) => {}
            Ok(Ok(Some(Frame::Control(Message::LinkClose)))) => return End::Closed,
            _ => return End::Lost,
        }
    }
}

fn lost(inner: &Arc<Inner>, epoch: u64) {
    let (initiator, addr, token) = {
        let mut slot = inner.link.lock().unwrap();
        if slot.epoch != epoch {
            return;
        }
        let Some(link) = slot.current.as_mut() else { return };
        link.status = LinkStatus::Reconnecting;
        link.stop = None;
        let resume = (link.initiator, link.addr, link.token.clone());
        emit_state(inner, &slot);
        resume
    };
    let inner = inner.clone();
    tokio::spawn(async move {
        if initiator {
            reconnect(&inner, epoch, addr, &token).await;
        } else {
            // El otro lado es quien reconecta; si no vuelve a tiempo, se cierra.
            sleep(RESUME_WINDOW).await;
            clear(&inner, epoch);
        }
    });
}

async fn reconnect(inner: &Arc<Inner>, epoch: u64, addr: SocketAddr, token: &str) {
    let deadline = Instant::now() + RESUME_WINDOW;
    while Instant::now() < deadline {
        sleep(RECONNECT_EVERY).await;
        if inner.link.lock().unwrap().epoch != epoch {
            return;
        }
        match handshake(inner, addr, token, token).await {
            Ok((r, w, peer_name)) => {
                let link = Link::new(token.to_owned(), peer_name, addr, true);
                install(inner, link, r, w, Some(epoch));
                return;
            }
            // El otro lado ya no reconoce el enlace (lo cerró o se reinició).
            Err(TransferError::WrongCode | TransferError::Rejected(_)) => break,
            Err(_) => {}
        }
    }
    clear(inner, epoch);
}
