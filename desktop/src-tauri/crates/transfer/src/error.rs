// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0.
// If a copy of the MPL was not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

use std::io;

use thiserror::Error;

#[derive(Debug, Error)]
pub enum TransferError {
    #[error("connection failed: {0}")]
    Connect(io::Error),
    #[error("io: {0}")]
    Io(#[from] io::Error),
    #[error("protocol: {0}")]
    Protocol(#[from] ft_core::Error),
    #[error("unexpected message from peer")]
    Unexpected,
    #[error("wrong pairing code")]
    WrongCode,
    #[error("too many failed pairing attempts")]
    Locked,
    #[error("protocol version mismatch")]
    VersionMismatch,
    #[error("peer rejected: {0}")]
    Rejected(String),
    #[error("integrity check failed for {0}")]
    HashMismatch(String),
    #[error("invalid file name: {0}")]
    InvalidName(String),
    #[error("nothing to send")]
    Empty,
    #[error("cancelled")]
    Cancelled,
    #[error("timed out")]
    Timeout,
    #[error("no linked device")]
    NotConnected,
}

impl TransferError {
    /// Código estable para la interfaz y para `pair_reject` / `transfer_error`.
    pub fn code(&self) -> &'static str {
        match self {
            Self::Connect(_) => "unreachable",
            Self::Io(_) => "io",
            Self::Protocol(_) | Self::Unexpected => "protocol",
            Self::WrongCode => "invalid_code",
            Self::Locked => "locked",
            Self::VersionMismatch => "version_mismatch",
            Self::Rejected(_) => "declined",
            Self::HashMismatch(_) => "hash_mismatch",
            Self::InvalidName(_) => "invalid_name",
            Self::Empty => "empty",
            Self::Cancelled => "cancelled",
            Self::Timeout => "timeout",
            Self::NotConnected => "not_connected",
        }
    }

    /// Traduce el `reason` que manda el otro lado.
    pub(crate) fn from_reason(reason: &str) -> Self {
        match reason {
            "invalid_code" => Self::WrongCode,
            "locked" => Self::Locked,
            "version_mismatch" => Self::VersionMismatch,
            "cancelled" => Self::Cancelled,
            other => Self::Rejected(other.to_owned()),
        }
    }
}
