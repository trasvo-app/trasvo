# Product

<!-- impeccable:product-schema 1 -->

## Platform

adaptive

Sitio web estático (`web/`) más dos apps nativas: Windows (Tauri) y Android (Flutter).

## Stack

- Apps: ya existen (ver `docs/architecture.md`).
- Sitio: delegado. HTML/CSS estático sin paso de build, publicado en GitHub Pages; binarios en GitHub Releases.

## Users

Personas hispanohablantes (primero Latinoamérica) con una PC con Windows y un celular Android, que quieren pasar fotos, videos y documentos entre los dos sin cable, sin nube y sin crear cuentas. Usuarios comunes, no técnicos: instalan desde un enlace, sin tienda ni firma de código.

## Product Purpose

Pasar archivos entre PC y celular por el mismo Wi-Fi, directo de un equipo al otro. Se conectan una sola vez (QR, IP o detección automática «Cerca») y quedan enlazados en ambos sentidos hasta tocar «Desconectar». Éxito: instalar y mandar el primer archivo en minutos sin ayuda.

## Positioning

Directo y local: los archivos nunca salen de tu red, sin cuenta, sin anuncios, sin rastreo, código abierto. El receptor siempre confirma antes de guardar.

## Operating Context

- Casa u oficina con un router; la PC suele ir por cable y el celular por Wi-Fi.
- Instalación sin firma: SmartScreen en Windows y el aviso de «apps desconocidas» / Play Protect en Android. El Firewall de Windows pregunta la primera vez que la app escucha.
- Distribución: GitHub Releases (setup .exe NSIS por usuario, APK universal firmado). Play Store más adelante.

## Capabilities and Constraints

- Hoy: Wi-Fi (misma red), QR, IP + código de 6 dígitos, «Cerca» (mDNS) con aceptación, enlace persistente con reconexión, carpetas, verificación SHA-256, carpeta de descargas configurable en la PC, app móvil solo vertical.
- No hay todavía: cifrado TLS (el tráfico va sin cifrar dentro del Wi-Fi), cable, Bluetooth, hotspot, transferencias en segundo plano en Android, «Compartir con…», inglés, iPhone, macOS/Linux.
- Requisitos: Windows 10/11 (WebView2), Android 7.0+ (API 24).
- Nombre: Trasvo (marca inventada, de «trasvasar»). Será parte de una marca madre aún sin nombre. GitHub: organización trasvo-app, repo trasvo.

## Brand Commitments

- Responsable y contacto legal: alias provisorio con correo trasvoapp@gmail.com.
- Licencia open source MPL-2.0 (la GPL choca con ML Kit, librería cerrada que usa el escáner de QR).
- Voz: español neutro con «tú» (igual que las apps), frases cortas, sin jerga técnica. Nunca decir «seguro» o «cifrado» sin matices.
- Logo: arco con un rombo (el archivo) que sale despedido; fuente en design/logo/. Estilo del sitio: el estándar de la categoría (elegido por el usuario), vara de terminación localsend.org.

## Evidence on Hand

- La app real funcionando (capturas de PC y de un celular Android se pueden tomar).
- No hay usuarios, reseñas, descargas ni prensa: no inventar testimonios, cifras ni logos de terceros.

## Product Principles

1. Nada sale de tu red: ni servidores, ni cuentas, ni telemetría.
2. Siempre se pregunta antes de guardar o de conectar sin código.
3. Instalable por cualquiera: cada aviso del sistema se explica con una imagen antes de que aparezca.
4. Honestidad sobre lo que falta (cifrado, segundo plano).

## Accessibility & Inclusion

Contraste WCAG AA, textos cortos, botones grandes; pensado también para adultos mayores.
