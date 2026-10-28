// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0.
// If a copy of the MPL was not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

//! Capa Tauri: arranca el motor, reenvía sus eventos y registra comandos.
//! La lógica vive en `crates/`.

mod commands;
mod settings;

use std::net::{Ipv4Addr, SocketAddr};
use std::path::PathBuf;
use std::sync::Mutex;

use commands::AppState;
use ft_core::DEFAULT_PORT;
use ft_discovery::Discovery;
use ft_transfer::{new_transfer_id, Engine, EngineConfig};
use ft_transports::wifi;
use settings::Settings;
use tauri::{Emitter, Manager, WebviewUrl, WebviewWindowBuilder};
use tokio::sync::mpsc;

/// Nombres de los eventos que recibe el frontend (ver `src/ipc/events.ts`).
const TRANSFER_EVENT: &str = "transfer-event";
const NEARBY_EVENT: &str = "nearby-devices";

fn device_name() -> String {
    std::env::var("COMPUTERNAME").unwrap_or_else(|_| "Mi PC".into())
}

pub(crate) fn default_download_dir(app: &tauri::AppHandle) -> PathBuf {
    app.path().download_dir().unwrap_or_else(|_| std::env::temp_dir())
}

/// Ventana principal. Se crea desde código (no en tauri.conf.json) para poder
/// agregar, solo en desarrollo, el puerto de depuración de WebView2.
fn create_main_window(app: &tauri::App) -> tauri::Result<()> {
    let builder = WebviewWindowBuilder::new(app, "main", WebviewUrl::default())
        .title("Trasvo")
        .inner_size(1200.0, 780.0)
        .min_inner_size(760.0, 560.0);

    // Solo `tauri dev`: abre 127.0.0.1:9222 para que Chrome DevTools MCP pueda ver y
    // probar la ventana real (ver docs/development.md). Nunca se compila en release.
    // Los `--disable-features` son los que Tauri pone por defecto; hay que repetirlos.
    #[cfg(all(debug_assertions, windows))]
    let builder = builder.additional_browser_args(
        "--disable-features=msWebOOUI,msPdfOOUI,msSmartScreenProtection --remote-debugging-port=9222",
    );

    builder.build()?;
    Ok(())
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .plugin(tauri_plugin_dialog::init())
        .setup(|app| {
            create_main_window(app)?;

            let config_dir = app.path().app_config_dir().unwrap_or_else(|_| std::env::temp_dir());
            let mut settings = Settings::load(&config_dir);
            let device_id = match &settings.device_id {
                Some(id) => id.clone(),
                None => {
                    let id = new_transfer_id();
                    settings.device_id = Some(id.clone());
                    // Si no se puede guardar, igual funciona (con otro id en el próximo inicio).
                    let _ = settings.save(&config_dir);
                    id
                }
            };
            // Si la carpeta elegida ya no existe (p. ej. un disco desconectado), Descargas.
            let download_dir = settings
                .download_dir
                .clone()
                .filter(|dir| dir.is_dir())
                .unwrap_or_else(|| default_download_dir(app.handle()));
            let name = device_name();
            let (tx, mut rx) = mpsc::unbounded_channel();
            let engine = Engine::new(
                EngineConfig {
                    device_id,
                    device_name: name.clone(),
                    code: ft_pairing::generate_code(),
                    download_dir,
                },
                tx,
            );

            let handle = app.handle().clone();
            tauri::async_runtime::spawn(async move {
                while let Some(event) = rx.recv().await {
                    let _ = handle.emit(TRANSFER_EVENT, &event);
                }
            });

            // Puerto fijo para que el QR y la IP no cambien; si está ocupado, uno libre.
            let port = tauri::async_runtime::block_on(async {
                let any = |port| SocketAddr::from((Ipv4Addr::UNSPECIFIED, port));
                match engine.listen(any(DEFAULT_PORT)).await {
                    Ok(addr) => Some(addr.port()),
                    Err(_) => engine.listen(any(0)).await.ok().map(|a| a.port()),
                }
            });

            // Anunciarse y buscar en el Wi-Fi. Sin red o sin puerto, solo QR/IP.
            let discovery = match (wifi::local_ipv4(), port) {
                (Some(ip), Some(port)) => {
                    let handle = app.handle().clone();
                    Discovery::start(engine.device_id(), &name, ip, port, move |devices| {
                        let _ = handle.emit(NEARBY_EVENT, &devices);
                    })
                    .ok()
                }
                _ => None,
            };

            app.manage(AppState {
                engine,
                device_name: name,
                port,
                discovery,
                config_dir,
                settings: Mutex::new(settings),
            });
            Ok(())
        })
        .invoke_handler(tauri::generate_handler![
            commands::protocol_version,
            commands::connection_info,
            commands::connect,
            commands::connect_nearby,
            commands::disconnect,
            commands::link_state,
            commands::nearby_devices,
            commands::send_files,
            commands::respond_offer,
            commands::cancel_transfer,
            commands::set_download_dir,
            commands::reset_download_dir,
            commands::open_download_dir,
        ])
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
