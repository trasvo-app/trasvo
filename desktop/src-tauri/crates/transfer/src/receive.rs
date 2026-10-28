// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0.
// If a copy of the MPL was not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

//! Lado receptor: atiende una conexión entrante de principio a fin.

use std::net::SocketAddr;
use std::path::{Path, PathBuf};
use std::sync::atomic::Ordering;
use std::sync::Arc;

use ft_core::PROTOCOL_VERSION;
use ft_protocol::{FileInfo, Frame, Message};
use sha2::{Digest, Sha256};
use tokio::fs;
use tokio::io::AsyncWriteExt;
use tokio::net::TcpStream;
use tokio::sync::oneshot;
use tokio::time::timeout;

use crate::codec::{read_frame, read_frame_opt, read_message, send};
use crate::files::{part_path, sanitize, unique_destination};
use crate::session::{hello, same_code, split, Progress, Reader, Writer};
use crate::{
    link, new_transfer_id, CancelGuard, Direction, Event, Inner, TransferError,
    MAX_FAILED_PAIRINGS, OFFER_TIMEOUT, PROMPT_TIMEOUT,
};

/// Cómo se autenticó el otro lado.
#[derive(PartialEq)]
enum Auth {
    /// Con nuestro código de 6 dígitos.
    Code,
    /// Con el token del enlace actual.
    Session,
    /// Sin código: nuestro usuario aceptó (solo sirve para abrir un enlace).
    Approved,
}

pub(crate) async fn handle(inner: Arc<Inner>, stream: TcpStream) -> Result<(), TransferError> {
    let peer_ip = stream.peer_addr()?.ip();
    let (mut r, mut w) = split(stream);
    send(&mut w, hello(&inner)).await?;

    let peer_name = match read_message(&mut r).await? {
        Message::Hello { version, device_name, .. } => {
            if version != PROTOCOL_VERSION {
                reject(&mut w, "version_mismatch").await?;
                return Err(TransferError::VersionMismatch);
            }
            device_name
        }
        _ => return Err(TransferError::Unexpected),
    };

    let Message::PairRequest { token, .. } = read_message(&mut r).await? else {
        return Err(TransferError::Unexpected);
    };
    let auth = authorize(&inner, &mut w, &token, &peer_name).await?;
    send(&mut w, Message::PairAccept { device_id: inner.config.device_id.clone() }).await?;

    let first = match read_frame_opt(&mut r).await? {
        None => return Ok(()),
        Some(Frame::Control(Message::LinkOpen { token, port })) => {
            // Con el token del enlace solo se puede retomar ese mismo enlace.
            if auth == Auth::Session && !link::is_session_token(&inner, &token) {
                return Err(TransferError::Unexpected);
            }
            let addr = SocketAddr::new(peer_ip, port);
            return link::accept(inner, r, w, peer_name, addr, token).await;
        }
        Some(frame) => frame,
    };
    if auth == Auth::Approved {
        return Err(TransferError::Unexpected);
    }

    // Una conexión emparejada puede traer varias transferencias seguidas.
    let mut next = Some(first);
    while let Some(frame) = next {
        let Frame::Control(Message::TransferOffer { transfer_id, files }) = frame else {
            return Err(TransferError::Unexpected);
        };
        if let Err(error) = receive(&inner, &mut r, &mut w, &peer_name, &transfer_id, &files).await {
            inner.emit(Event::Failed {
                transfer_id: transfer_id.clone(),
                direction: Direction::Receive,
                reason: error.code().to_owned(),
            });
            let reason = error.code().to_owned();
            let _ = send(&mut w, Message::TransferError { transfer_id, reason }).await;
            return Err(error);
        }
        next = read_frame_opt(&mut r).await?;
    }
    Ok(())
}

async fn authorize(
    inner: &Inner,
    w: &mut Writer,
    token: &str,
    peer_name: &str,
) -> Result<Auth, TransferError> {
    if token.is_empty() {
        if ask_user(inner, peer_name).await {
            return Ok(Auth::Approved);
        }
        reject(w, "declined").await?;
        return Err(TransferError::Rejected("declined".into()));
    }
    // Los tokens de enlace (128 bits) no se pueden adivinar: no cuentan para el bloqueo.
    if token.len() == link::TOKEN_LEN {
        if link::is_session_token(inner, token) {
            return Ok(Auth::Session);
        }
        reject(w, "invalid_code").await?;
        return Err(TransferError::WrongCode);
    }
    if inner.failed_pairings.load(Ordering::Relaxed) >= MAX_FAILED_PAIRINGS {
        reject(w, "locked").await?;
        return Err(TransferError::Locked);
    }
    if !same_code(token, &inner.config.code) {
        inner.failed_pairings.fetch_add(1, Ordering::Relaxed);
        reject(w, "invalid_code").await?;
        return Err(TransferError::WrongCode);
    }
    Ok(Auth::Code)
}

/// Pregunta a nuestro usuario si acepta la conexión. Una pregunta a la vez.
async fn ask_user(inner: &Inner, peer_name: &str) -> bool {
    if inner.prompting.swap(true, Ordering::SeqCst) {
        return false;
    }
    let request_id = new_transfer_id();
    let (tx, rx) = oneshot::channel();
    inner.pending.lock().unwrap().insert(request_id.clone(), tx);
    inner.emit(Event::LinkRequest {
        request_id: request_id.clone(),
        peer_name: peer_name.to_owned(),
    });
    let accepted = matches!(timeout(PROMPT_TIMEOUT, rx).await, Ok(Ok(true)));
    inner.pending.lock().unwrap().remove(&request_id);
    inner.prompting.store(false, Ordering::SeqCst);
    inner.emit(Event::LinkRequestEnded { request_id });
    accepted
}

async fn reject(w: &mut Writer, reason: &str) -> Result<(), TransferError> {
    send(w, Message::PairReject { reason: reason.to_owned() }).await
}

async fn receive(
    inner: &Inner,
    r: &mut Reader,
    w: &mut Writer,
    peer_name: &str,
    transfer_id: &str,
    files: &[FileInfo],
) -> Result<(), TransferError> {
    let relative: Vec<PathBuf> = files.iter().map(|f| sanitize(&f.name)).collect::<Result<_, _>>()?;
    let total = files.iter().map(|f| f.size).sum();

    let (tx, rx) = oneshot::channel();
    inner.pending.lock().unwrap().insert(transfer_id.to_owned(), tx);
    inner.emit(Event::Offer {
        transfer_id: transfer_id.to_owned(),
        peer_name: peer_name.to_owned(),
        files: files.to_vec(),
        total_bytes: total,
    });
    // Mientras el usuario decide, el emisor puede arrepentirse y mandar `cancel`.
    let decision = tokio::select! {
        answer = timeout(OFFER_TIMEOUT, rx) => Ok(matches!(answer, Ok(Ok(true)))),
        msg = read_message(r) => match msg? {
            Message::Cancel { .. } => Err(TransferError::Cancelled),
            _ => Err(TransferError::Unexpected),
        },
    };
    inner.pending.lock().unwrap().remove(transfer_id);

    if !decision? {
        let id = transfer_id.to_owned();
        send(w, Message::TransferReject { transfer_id: id, reason: "declined".into() }).await?;
        inner.emit(Event::Failed {
            transfer_id: transfer_id.to_owned(),
            direction: Direction::Receive,
            reason: "declined".into(),
        });
        return Ok(());
    }
    send(w, Message::TransferAccept { transfer_id: transfer_id.to_owned() }).await?;

    let mut cancel = inner.track_cancel(transfer_id);
    let mut progress = Progress::new(inner, transfer_id, Direction::Receive, total);
    let mut saved = Vec::with_capacity(files.len());
    // La misma carpeta para toda la transferencia, aunque cambie en Ajustes a mitad.
    let download_dir = inner.download_dir();
    for (index, (file, rel)) in files.iter().zip(&relative).enumerate() {
        progress.start_file(&file.name);
        let dest = unique_destination(&download_dir, rel);
        let mut incoming = Incoming { r, w, transfer_id, cancel: &mut cancel };
        let path = incoming.file(file, index, &dest, &mut progress).await?;
        saved.push(path.display().to_string());
    }

    match read_message(r).await? {
        Message::TransferDone { .. } => {}
        _ => return Err(TransferError::Unexpected),
    }
    send(w, Message::TransferComplete { transfer_id: transfer_id.to_owned() }).await?;
    inner.emit(Event::Completed {
        transfer_id: transfer_id.to_owned(),
        direction: Direction::Receive,
        files: saved,
    });
    Ok(())
}

/// Borra el `.part` si la recepción se corta antes de verificar el archivo.
struct PartGuard(Option<PathBuf>);

impl Drop for PartGuard {
    fn drop(&mut self) {
        if let Some(path) = self.0.take() {
            let _ = std::fs::remove_file(path);
        }
    }
}

struct Incoming<'a, 'c> {
    r: &'a mut Reader,
    w: &'a mut Writer,
    transfer_id: &'a str,
    cancel: &'a mut CancelGuard<'c>,
}

impl Incoming<'_, '_> {
    /// Siguiente frame, o `Cancelled` (avisando al emisor) si el usuario cancela.
    async fn next_frame(&mut self) -> Result<Frame, TransferError> {
        tokio::select! {
            frame = read_frame(self.r) => frame,
            () = self.cancel.cancelled() => {
                let transfer_id = self.transfer_id.to_owned();
                let _ = send(self.w, Message::Cancel { transfer_id }).await;
                Err(TransferError::Cancelled)
            }
        }
    }

    async fn file(
        &mut self,
        file: &FileInfo,
        index: usize,
        dest: &Path,
        progress: &mut Progress<'_>,
    ) -> Result<PathBuf, TransferError> {
        if let Some(parent) = dest.parent() {
            fs::create_dir_all(parent).await?;
        }
        let part = part_path(dest);
        let mut guard = PartGuard(Some(part.clone()));
        let mut out = fs::File::create(&part).await?;
        let mut hasher = Sha256::new();
        let mut remaining = file.size;

        while remaining > 0 {
            match self.next_frame().await? {
                Frame::Data(bytes) => {
                    let n = bytes.len() as u64;
                    if n == 0 || n > remaining {
                        return Err(TransferError::Unexpected);
                    }
                    hasher.update(&bytes);
                    out.write_all(&bytes).await?;
                    remaining -= n;
                    progress.advance(n);
                }
                Frame::Control(Message::Cancel { .. }) => return Err(TransferError::Cancelled),
                Frame::Control(Message::TransferError { reason, .. }) => {
                    return Err(TransferError::from_reason(&reason))
                }
                Frame::Control(_) => return Err(TransferError::Unexpected),
            }
        }
        out.flush().await?;
        drop(out);

        match self.next_frame().await? {
            Frame::Control(Message::FileEnd { index: i, hash, .. }) if i as usize == index => {
                if hash != format!("{:x}", hasher.finalize()) {
                    return Err(TransferError::HashMismatch(file.name.clone()));
                }
            }
            Frame::Control(Message::Cancel { .. }) => return Err(TransferError::Cancelled),
            _ => return Err(TransferError::Unexpected),
        }

        fs::rename(&part, dest).await?;
        guard.0 = None;
        Ok(dest.to_path_buf())
    }
}
