// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0.
// If a copy of the MPL was not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

//! Lado emisor: conecta, ofrece, y si aceptan, manda los archivos en trozos.

use std::net::SocketAddr;
use std::path::PathBuf;
use std::time::Duration;

use ft_protocol::{FileInfo, Frame, Message, MAX_CHUNK_BYTES};
use sha2::{Digest, Sha256};
use tokio::fs;
use tokio::io::AsyncReadExt;
use tokio::sync::oneshot;
use tokio::time::timeout;

use crate::codec::{read_message, send, write_frame};
use crate::files::{collect, OutgoingFile};
use crate::session::{connect, Progress, Writer};
use crate::{
    AbortOnDrop, CancelGuard, Direction, Event, Inner, TransferError, HANDSHAKE_TIMEOUT,
    OFFER_TIMEOUT,
};

/// Margen sobre `OFFER_TIMEOUT`: el receptor responde «rechazado» al vencer el suyo.
const ACCEPT_WAIT: Duration = Duration::from_secs(OFFER_TIMEOUT.as_secs() + 10);
const COMPLETE_WAIT: Duration = Duration::from_secs(30);

type PeerReply = oneshot::Receiver<Result<Message, TransferError>>;

pub(crate) async fn run(
    inner: &Inner,
    transfer_id: &str,
    addr: SocketAddr,
    token: &str,
    paths: Vec<PathBuf>,
) -> Result<(), TransferError> {
    let mut cancel = inner.track_cancel(transfer_id);
    let files = tokio::task::spawn_blocking(move || collect(&paths))
        .await
        .map_err(|e| TransferError::Io(std::io::Error::other(e)))??;
    if files.is_empty() {
        return Err(TransferError::Empty);
    }
    let total: u64 = files.iter().map(|f| f.size).sum();

    let (mut r, mut w, peer_name) = connect(inner, addr, token, HANDSHAKE_TIMEOUT).await?;
    let id = || transfer_id.to_owned();

    let offer = files.iter().map(|f| FileInfo { name: f.name.clone(), size: f.size }).collect();
    send(&mut w, Message::TransferOffer { transfer_id: id(), files: offer }).await?;
    inner.emit(Event::Waiting {
        transfer_id: id(),
        peer_name,
        file_count: files.len(),
        total_bytes: total,
    });

    let reply = tokio::select! {
        reply = timeout(ACCEPT_WAIT, read_message(&mut r)) => {
            reply.map_err(|_| TransferError::Timeout)??
        }
        () = cancel.cancelled() => {
            let _ = send(&mut w, Message::Cancel { transfer_id: id() }).await;
            return Err(TransferError::Cancelled);
        }
    };
    match reply {
        Message::TransferAccept { .. } => {}
        Message::TransferReject { reason, .. } => return Err(TransferError::from_reason(&reason)),
        _ => return Err(TransferError::Unexpected),
    }

    // Desde aquí solo escribimos; una tarea aparte escucha si el receptor cancela
    // o falla a mitad, y trae su respuesta final.
    let (reply_tx, mut peer) = oneshot::channel();
    let _reader = AbortOnDrop(tokio::spawn(async move {
        let _ = reply_tx.send(read_message(&mut r).await);
    }));

    let mut progress = Progress::new(inner, transfer_id, Direction::Send, total);
    let mut buf = vec![0u8; MAX_CHUNK_BYTES];
    for (index, file) in files.iter().enumerate() {
        progress.start_file(&file.name);
        let mut outgoing = Outgoing { w: &mut w, cancel: &cancel, peer: &mut peer };
        let sent = outgoing.file(file, &mut buf, &mut progress).await;
        let hash = match sent {
            Ok(hash) => hash,
            Err(error) => {
                if cancel.is_cancelled() {
                    let _ = send(&mut w, Message::Cancel { transfer_id: id() }).await;
                }
                return Err(error);
            }
        };
        let index = index as u32;
        send(&mut w, Message::FileEnd { transfer_id: id(), index, hash }).await?;
    }
    send(&mut w, Message::TransferDone { transfer_id: id() }).await?;

    let reply = timeout(COMPLETE_WAIT, peer)
        .await
        .map_err(|_| TransferError::Timeout)?
        .map_err(|_| TransferError::Unexpected)??;
    match reply {
        Message::TransferComplete { .. } => {}
        Message::TransferError { reason, .. } => return Err(TransferError::from_reason(&reason)),
        Message::Cancel { .. } => return Err(TransferError::Cancelled),
        _ => return Err(TransferError::Unexpected),
    }

    inner.emit(Event::Completed {
        transfer_id: id(),
        direction: Direction::Send,
        files: files.into_iter().map(|f| f.name).collect(),
    });
    Ok(())
}

struct Outgoing<'a, 'c> {
    w: &'a mut Writer,
    cancel: &'a CancelGuard<'c>,
    peer: &'a mut PeerReply,
}

impl Outgoing<'_, '_> {
    /// Corta si el usuario canceló o si el receptor ya respondió (cancel / error).
    fn check(&mut self) -> Result<(), TransferError> {
        if self.cancel.is_cancelled() {
            return Err(TransferError::Cancelled);
        }
        match self.peer.try_recv() {
            Err(oneshot::error::TryRecvError::Empty) => Ok(()),
            Err(oneshot::error::TryRecvError::Closed) => Err(TransferError::Unexpected),
            Ok(Err(error)) => Err(error),
            Ok(Ok(Message::Cancel { .. })) => Err(TransferError::Cancelled),
            Ok(Ok(Message::TransferError { reason, .. })) => Err(TransferError::from_reason(&reason)),
            Ok(Ok(_)) => Err(TransferError::Unexpected),
        }
    }

    /// Manda exactamente `file.size` bytes y devuelve su SHA-256 en hexadecimal.
    async fn file(
        &mut self,
        file: &OutgoingFile,
        buf: &mut [u8],
        progress: &mut Progress<'_>,
    ) -> Result<String, TransferError> {
        let mut input = fs::File::open(&file.path).await?;
        let mut hasher = Sha256::new();
        let mut remaining = file.size;
        while remaining > 0 {
            self.check()?;
            let want = remaining.min(buf.len() as u64) as usize;
            let n = input.read(&mut buf[..want]).await?;
            if n == 0 {
                // El archivo se achicó desde que lo listamos.
                return Err(std::io::Error::from(std::io::ErrorKind::UnexpectedEof).into());
            }
            hasher.update(&buf[..n]);
            write_frame(self.w, &Frame::Data(buf[..n].to_vec())).await?;
            remaining -= n as u64;
            progress.advance(n as u64);
        }
        self.check()?;
        Ok(format!("{:x}", hasher.finalize()))
    }
}
