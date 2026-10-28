// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0.
// If a copy of the MPL was not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

//! Nombres de archivo: qué se ofrece al enviar y dónde se guarda al recibir.

use std::fs;
use std::io;
use std::path::{Component, Path, PathBuf};

use crate::TransferError;

/// Un archivo listo para enviar: dónde está y cómo se llamará del otro lado.
#[derive(Debug, Clone)]
pub struct OutgoingFile {
    pub path: PathBuf,
    /// Ruta relativa con `/`; las carpetas conservan su estructura.
    pub name: String,
    pub size: u64,
}

/// Expande carpetas (recursivo) y devuelve la lista plana de archivos a enviar.
pub fn collect(paths: &[PathBuf]) -> Result<Vec<OutgoingFile>, TransferError> {
    let mut out = Vec::new();
    for path in paths {
        let meta = fs::metadata(path)?;
        let base = path
            .file_name()
            .and_then(|n| n.to_str())
            .ok_or_else(|| TransferError::InvalidName(path.display().to_string()))?
            .to_owned();
        if meta.is_dir() {
            walk(path, &base, &mut out)?;
        } else {
            out.push(OutgoingFile { path: path.clone(), name: base, size: meta.len() });
        }
    }
    Ok(out)
}

fn walk(dir: &Path, prefix: &str, out: &mut Vec<OutgoingFile>) -> io::Result<()> {
    let mut entries: Vec<_> = fs::read_dir(dir)?.collect::<Result<_, _>>()?;
    entries.sort_by_key(|e| e.file_name());
    for entry in entries {
        let kind = entry.file_type()?;
        let Some(name) = entry.file_name().to_str().map(str::to_owned) else {
            continue; // Nombres no UTF-8: se omiten.
        };
        let rel = format!("{prefix}/{name}");
        if kind.is_dir() {
            walk(&entry.path(), &rel, out)?;
        } else if kind.is_file() {
            out.push(OutgoingFile { path: entry.path(), name: rel, size: entry.metadata()?.len() });
        }
        // Los enlaces simbólicos se omiten a propósito.
    }
    Ok(())
}

const RESERVED: &[&str] = &[
    "CON", "PRN", "AUX", "NUL", "COM1", "COM2", "COM3", "COM4", "COM5", "COM6", "COM7", "COM8",
    "COM9", "LPT1", "LPT2", "LPT3", "LPT4", "LPT5", "LPT6", "LPT7", "LPT8", "LPT9",
];

/// Convierte el nombre que manda el otro lado en una ruta relativa segura.
///
/// Rechaza rutas absolutas, `..`, separadores de Windows, caracteres prohibidos
/// y nombres reservados, para que nadie pueda escribir fuera de la carpeta destino.
pub fn sanitize(name: &str) -> Result<PathBuf, TransferError> {
    let invalid = || TransferError::InvalidName(name.to_owned());
    if name.is_empty() || name.len() > 1024 {
        return Err(invalid());
    }
    let mut out = PathBuf::new();
    for part in name.split('/') {
        let bad_char = |c: char| c.is_control() || r#"<>:"\|?*"#.contains(c);
        let stem = part.split('.').next().unwrap_or("").to_ascii_uppercase();
        if part.is_empty()
            || part == "."
            || part == ".."
            || part.ends_with(['.', ' '])
            || part.chars().any(bad_char)
            || RESERVED.contains(&stem.as_str())
        {
            return Err(invalid());
        }
        out.push(part);
    }
    // Defensa extra: el resultado solo debe tener componentes normales.
    if out.components().any(|c| !matches!(c, Component::Normal(_))) {
        return Err(invalid());
    }
    Ok(out)
}

/// Ruta libre dentro de `dir`: si ya existe, agrega " (1)", " (2)"… antes de la extensión.
pub fn unique_destination(dir: &Path, rel: &Path) -> PathBuf {
    let first = dir.join(rel);
    if !first.exists() && !part_path(&first).exists() {
        return first;
    }
    let parent = first.parent().map(Path::to_path_buf).unwrap_or_else(|| dir.to_path_buf());
    let stem = first.file_stem().and_then(|s| s.to_str()).unwrap_or("archivo").to_owned();
    let ext = first.extension().and_then(|s| s.to_str()).map(|e| format!(".{e}"));
    (1..)
        .map(|n| parent.join(format!("{stem} ({n}){}", ext.as_deref().unwrap_or(""))))
        .find(|p| !p.exists() && !part_path(p).exists())
        .expect("infinite iterator")
}

/// Archivo temporal mientras se recibe; se renombra al verificar el hash.
pub fn part_path(dest: &Path) -> PathBuf {
    let mut name = dest.file_name().unwrap_or_default().to_os_string();
    name.push(".part");
    dest.with_file_name(name)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn sanitize_accepts_normal_names() {
        assert_eq!(sanitize("foto.jpg").unwrap(), PathBuf::from("foto.jpg"));
        assert_eq!(
            sanitize("Viaje/Día 1/video.mp4").unwrap(),
            PathBuf::from("Viaje").join("Día 1").join("video.mp4")
        );
    }

    #[test]
    fn sanitize_blocks_escapes_and_bad_names() {
        for bad in [
            "", "../x", "a/../b", "/etc/passwd", "C:/x", "C:\\x", "a\\b", "a//b", ".", "a/.",
            "con.txt", "NUL", "x?.jpg", "fin.", "fin ", "tab\there",
        ] {
            assert!(sanitize(bad).is_err(), "{bad:?}");
        }
    }

    #[test]
    fn unique_destination_avoids_overwrites() {
        let dir = tempfile::tempdir().unwrap();
        let rel = Path::new("foto.jpg");
        assert_eq!(unique_destination(dir.path(), rel), dir.path().join("foto.jpg"));
        fs::write(dir.path().join("foto.jpg"), b"x").unwrap();
        assert_eq!(unique_destination(dir.path(), rel), dir.path().join("foto (1).jpg"));
        fs::write(part_path(&dir.path().join("foto (1).jpg")), b"x").unwrap();
        assert_eq!(unique_destination(dir.path(), rel), dir.path().join("foto (2).jpg"));
    }

    #[test]
    fn collect_expands_folders_with_relative_names() {
        let dir = tempfile::tempdir().unwrap();
        let album = dir.path().join("Album");
        fs::create_dir_all(album.join("sub")).unwrap();
        fs::write(album.join("a.txt"), b"aa").unwrap();
        fs::write(album.join("sub").join("b.txt"), b"bbb").unwrap();
        let single = dir.path().join("solo.txt");
        fs::write(&single, b"s").unwrap();

        let files = collect(&[album, single]).unwrap();
        let names: Vec<_> = files.iter().map(|f| (f.name.as_str(), f.size)).collect();
        assert_eq!(names, [("Album/a.txt", 2), ("Album/sub/b.txt", 3), ("solo.txt", 1)]);
    }
}
