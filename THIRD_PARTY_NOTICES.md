# Componentes de terceros

Trasvo se distribuye bajo la [Mozilla Public License 2.0](LICENSE). Incluye o usa los siguientes componentes de terceros, cada uno bajo su propia licencia. Los derechos de autor pertenecen a sus respectivos autores.

Esta lista cubre las dependencias directas. Las dependencias indirectas (y sus versiones exactas) están en `desktop/src-tauri/Cargo.lock`, `desktop/package-lock.json` y `mobile/pubspec.lock`; el texto completo de la licencia de cada una está en su repositorio y dentro del paquete publicado en crates.io, npm o pub.dev.

## App de PC (Rust)

| Componente | Licencia |
| --- | --- |
| [tauri](https://github.com/tauri-apps/tauri) y `tauri-plugin-dialog` | MIT o Apache-2.0 |
| [tokio](https://github.com/tokio-rs/tokio) | MIT |
| [serde](https://github.com/serde-rs/serde) y `serde_json` | MIT o Apache-2.0 |
| [thiserror](https://github.com/dtolnay/thiserror) | MIT o Apache-2.0 |
| [rand](https://github.com/rust-random/rand) | MIT o Apache-2.0 |
| [sha2](https://github.com/RustCrypto/hashes) | MIT o Apache-2.0 |
| [mdns-sd](https://github.com/keepsimple1/mdns-sd) | MIT o Apache-2.0 |

Algunas dependencias indirectas de Tauri (por ejemplo `option-ext`, `cssparser`, `selectors`) están bajo MPL-2.0. Se usan sin modificar.

## App de PC (interfaz web)

| Componente | Licencia |
| --- | --- |
| [React y React DOM](https://github.com/facebook/react) | MIT |
| [@tauri-apps/api](https://github.com/tauri-apps/tauri) y `@tauri-apps/plugin-dialog` | MIT o Apache-2.0 |
| [qrcode](https://github.com/soldair/node-qrcode) | MIT |

## App del celular (Flutter / Dart)

| Componente | Licencia |
| --- | --- |
| [Flutter SDK](https://github.com/flutter/flutter) y Material Icons | BSD-3-Clause; Material Icons, Apache-2.0 |
| [cupertino_icons](https://pub.dev/packages/cupertino_icons) | MIT |
| [shared_preferences](https://pub.dev/packages/shared_preferences), [path_provider](https://pub.dev/packages/path_provider), [crypto](https://pub.dev/packages/crypto) | BSD-3-Clause |
| [mobile_scanner](https://pub.dev/packages/mobile_scanner) | BSD-3-Clause |
| [photo_manager](https://pub.dev/packages/photo_manager) | Apache-2.0 |
| [file_picker](https://pub.dev/packages/file_picker) | MIT |
| [nsd](https://pub.dev/packages/nsd) | MIT |

La app del celular puede mostrar las licencias de todos los paquetes de Flutter que incluye desde el propio sistema de licencias de Flutter.

## Componentes con condiciones propias (no son de código abierto)

- **Google ML Kit** (lector de códigos QR, incluido por `mobile_scanner`): se rige por las [condiciones de ML Kit](https://developers.google.com/ml-kit/terms) y las de Google Play Services.
- **Microsoft Edge WebView2**: el instalador de Windows lo descarga si hace falta. Se rige por las condiciones de Microsoft.

## Sitio web

- **Geist** (tipografía), Copyright 2024 The Geist Project Authors, bajo la [SIL Open Font License 1.1](web/assets/fonts/OFL.txt).

## Marcas

Windows, SmartScreen y WebView2 son marcas de Microsoft Corporation. Android, Google Play y Play Protect son marcas de Google LLC. GitHub es marca de GitHub, Inc. Trasvo no está afiliada ni respaldada por ellas.
