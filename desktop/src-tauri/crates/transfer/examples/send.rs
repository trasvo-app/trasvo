// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0.
// If a copy of the MPL was not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

//! Envía archivos a una PC o celular desde la terminal (útil para probar la app).
//!
//! cargo run -p ft-transfer --example send -- 192.168.1.20:47520 123456 foto.jpg Carpeta

use std::path::PathBuf;

use ft_transfer::{new_transfer_id, Engine, EngineConfig, Event};
use tokio::sync::mpsc;

#[tokio::main]
async fn main() {
    let mut args = std::env::args().skip(1);
    let (Some(addr), Some(code)) = (args.next(), args.next()) else {
        eprintln!("uso: send <ip:puerto> <código> <archivo o carpeta>...");
        std::process::exit(2);
    };
    let paths: Vec<PathBuf> = args.map(PathBuf::from).collect();
    if paths.is_empty() {
        eprintln!("Falta al menos un archivo o carpeta para enviar.");
        std::process::exit(2);
    }
    let missing: Vec<_> = paths.iter().filter(|p| !p.exists()).collect();
    if !missing.is_empty() {
        for path in missing {
            eprintln!("No existe: {}", path.display());
        }
        std::process::exit(2);
    }
    let addr = addr.parse().expect("dirección inválida, ej. 192.168.1.20:47520");

    let (tx, mut rx) = mpsc::unbounded_channel();
    let engine = Engine::new(
        EngineConfig {
            device_id: "cli".into(),
            device_name: "Terminal".into(),
            code: String::new(),
            download_dir: std::env::temp_dir(),
        },
        tx,
    );
    tokio::spawn(async move {
        while let Some(event) = rx.recv().await {
            match event {
                Event::Waiting { peer_name, .. } => println!("Esperando que {peer_name} acepte…"),
                Event::Progress { bytes_done, bytes_total, current_file, .. } => {
                    let pct = (bytes_done * 100).checked_div(bytes_total).unwrap_or(100);
                    println!("{pct:>3}%  {current_file}");
                }
                Event::Completed { files, .. } => println!("Listo: {} archivo(s)", files.len()),
                // Los errores se imprimen abajo, con el resultado de `send`.
                _ => {}
            }
        }
    });

    if let Err(error) = engine.send(new_transfer_id(), addr, code, paths).await {
        eprintln!("Falló: {} ({error})", error.code());
        std::process::exit(1);
    }
}
