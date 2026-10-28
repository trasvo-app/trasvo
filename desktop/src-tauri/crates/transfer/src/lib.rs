// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0.
// If a copy of the MPL was not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

//! Motor de transferencia: servidor que recibe, cliente que envía, y eventos
//! de progreso para la interfaz. Habla el protocolo de `ft-protocol` sobre TCP.

mod codec;
mod error;
pub mod files;
mod link;
mod receive;
mod send;
mod session;

use std::collections::HashMap;
use std::io;
use std::net::SocketAddr;
use std::path::PathBuf;
use std::sync::atomic::{AtomicBool, AtomicU16, AtomicU32, Ordering};
use std::sync::{Arc, Mutex};
use std::time::Duration;

use ft_protocol::FileInfo;
use rand::RngCore;
use serde::Serialize;
use tokio::net::TcpListener;
use tokio::sync::{mpsc, oneshot, watch};
use tokio::task::JoinHandle;

pub use error::TransferError;
pub use link::{LinkStatus, Peer, LINK_TIMEOUT, PING_INTERVAL, RESUME_WINDOW};

/// Cuánto espera el emisor a que el receptor acepte o rechace.
pub const OFFER_TIMEOUT: Duration = Duration::from_secs(120);
/// Cuánto tiene el usuario para aceptar una conexión desde un dispositivo cercano.
pub const PROMPT_TIMEOUT: Duration = Duration::from_secs(60);
const CONNECT_TIMEOUT: Duration = Duration::from_secs(5);
/// Saludo y emparejamiento con código o token (sin intervención del usuario).
const HANDSHAKE_TIMEOUT: Duration = Duration::from_secs(15);
/// Tras esta cantidad de códigos incorrectos se rechaza todo emparejamiento.
const MAX_FAILED_PAIRINGS: u32 = 10;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
#[serde(rename_all = "lowercase")]
pub enum Direction {
    Send,
    Receive,
}

/// Lo que la interfaz necesita saber. Se serializa tal cual hacia el frontend.
#[derive(Debug, Clone, PartialEq, Serialize)]
#[serde(tag = "kind", rename_all = "camelCase", rename_all_fields = "camelCase")]
pub enum Event {
    /// Alguien quiere enviarnos archivos: hay que llamar a `Engine::respond`.
    Offer { transfer_id: String, peer_name: String, files: Vec<FileInfo>, total_bytes: u64 },
    /// Enviamos una oferta y esperamos la respuesta del otro lado.
    Waiting { transfer_id: String, peer_name: String, file_count: usize, total_bytes: u64 },
    Progress {
        transfer_id: String,
        direction: Direction,
        bytes_done: u64,
        bytes_total: u64,
        current_file: String,
    },
    /// `files`: rutas guardadas (al recibir) o nombres enviados (al enviar).
    Completed { transfer_id: String, direction: Direction, files: Vec<String> },
    Failed { transfer_id: String, direction: Direction, reason: String },
    /// Cambió el enlace con el otro dispositivo. `peer` es `None` si se desconectó.
    Link { status: LinkStatus, peer: Option<Peer> },
    /// Un dispositivo cercano pide conectarse: hay que llamar a `Engine::respond`.
    LinkRequest { request_id: String, peer_name: String },
    /// La petición ya no espera respuesta (se respondió o venció).
    LinkRequestEnded { request_id: String },
}

#[derive(Debug, Clone)]
pub struct EngineConfig {
    pub device_id: String,
    pub device_name: String,
    /// Código que el otro lado debe presentar para emparejarse con nosotros.
    pub code: String,
    /// Carpeta inicial donde se guarda lo recibido (se puede cambiar después).
    pub download_dir: PathBuf,
}

#[derive(Clone)]
pub struct Engine {
    inner: Arc<Inner>,
}

pub(crate) struct Inner {
    config: EngineConfig,
    events: mpsc::UnboundedSender<Event>,
    download_dir: Mutex<PathBuf>,
    /// Puerto en el que escuchamos (se anuncia al abrir un enlace).
    port: AtomicU16,
    pending: Mutex<HashMap<String, oneshot::Sender<bool>>>,
    cancels: Mutex<HashMap<String, watch::Sender<bool>>>,
    failed_pairings: AtomicU32,
    link: Mutex<link::Slot>,
    /// Hay una petición de conexión esperando al usuario (solo una a la vez).
    prompting: AtomicBool,
}

impl Inner {
    fn emit(&self, event: Event) {
        // Si la interfaz ya no escucha, no hay a quién avisar.
        let _ = self.events.send(event);
    }

    pub(crate) fn download_dir(&self) -> PathBuf {
        self.download_dir.lock().unwrap().clone()
    }

    /// Hace cancelable la transferencia `id` mientras viva el guard.
    pub(crate) fn track_cancel(&self, id: &str) -> CancelGuard<'_> {
        let (tx, rx) = watch::channel(false);
        self.cancels.lock().unwrap().insert(id.to_owned(), tx);
        CancelGuard { inner: self, id: id.to_owned(), rx }
    }
}

pub(crate) struct CancelGuard<'a> {
    inner: &'a Inner,
    id: String,
    rx: watch::Receiver<bool>,
}

impl CancelGuard<'_> {
    pub fn is_cancelled(&self) -> bool {
        *self.rx.borrow()
    }

    /// Termina cuando el usuario cancela; si nunca cancela, no termina.
    pub async fn cancelled(&mut self) {
        if self.rx.wait_for(|cancelled| *cancelled).await.is_err() {
            std::future::pending::<()>().await;
        }
    }
}

impl Drop for CancelGuard<'_> {
    fn drop(&mut self) {
        self.inner.cancels.lock().unwrap().remove(&self.id);
    }
}

/// Aborta la tarea al soltarse (p. ej. al cortar una transferencia a mitad).
pub(crate) struct AbortOnDrop<T>(pub JoinHandle<T>);

impl<T> Drop for AbortOnDrop<T> {
    fn drop(&mut self) {
        self.0.abort();
    }
}

impl Engine {
    pub fn new(config: EngineConfig, events: mpsc::UnboundedSender<Event>) -> Self {
        Self {
            inner: Arc::new(Inner {
                download_dir: Mutex::new(config.download_dir.clone()),
                config,
                events,
                port: AtomicU16::new(0),
                pending: Mutex::default(),
                cancels: Mutex::default(),
                failed_pairings: AtomicU32::new(0),
                link: Mutex::default(),
                prompting: AtomicBool::new(false),
            }),
        }
    }

    pub fn code(&self) -> &str {
        &self.inner.config.code
    }

    pub fn device_id(&self) -> &str {
        &self.inner.config.device_id
    }

    pub fn download_dir(&self) -> PathBuf {
        self.inner.download_dir()
    }

    /// Cambia dónde se guarda lo que llega (las transferencias en curso no cambian).
    pub fn set_download_dir(&self, dir: PathBuf) {
        *self.inner.download_dir.lock().unwrap() = dir;
    }

    /// Empieza a aceptar conexiones en `addr`. Devuelve la dirección real (útil con puerto 0).
    pub async fn listen(&self, addr: SocketAddr) -> io::Result<SocketAddr> {
        let listener = TcpListener::bind(addr).await?;
        let local = listener.local_addr()?;
        self.inner.port.store(local.port(), Ordering::Relaxed);
        let inner = self.inner.clone();
        tokio::spawn(async move {
            loop {
                match listener.accept().await {
                    Ok((stream, _)) => {
                        tokio::spawn(receive::handle(inner.clone(), stream));
                    }
                    // Errores transitorios (p. ej. demasiados archivos abiertos): reintentar.
                    Err(_) => tokio::time::sleep(Duration::from_millis(100)).await,
                }
            }
        });
        Ok(local)
    }

    /// Respuesta del usuario a un `Event::Offer` o `Event::LinkRequest`.
    /// `false` si ya no espera respuesta.
    pub fn respond(&self, transfer_id: &str, accept: bool) -> bool {
        let sender = self.inner.pending.lock().unwrap().remove(transfer_id);
        sender.is_some_and(|tx| tx.send(accept).is_ok())
    }

    /// Cancela una transferencia en curso (en cualquier sentido) o rechaza una oferta
    /// pendiente. El otro lado recibe `cancel`. `false` si ya no existe.
    pub fn cancel(&self, transfer_id: &str) -> bool {
        if self.respond(transfer_id, false) {
            return true;
        }
        let cancels = self.inner.cancels.lock().unwrap();
        cancels.get(transfer_id).is_some_and(|tx| tx.send(true).is_ok())
    }

    /// Comprueba que hay un dispositivo en `addr` y que acepta `code`. Devuelve su nombre.
    pub async fn check_pairing(&self, addr: SocketAddr, code: &str) -> Result<String, TransferError> {
        let (_, _, peer) = session::connect(&self.inner, addr, code, HANDSHAKE_TIMEOUT).await?;
        Ok(peer)
    }

    /// Se enlaza con `addr` usando su código. Desde ese momento los dos lados pueden
    /// enviarse archivos con `send_linked`. Devuelve el nombre del otro dispositivo.
    pub async fn link(&self, addr: SocketAddr, code: &str) -> Result<String, TransferError> {
        link::open(&self.inner, addr, code).await
    }

    /// Como `link`, sin código: el otro lado le pregunta a su usuario (dispositivo cercano).
    pub async fn link_nearby(&self, addr: SocketAddr) -> Result<String, TransferError> {
        link::open(&self.inner, addr, "").await
    }

    /// Cierra el enlace en los dos lados.
    pub fn unlink(&self) {
        link::close_by_user(&self.inner);
    }

    pub fn link_state(&self) -> (LinkStatus, Option<Peer>) {
        link::state(&self.inner)
    }

    /// Envía al dispositivo enlazado.
    pub async fn send_linked(
        &self,
        transfer_id: String,
        paths: Vec<PathBuf>,
    ) -> Result<(), TransferError> {
        let Some((addr, token)) = link::target(&self.inner) else {
            let error = TransferError::NotConnected;
            self.emit_failed(transfer_id, &error);
            return Err(error);
        };
        self.send(transfer_id, addr, token, paths).await
    }

    /// Envía archivos y carpetas a `addr` presentando `token` (su código o el del enlace).
    /// Emite eventos de progreso y, si falla, `Failed`.
    pub async fn send(
        &self,
        transfer_id: String,
        addr: SocketAddr,
        token: String,
        paths: Vec<PathBuf>,
    ) -> Result<(), TransferError> {
        let result = send::run(&self.inner, &transfer_id, addr, &token, paths).await;
        if let Err(error) = &result {
            self.emit_failed(transfer_id, error);
        }
        result
    }

    fn emit_failed(&self, transfer_id: String, error: &TransferError) {
        self.inner.emit(Event::Failed {
            transfer_id,
            direction: Direction::Send,
            reason: error.code().to_owned(),
        });
    }
}

pub fn new_transfer_id() -> String {
    let mut bytes = [0u8; 8];
    rand::thread_rng().fill_bytes(&mut bytes);
    bytes.iter().map(|b| format!("{b:02x}")).collect()
}
