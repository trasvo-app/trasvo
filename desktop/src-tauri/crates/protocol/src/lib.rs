// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0.
// If a copy of the MPL was not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

//! Mensajes y encuadre del protocolo (ver docs/protocol.md). Sin I/O.
//!
//! Cada frame = `u32` big-endian con la longitud del resto + `u8` tipo + carga.
//! Tipo 0: mensaje de control en JSON. Tipo 1: bytes del archivo en curso.

use ft_core::{Error, Result, MAX_CONTROL_MESSAGE_BYTES};
use serde::{Deserialize, Serialize};

pub const FRAME_CONTROL: u8 = 0;
pub const FRAME_DATA: u8 = 1;

/// Tamaño máximo de un trozo de archivo.
pub const MAX_CHUNK_BYTES: usize = 256 * 1024;

/// Longitud máxima del cuerpo de un frame (tipo + carga).
pub const MAX_FRAME_BODY: usize = 1 + MAX_CONTROL_MESSAGE_BYTES;

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct FileInfo {
    /// Ruta relativa con `/` (p. ej. `Fotos/playa.jpg`).
    pub name: String,
    pub size: u64,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(tag = "type", rename_all = "snake_case")]
pub enum Message {
    Hello { version: u32, device_id: String, device_name: String },
    PairRequest { token: String, fingerprint: String },
    PairAccept { device_id: String },
    PairReject { reason: String },
    TransferOffer { transfer_id: String, files: Vec<FileInfo> },
    TransferAccept { transfer_id: String },
    TransferReject { transfer_id: String, reason: String },
    FileEnd { transfer_id: String, index: u32, hash: String },
    TransferDone { transfer_id: String },
    TransferComplete { transfer_id: String },
    TransferError { transfer_id: String, reason: String },
    Cancel { transfer_id: String },
    /// Abre un enlace persistente. `token` autentica las transferencias en ambos
    /// sentidos mientras dure; `port` es donde escucha quien abre el enlace.
    LinkOpen { token: String, port: u16 },
    LinkAccept,
    /// Latido del enlace, en ambos sentidos.
    Ping,
    /// Cierre del enlace pedido por el usuario.
    LinkClose,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Frame {
    Control(Message),
    Data(Vec<u8>),
}

pub fn encode_frame(frame: &Frame) -> Result<Vec<u8>> {
    let (kind, payload) = match frame {
        Frame::Control(msg) => {
            let body =
                serde_json::to_vec(msg).map_err(|e| Error::InvalidMessage(e.to_string()))?;
            if body.len() > MAX_CONTROL_MESSAGE_BYTES {
                return Err(Error::MessageTooLarge(body.len()));
            }
            (FRAME_CONTROL, body)
        }
        Frame::Data(bytes) => {
            if bytes.len() > MAX_CHUNK_BYTES {
                return Err(Error::MessageTooLarge(bytes.len()));
            }
            (FRAME_DATA, bytes.clone())
        }
    };
    let mut out = Vec::with_capacity(5 + payload.len());
    out.extend_from_slice(&((payload.len() + 1) as u32).to_be_bytes());
    out.push(kind);
    out.extend_from_slice(&payload);
    Ok(out)
}

/// Longitud del cuerpo indicada por la cabecera de 4 bytes, ya validada.
pub fn body_len(header: [u8; 4]) -> Result<usize> {
    let len = u32::from_be_bytes(header) as usize;
    if len == 0 {
        return Err(Error::InvalidMessage("empty frame".into()));
    }
    if len > MAX_FRAME_BODY {
        return Err(Error::MessageTooLarge(len));
    }
    Ok(len)
}

/// Decodifica el cuerpo de un frame (tipo + carga), sin la cabecera.
pub fn decode_body(body: &[u8]) -> Result<Frame> {
    let (&kind, payload) = body
        .split_first()
        .ok_or_else(|| Error::InvalidMessage("empty frame".into()))?;
    match kind {
        FRAME_CONTROL => serde_json::from_slice(payload)
            .map(Frame::Control)
            .map_err(|e| Error::InvalidMessage(e.to_string())),
        FRAME_DATA if payload.len() <= MAX_CHUNK_BYTES => Ok(Frame::Data(payload.to_vec())),
        FRAME_DATA => Err(Error::MessageTooLarge(payload.len())),
        other => Err(Error::InvalidMessage(format!("unknown frame type {other}"))),
    }
}

/// Decodifica un frame completo. Devuelve el frame y los bytes consumidos.
pub fn decode_frame(buf: &[u8]) -> Result<(Frame, usize)> {
    let header: [u8; 4] = buf.get(..4).ok_or(Error::IncompleteFrame)?.try_into().unwrap();
    let len = body_len(header)?;
    let body = buf.get(4..4 + len).ok_or(Error::IncompleteFrame)?;
    Ok((decode_body(body)?, 4 + len))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[derive(Deserialize)]
    struct Vector {
        name: String,
        json: serde_json::Value,
    }

    fn vectors() -> Vec<Vector> {
        let raw = include_str!("../../../../../protocol/test-vectors/control-messages.json");
        serde_json::from_str(raw).unwrap()
    }

    #[test]
    fn vectors_roundtrip() {
        for v in vectors() {
            let msg: Message = serde_json::from_value(v.json.clone())
                .unwrap_or_else(|e| panic!("{}: {e}", v.name));
            assert_eq!(serde_json::to_value(&msg).unwrap(), v.json, "{}", v.name);
            let frame = Frame::Control(msg);
            let bytes = encode_frame(&frame).unwrap();
            let (back, used) = decode_frame(&bytes).unwrap();
            assert_eq!(back, frame);
            assert_eq!(used, bytes.len());
        }
    }

    #[test]
    fn data_frames_roundtrip() {
        let frame = Frame::Data(vec![0, 1, 2, 255]);
        let bytes = encode_frame(&frame).unwrap();
        assert_eq!(&bytes[..5], &[0, 0, 0, 5, FRAME_DATA]);
        assert_eq!(decode_frame(&bytes).unwrap(), (frame, 9));
    }

    #[test]
    fn oversized_chunks_are_rejected() {
        let frame = Frame::Data(vec![0; MAX_CHUNK_BYTES + 1]);
        assert!(matches!(encode_frame(&frame), Err(Error::MessageTooLarge(_))));
    }

    #[test]
    fn incomplete_frame_is_reported() {
        assert_eq!(decode_frame(&[0, 0]).unwrap_err(), Error::IncompleteFrame);
        assert_eq!(decode_frame(&[0, 0, 0, 5, 0]).unwrap_err(), Error::IncompleteFrame);
    }

    #[test]
    fn invalid_headers_are_rejected() {
        assert!(body_len([0, 0, 0, 0]).is_err());
        let too_big = (MAX_FRAME_BODY as u32 + 1).to_be_bytes();
        assert!(matches!(body_len(too_big), Err(Error::MessageTooLarge(_))));
        assert!(decode_body(&[9, 1, 2]).is_err());
    }
}
