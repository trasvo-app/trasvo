// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0.
// If a copy of the MPL was not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

//! Dominio sin I/O: identificadores y errores compartidos.

use thiserror::Error;

/// Versión del protocolo que habla esta compilación.
pub const PROTOCOL_VERSION: u32 = 1;

/// Puerto TCP por defecto en el que escucha cada dispositivo.
pub const DEFAULT_PORT: u16 = 47520;

/// Tamaño máximo de un mensaje de control (1 MiB).
pub const MAX_CONTROL_MESSAGE_BYTES: usize = 1024 * 1024;

#[derive(Debug, Error, PartialEq, Eq)]
pub enum Error {
    #[error("message too large: {0} bytes")]
    MessageTooLarge(usize),
    #[error("incomplete frame")]
    IncompleteFrame,
    #[error("invalid message: {0}")]
    InvalidMessage(String),
}

pub type Result<T> = std::result::Result<T, Error>;
