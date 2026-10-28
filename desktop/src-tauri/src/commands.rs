// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0.
// If a copy of the MPL was not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

//! Comandos que la interfaz invoca. Solo traducen: la lógica vive en `crates/`.

use std::net::{Ipv4Addr, SocketAddr};
use std::path::{Path, PathBuf};
use std::sync::Mutex;

use ft_core::PROTOCOL_VERSION;
use ft_discovery::{Discovery, NearbyDevice};
use ft_transfer::{new_transfer_id, Engine, LinkStatus, Peer, TransferError};
use ft_transports::wifi;
use serde::Serialize;
use tauri::State;

use crate::settings::Settings;

pub struct AppState {
    pub engine: Engine,
    pub device_name: String,
    /// Puerto en el que escucha el servidor (`None` si no se pudo abrir).
    pub port: Option<u16>,
    /// Búsqueda en el Wi-Fi (`None` si no hay red o no se pudo iniciar).
    pub discovery: Option<Discovery>,
    pub config_dir: PathBuf,
    pub settings: Mutex<Settings>,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ConnectionInfo {
    device_name: String,
    ip: Option<String>,
    port: Option<u16>,
    code: String,
    download_dir: String,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub struct LinkView {
    status: LinkStatus,
    peer: Option<Peer>,
}

/// Errores que ve la interfaz; se traducen a texto en el frontend.
#[derive(Debug, Serialize)]
#[serde(transparent)]
pub struct CommandError(&'static str);

impl From<TransferError> for CommandError {
    fn from(error: TransferError) -> Self {
        Self(error.code())
    }
}

#[tauri::command]
pub fn protocol_version() -> u32 {
    PROTOCOL_VERSION
}

#[tauri::command]
pub fn connection_info(state: State<'_, AppState>) -> ConnectionInfo {
    ConnectionInfo {
        device_name: state.device_name.clone(),
        ip: wifi::local_ipv4().map(|ip| ip.to_string()),
        port: state.port,
        code: state.engine.code().to_owned(),
        download_dir: state.engine.download_dir().display().to_string(),
    }
}

fn parse_addr(ip: &str, port: u16) -> Result<SocketAddr, CommandError> {
    if port == 0 {
        return Err(CommandError("invalid_port"));
    }
    let ip: Ipv4Addr = ip.trim().parse().map_err(|_| CommandError("invalid_ip"))?;
    Ok(SocketAddr::from((ip, port)))
}

/// Se enlaza con el otro dispositivo usando su código. Devuelve su nombre.
/// Desde ahí los dos lados pueden enviarse archivos hasta que alguno desconecte.
#[tauri::command]
pub async fn connect(
    state: State<'_, AppState>,
    ip: String,
    port: u16,
    code: String,
) -> Result<String, CommandError> {
    if !ft_pairing::is_valid_code(&code) {
        return Err(CommandError("invalid_code"));
    }
    let addr = parse_addr(&ip, port)?;
    Ok(state.engine.link(addr, &code).await?)
}

/// Se enlaza con un dispositivo encontrado en el Wi-Fi: el otro lado debe aceptar.
#[tauri::command]
pub async fn connect_nearby(
    state: State<'_, AppState>,
    ip: String,
    port: u16,
) -> Result<String, CommandError> {
    let addr = parse_addr(&ip, port)?;
    Ok(state.engine.link_nearby(addr).await?)
}

#[tauri::command]
pub fn disconnect(state: State<'_, AppState>) {
    state.engine.unlink();
}

#[tauri::command]
pub fn link_state(state: State<'_, AppState>) -> LinkView {
    let (status, peer) = state.engine.link_state();
    LinkView { status, peer }
}

#[tauri::command]
pub fn nearby_devices(state: State<'_, AppState>) -> Vec<NearbyDevice> {
    state.discovery.as_ref().map(Discovery::devices).unwrap_or_default()
}

/// Empieza a enviar al dispositivo enlazado y devuelve el id; el progreso llega por eventos.
#[tauri::command]
pub fn send_files(state: State<'_, AppState>, paths: Vec<String>) -> Result<String, CommandError> {
    if paths.is_empty() {
        return Err(CommandError("empty"));
    }
    if state.engine.link_state().1.is_none() {
        return Err(CommandError("not_connected"));
    }
    let transfer_id = new_transfer_id();
    let engine = state.engine.clone();
    let id = transfer_id.clone();
    let paths = paths.into_iter().map(PathBuf::from).collect();
    tauri::async_runtime::spawn(async move {
        // El resultado ya llega a la interfaz como evento `completed` o `failed`.
        let _ = engine.send_linked(id, paths).await;
    });
    Ok(transfer_id)
}

/// Cancela una transferencia en curso o rechaza una oferta pendiente.
#[tauri::command]
pub fn cancel_transfer(state: State<'_, AppState>, transfer_id: String) -> bool {
    state.engine.cancel(&transfer_id)
}

/// Respuesta del usuario a una oferta entrante o a una petición de conexión.
#[tauri::command]
pub fn respond_offer(state: State<'_, AppState>, transfer_id: String, accept: bool) -> bool {
    state.engine.respond(&transfer_id, accept)
}

/// Cambia la carpeta donde se guarda lo recibido y la recuerda. Devuelve la ruta final.
#[tauri::command]
pub fn set_download_dir(state: State<'_, AppState>, path: String) -> Result<String, CommandError> {
    let dir = PathBuf::from(path);
    if !dir.is_dir() {
        return Err(CommandError("invalid_folder"));
    }
    save_download_dir(&state, Some(dir.clone()))?;
    state.engine.set_download_dir(dir.clone());
    Ok(dir.display().to_string())
}

/// Vuelve a la carpeta Descargas del sistema.
#[tauri::command]
pub fn reset_download_dir(
    state: State<'_, AppState>,
    app: tauri::AppHandle,
) -> Result<String, CommandError> {
    let dir = crate::default_download_dir(&app);
    save_download_dir(&state, None)?;
    state.engine.set_download_dir(dir.clone());
    Ok(dir.display().to_string())
}

fn save_download_dir(state: &AppState, dir: Option<PathBuf>) -> Result<(), CommandError> {
    let mut settings = state.settings.lock().unwrap();
    settings.download_dir = dir;
    settings.save(&state.config_dir).map_err(|_| CommandError("io"))
}

/// Abre la carpeta de descargas en el Explorador.
#[tauri::command]
pub fn open_download_dir(state: State<'_, AppState>) -> Result<(), CommandError> {
    let dir = state.engine.download_dir();
    open_in_explorer(&dir).map_err(|_| CommandError("io"))
}

fn open_in_explorer(path: &Path) -> std::io::Result<()> {
    #[cfg(windows)]
    let program = "explorer";
    #[cfg(target_os = "macos")]
    let program = "open";
    #[cfg(all(unix, not(target_os = "macos")))]
    let program = "xdg-open";
    std::process::Command::new(program).arg(path).spawn().map(|_| ())
}
