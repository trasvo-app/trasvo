// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0.
// If a copy of the MPL was not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

//! Piezas compartidas por emisor y receptor: conexión, saludo y progreso.

use std::net::SocketAddr;
use std::time::{Duration, Instant};

use ft_core::PROTOCOL_VERSION;
use ft_protocol::Message;
use tokio::io::{BufReader, BufWriter};
use tokio::net::tcp::{OwnedReadHalf, OwnedWriteHalf};
use tokio::net::TcpStream;
use tokio::time::timeout;

use crate::codec::{read_message, send};
use crate::{Direction, Event, Inner, TransferError, CONNECT_TIMEOUT};

pub(crate) type Reader = BufReader<OwnedReadHalf>;
pub(crate) type Writer = BufWriter<OwnedWriteHalf>;

pub(crate) fn split(stream: TcpStream) -> (Reader, Writer) {
    let _ = stream.set_nodelay(true);
    let (r, w) = stream.into_split();
    (BufReader::new(r), BufWriter::with_capacity(512 * 1024, w))
}

pub(crate) fn hello(inner: &Inner) -> Message {
    Message::Hello {
        version: PROTOCOL_VERSION,
        device_id: inner.config.device_id.clone(),
        device_name: inner.config.device_name.clone(),
    }
}

/// Conecta, saluda y presenta `token` (código, token del enlace o vacío para pedir
/// permiso). `wait`: tope para el saludo y la respuesta. Devuelve el stream listo y
/// el nombre del otro lado.
pub(crate) async fn connect(
    inner: &Inner,
    addr: SocketAddr,
    token: &str,
    wait: Duration,
) -> Result<(Reader, Writer, String), TransferError> {
    let stream = timeout(CONNECT_TIMEOUT, TcpStream::connect(addr))
        .await
        .map_err(|_| TransferError::Connect(std::io::ErrorKind::TimedOut.into()))?
        .map_err(TransferError::Connect)?;
    let (r, w) = split(stream);
    timeout(wait, pair(inner, r, w, token)).await.map_err(|_| TransferError::Timeout)?
}

async fn pair(
    inner: &Inner,
    mut r: Reader,
    mut w: Writer,
    token: &str,
) -> Result<(Reader, Writer, String), TransferError> {
    send(&mut w, hello(inner)).await?;
    let peer_name = match read_message(&mut r).await? {
        Message::Hello { version, device_name, .. } if version == PROTOCOL_VERSION => device_name,
        Message::Hello { .. } => return Err(TransferError::VersionMismatch),
        _ => return Err(TransferError::Unexpected),
    };

    send(&mut w, Message::PairRequest { token: token.to_owned(), fingerprint: String::new() })
        .await?;
    match read_message(&mut r).await? {
        Message::PairAccept { .. } => Ok((r, w, peer_name)),
        Message::PairReject { reason } => Err(TransferError::from_reason(&reason)),
        _ => Err(TransferError::Unexpected),
    }
}

/// Comparación que no corta en el primer byte distinto (no filtra el código por tiempo).
pub(crate) fn same_code(a: &str, b: &str) -> bool {
    a.len() == b.len() && a.bytes().zip(b.bytes()).fold(0u8, |acc, (x, y)| acc | (x ^ y)) == 0
}

const PROGRESS_INTERVAL: Duration = Duration::from_millis(100);

/// Emite `Event::Progress` como mucho cada 100 ms, y siempre al cambiar de archivo y al terminar.
pub(crate) struct Progress<'a> {
    inner: &'a Inner,
    transfer_id: String,
    direction: Direction,
    total: u64,
    done: u64,
    current_file: String,
    last: Instant,
}

impl<'a> Progress<'a> {
    pub fn new(inner: &'a Inner, transfer_id: &str, direction: Direction, total: u64) -> Self {
        Self {
            inner,
            transfer_id: transfer_id.to_owned(),
            direction,
            total,
            done: 0,
            current_file: String::new(),
            last: Instant::now(),
        }
    }

    pub fn start_file(&mut self, name: &str) {
        self.current_file = name.to_owned();
        self.emit();
    }

    pub fn advance(&mut self, bytes: u64) {
        self.done += bytes;
        if self.done == self.total || self.last.elapsed() >= PROGRESS_INTERVAL {
            self.emit();
        }
    }

    fn emit(&mut self) {
        self.last = Instant::now();
        self.inner.emit(Event::Progress {
            transfer_id: self.transfer_id.clone(),
            direction: self.direction,
            bytes_done: self.done,
            bytes_total: self.total,
            current_file: self.current_file.clone(),
        });
    }
}

#[cfg(test)]
mod tests {
    use super::same_code;

    #[test]
    fn same_code_compares_exactly() {
        assert!(same_code("123456", "123456"));
        assert!(!same_code("123456", "123457"));
        assert!(!same_code("123456", "12345"));
        assert!(!same_code("", "1"));
    }
}
