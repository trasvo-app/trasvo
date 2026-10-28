// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0.
// If a copy of the MPL was not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

//! Preferencias de la PC guardadas en disco (carpeta de configuración de la app).

use std::fs;
use std::path::{Path, PathBuf};

use serde::{Deserialize, Serialize};

const FILE: &str = "settings.json";

#[derive(Debug, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Settings {
    /// Dónde se guarda lo recibido. `None`: la carpeta Descargas del sistema.
    #[serde(default)]
    pub download_dir: Option<PathBuf>,
    /// Identificador fijo de esta PC (el mismo en cada inicio, para la búsqueda en el Wi-Fi).
    #[serde(default)]
    pub device_id: Option<String>,
}

impl Settings {
    /// Lee las preferencias; si no hay o están dañadas, usa los valores por defecto.
    pub fn load(config_dir: &Path) -> Self {
        fs::read(config_dir.join(FILE))
            .ok()
            .and_then(|bytes| serde_json::from_slice(&bytes).ok())
            .unwrap_or_default()
    }

    pub fn save(&self, config_dir: &Path) -> std::io::Result<()> {
        fs::create_dir_all(config_dir)?;
        let json = serde_json::to_vec_pretty(self).map_err(std::io::Error::other)?;
        fs::write(config_dir.join(FILE), json)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn roundtrip_and_defaults() {
        let dir = std::env::temp_dir().join(format!("ft-settings-{}", std::process::id()));
        let _ = fs::remove_dir_all(&dir);
        assert!(Settings::load(&dir).download_dir.is_none());

        let settings = Settings {
            download_dir: Some(PathBuf::from(r"D:\Recibidos")),
            device_id: Some("abc".into()),
        };
        settings.save(&dir).unwrap();
        assert_eq!(Settings::load(&dir).download_dir, settings.download_dir);

        fs::write(dir.join(FILE), b"{roto").unwrap();
        assert!(Settings::load(&dir).download_dir.is_none());
        fs::remove_dir_all(&dir).unwrap();
    }
}
