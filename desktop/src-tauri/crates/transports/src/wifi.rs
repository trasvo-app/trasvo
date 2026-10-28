// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0.
// If a copy of the MPL was not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

//! Wi-Fi: TCP entre dispositivos conectados al mismo router.

use std::io;
use std::net::{IpAddr, Ipv4Addr, SocketAddr, TcpStream, UdpSocket};
use std::time::Duration;

/// IP de esta PC en la red local (la de la interfaz con salida a internet).
///
/// `connect` en UDP solo elige la ruta; no envía ningún paquete.
pub fn local_ipv4() -> Option<Ipv4Addr> {
    let socket = UdpSocket::bind((Ipv4Addr::UNSPECIFIED, 0)).ok()?;
    socket.connect((Ipv4Addr::new(8, 8, 8, 8), 80)).ok()?;
    match socket.local_addr().ok()?.ip() {
        IpAddr::V4(ip) if !ip.is_loopback() && !ip.is_unspecified() => Some(ip),
        _ => None,
    }
}

/// Comprueba si hay algo escuchando en `addr` dentro de `timeout`.
pub fn probe(addr: SocketAddr, timeout: Duration) -> io::Result<()> {
    TcpStream::connect_timeout(&addr, timeout).map(|_| ())
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::net::TcpListener;

    #[test]
    fn probe_finds_a_listener() {
        let listener = TcpListener::bind((Ipv4Addr::LOCALHOST, 0)).unwrap();
        let addr = listener.local_addr().unwrap();
        probe(addr, Duration::from_secs(1)).unwrap();
    }

    #[test]
    fn probe_fails_when_nothing_listens() {
        let addr = TcpListener::bind((Ipv4Addr::LOCALHOST, 0))
            .unwrap()
            .local_addr()
            .unwrap();
        // El listener se cerró al salir de la expresión: el puerto queda libre.
        assert!(probe(addr, Duration::from_millis(500)).is_err());
    }
}
