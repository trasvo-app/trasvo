# Publicar una versión

No hace falta Docker. Se compila en una PC con Windows que tenga Rust, Node 20+, Flutter y el JDK (ver `development.md`).

## Qué se publica

| Archivo | Qué es |
| --- | --- |
| `Trasvo-Setup-x64.exe` | Instalador NSIS de Windows, por usuario (sin administrador), en español. Silencioso con `/S`. |
| `Trasvo.apk` | APK universal firmado con la llave de release. |
| `SHA256SUMS.txt` | Huellas de los dos. |

Los nombres son fijos: la web enlaza a `releases/latest/download/<nombre>`, así que cada versión nueva queda enlazada sola.

## Pasos

1. Sube la versión en `desktop/src-tauri/tauri.conf.json` (`version`), `desktop/package.json` y `mobile/pubspec.yaml` (`version: X.Y.Z+N`, con `N` siempre mayor que el anterior).
2. Compila:
   ```bash
   cd desktop && npm run tauri build
   cd mobile && flutter build apk --release
   ```
3. Junta los archivos y calcula los hashes. Escribe `release/X.Y.Z/` y actualiza `web/assets/release.json` (versión, tamaños y SHA-256 que muestra la web):
   ```bash
   powershell -File scripts/release.ps1
   ```
4. Haz commit de `web/assets/release.json` y crea el tag `vX.Y.Z`.
5. En GitHub → Releases → *Draft a new release*: elige el tag, pega las novedades y sube los tres archivos de `release/X.Y.Z/`.
6. Haz push a `main`: el workflow `.github/workflows/pages.yml` publica `web/` en GitHub Pages.

## Llave de firma del APK

- Vive fuera del repo, en `<carpeta-de-llaves>\android-release.jks`, con su contraseña en `mobile/android/key.properties` (ignorado por git) y una copia en `<carpeta-de-llaves>\LEEME-android-release.txt`.
- **Si se pierde, no se pueden publicar actualizaciones**: Android rechaza un APK firmado con otra llave y los usuarios tendrían que desinstalar. Guarda una copia de esa carpeta fuera de la PC de compilación.
- Para Play Store más adelante: usar «Play App Signing» y subir esta llave como llave de subida.

## Primera publicación (una sola vez)

1. Crear la organización `trasvo-app` en GitHub y el repositorio público `trasvo`.
2. `git remote add origin https://github.com/trasvo-app/trasvo.git` y `git push -u origin main`.
3. Settings → Pages → *Source: GitHub Actions*.
4. Crear la release `v0.1.0` como en el paso 5.
