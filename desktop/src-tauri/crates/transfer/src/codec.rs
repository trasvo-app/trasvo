// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0.
// If a copy of the MPL was not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

//! Lectura y escritura de frames sobre un stream asíncrono.

use std::io::ErrorKind;

use ft_protocol::{body_len, decode_body, encode_frame, Frame, Message};
use tokio::io::{AsyncRead, AsyncReadExt, AsyncWrite, AsyncWriteExt};

use crate::TransferError;

pub async fn write_frame<W: AsyncWrite + Unpin>(
    w: &mut W,
    frame: &Frame,
) -> Result<(), TransferError> {
    w.write_all(&encode_frame(frame)?).await?;
    Ok(())
}

pub async fn send<W: AsyncWrite + Unpin>(w: &mut W, msg: Message) -> Result<(), TransferError> {
    write_frame(w, &Frame::Control(msg)).await?;
    w.flush().await?;
    Ok(())
}

/// Lee un frame. `Ok(None)` si el otro lado cerró limpiamente entre frames.
pub async fn read_frame_opt<R: AsyncRead + Unpin>(
    r: &mut R,
) -> Result<Option<Frame>, TransferError> {
    let mut header = [0u8; 4];
    match r.read_exact(&mut header).await {
        Ok(_) => {}
        Err(e) if e.kind() == ErrorKind::UnexpectedEof => return Ok(None),
        Err(e) => return Err(e.into()),
    }
    let mut body = vec![0u8; body_len(header)?];
    r.read_exact(&mut body).await?;
    Ok(Some(decode_body(&body)?))
}

pub async fn read_frame<R: AsyncRead + Unpin>(r: &mut R) -> Result<Frame, TransferError> {
    read_frame_opt(r)
        .await?
        .ok_or_else(|| ErrorKind::UnexpectedEof.into())
        .map_err(|e: std::io::Error| e.into())
}

/// Lee un mensaje de control; un frame de datos aquí es un error de protocolo.
pub async fn read_message<R: AsyncRead + Unpin>(r: &mut R) -> Result<Message, TransferError> {
    match read_frame(r).await? {
        Frame::Control(msg) => Ok(msg),
        Frame::Data(_) => Err(TransferError::Unexpected),
    }
}
