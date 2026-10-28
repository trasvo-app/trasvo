# Protocolo v1

Contrato único entre la app de PC (Rust, `ft-protocol` + `ft-transfer`) y la de Android (Dart, `lib/domain/protocol`). Los vectores de `protocol/test-vectors/` deben pasar en ambos lados.

## Transporte
TCP. Cada dispositivo escucha en el puerto **47520** (si está ocupado, uno libre; la app muestra el real). Quien inicia la conexión presenta el código del que escucha.

## Encuadre
Cada frame es:

| Bytes | Contenido |
| --- | --- |
| 4 | `u32` big-endian: longitud del resto (tipo + carga) |
| 1 | Tipo: `0` control (JSON UTF-8), `1` datos (bytes del archivo en curso) |
| n | Carga |

Límites: control ≤ 1 MiB; datos ≤ 256 KiB por frame. Un frame de longitud 0 o mayor al límite cierra la conexión.

## Mensajes de control
Campo `type` en `snake_case`.

| type | Campos | Quién |
| --- | --- | --- |
| `hello` | `version`, `device_id`, `device_name` | Ambos, primero |
| `pair_request` | `token`: código de 6 dígitos, token del enlace (32 hex) o vacío (pedir permiso); `fingerprint` (vacío en v1) | Cliente |
| `pair_accept` | `device_id` | Servidor |
| `pair_reject` | `reason`: `invalid_code`, `locked`, `version_mismatch`, `declined` | Servidor |
| `link_open` | `token` (32 hex, elegido por quien abre), `port` (donde escucha quien abre) | Cliente, tras `pair_accept` |
| `link_accept` | — | Servidor |
| `ping` | — | Ambos, por el enlace |
| `link_close` | — | Cualquiera, al tocar «Desconectar» |
| `transfer_offer` | `transfer_id`, `files[]` (`name`, `size`) | Emisor |
| `transfer_accept` | `transfer_id` | Receptor |
| `transfer_reject` | `transfer_id`, `reason` (`declined`) | Receptor |
| `file_end` | `transfer_id`, `index`, `hash` (SHA-256 hex) | Emisor, tras los bytes de cada archivo |
| `transfer_done` | `transfer_id` | Emisor, al final |
| `transfer_complete` | `transfer_id` | Receptor, si todo se verificó |
| `transfer_error` | `transfer_id`, `reason` | Cualquiera |
| `cancel` | `transfer_id` | Cualquiera |

## Flujo
```
Cliente (emisor)                       Servidor (receptor)
hello  ───────────────────────────────►
       ◄─────────────────────────────── hello
pair_request{token} ──────────────────►
       ◄─────────────── pair_accept | pair_reject
transfer_offer{files} ────────────────►   (el usuario decide, máx. 120 s)
       ◄──────────── transfer_accept | transfer_reject
por cada archivo:
  datos… (exactamente `size` bytes)  ─►
  file_end{index, hash} ──────────────►   (verifica SHA-256)
transfer_done ────────────────────────►
       ◄─────────────────────────────── transfer_complete | transfer_error
```
Una conexión emparejada puede llevar varias transferencias seguidas.

## Enlace persistente
Se empareja **una sola vez**, desde cualquiera de los dos lados, y quedan conectados para enviar en ambos sentidos hasta que alguno toca «Desconectar».

```
A (abre el enlace)                     B
hello / pair_request{código | ""} ────►   ("" = B le pregunta a su usuario, máx. 60 s)
       ◄─────────────── pair_accept | pair_reject
link_open{token, port} ───────────────►   (B guarda: IP de A + port, token)
       ◄─────────────────────────────── link_accept
ping ◄────────────────────────────────► ping      (cada 10 s; sin nada en 40 s = cortado)
link_close ───────────────────────────►            («Desconectar»; cualquiera de los dos)
```
- **Envíos:** cada transferencia abre su propia conexión y presenta el token del enlace en `pair_request`, en cualquier sentido. B le envía a A en la IP de la que llegó A y el `port` de `link_open`.
- **Sin código** (`token` vacío): solo sirve para abrir un enlace, nunca para mandar una oferta suelta. Se usa con los dispositivos encontrados en el Wi-Fi.
- **Cortes de red:** si el enlace se corta sin `link_close`, ambos muestran «Reconectando…». A (quien lo abrió) reintenta cada 3 s durante 10 min con el mismo token; B lo acepta como el mismo enlace. Si el otro lado ya no reconoce el token (`invalid_code`), se da por desconectado.
- Un enlace nuevo reemplaza al anterior, al que se le avisa con `link_close`.

## Búsqueda en el Wi-Fi
Cada app anuncia por mDNS / DNS-SD el servicio `_ftransfer._tcp` con su puerto y los TXT `id` (fijo por dispositivo), `name` y `v=1`. Encontrar un dispositivo no da acceso: hay que abrir un enlace con código o con el permiso del otro usuario.

## Nombres de archivo
`name` es una ruta relativa con `/` (las carpetas conservan su estructura). El receptor rechaza rutas absolutas, `..`, `\`, `:` y otros caracteres prohibidos en Windows, y nombres reservados (`CON`, `NUL`…). Si el destino existe, guarda como `nombre (1).ext`. Mientras recibe escribe `*.part` y solo renombra al verificar el hash.

## Seguridad (v1)
- Código de 6 dígitos por sesión; comparación en tiempo constante.
- Tras 10 códigos incorrectos el receptor rechaza todo emparejamiento (`locked`) hasta reiniciar la app. Los tokens de enlace (128 bits) no cuentan para ese bloqueo.
- Conectarse sin código exige que el otro usuario acepte, y solo abre un enlace.
- El receptor siempre pregunta al usuario antes de guardar.
- **Pendiente:** cifrado TLS con huella del certificado en el QR (`fingerprint`). En v1 el tráfico viaja sin cifrar dentro del Wi-Fi.

## Versionado
`version` es un entero. Si difiere, el servidor responde `pair_reject` con `reason = "version_mismatch"`.
