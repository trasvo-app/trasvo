# Desarrollo

## App de PC
```bash
cd desktop
npm install
npm run tauri dev
```
La primera vez compila todas las dependencias de Rust y tarda varios minutos; después abre en segundos.

## Inspeccionar la app real (Chrome DevTools MCP)
En compilaciones de desarrollo (`tauri dev`), la ventana abre el puerto de depuración de WebView2 en `127.0.0.1:9222` (ver `enable_devtools_port` en `desktop/src-tauri/src/lib.rs`; nunca se activa en release).

`.mcp.json` registra el servidor `desktop-app` (Chrome DevTools MCP) conectado a ese puerto. Con la app abierta, Claude Code puede ver la ventana, hacer clic y leer la consola de la app real, con el backend de Rust funcionando.

También sirve el inspector de Edge: abre `edge://inspect` y agrega `localhost:9222`.

## Probar envíos sin celular
Con la app abierta, mira el código en «Conectar» y desde `desktop/src-tauri`:
```bash
cargo run -p ft-transfer --example send -- 127.0.0.1:47520 <código> <ruta de un archivo o carpeta que exista>
```

## App del celular (Android)
Instalado en esta PC:
- Flutter en `<ruta-a-flutter>` (no está en el PATH: usa la ruta completa o agrégalo).
- JDK 21 (Temurin) y SDK de Android en `%LOCALAPPDATA%\Android\Sdk` (configurados con `flutter config`).
- Emulador `ft_pixel` (Pixel 7, Android 16).

```bash
cd mobile
flutter emulators --launch ft_pixel
flutter run
```

Probar con un teléfono real (recomendado): actívale la depuración USB, conéctalo y `flutter run -d <id>` (el id sale en `flutter devices`). Con la PC y el celular en el mismo Wi-Fi funcionan «Cerca», QR e IP, y el enlace en ambos sentidos.

Con el emulador, el enlace solo sirve en un sentido: cada lado le envía al otro en la IP desde la que llegó, y el emulador ve a la PC detrás de una NAT (`10.0.2.2`) y la PC lo ve a él como `127.0.0.1`.
- **Celular → PC:** en el celular, «IP» con `10.0.2.2` y el código de la PC.
- **PC → celular:** `adb forward tcp:47530 tcp:47520`, y en la PC conecta a `127.0.0.1:47530` con el código del celular.
- «Cerca» (mDNS) no cruza la NAT del emulador.

Lo recibido en el celular queda en `Download/Trasvo` (MediaStore; ver `DownloadsSaver.kt`).

## Motor del celular desde la terminal
`mobile/lib/data/transfer` es Dart puro (`dart:io`), así que se puede usar sin teléfono:
```bash
cd mobile
dart run tool/receive.dart <carpeta destino> [código] [puerto]   # acepta todo
dart run tool/send.dart <ip> <puerto> <código> <archivos o carpetas…>
```
Con esto se comprobó que PC (Rust) y celular (Dart) se entienden en ambos sentidos.

## Tests
```bash
cd desktop/src-tauri && cargo test --workspace
cd desktop && npm test
cd mobile && flutter test
```
