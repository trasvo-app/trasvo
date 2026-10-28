// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0.
// If a copy of the MPL was not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

//! Emparejamiento: códigos de un solo uso que se muestran en pantalla y en el QR.

use rand::Rng;

/// Cantidad de dígitos del código de emparejamiento.
pub const CODE_LEN: usize = 6;

/// Genera un código numérico de `CODE_LEN` dígitos (con ceros a la izquierda).
pub fn generate_code() -> String {
    format!("{:06}", rand::thread_rng().gen_range(0..1_000_000))
}

/// Un código válido tiene exactamente `CODE_LEN` dígitos ASCII.
pub fn is_valid_code(code: &str) -> bool {
    code.len() == CODE_LEN && code.bytes().all(|b| b.is_ascii_digit())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn generated_codes_are_valid() {
        for _ in 0..1000 {
            assert!(is_valid_code(&generate_code()));
        }
    }

    #[test]
    fn rejects_malformed_codes() {
        for bad in ["", "12345", "1234567", "12a456", " 12345", "１２３４５６"] {
            assert!(!is_valid_code(bad), "{bad:?}");
        }
    }
}
