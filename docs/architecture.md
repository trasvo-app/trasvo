# Arquitectura

## Idea central
Un solo protocolo, varios transportes. Wi-Fi, cable (USB tethering / `adb reverse`) y Bluetooth solo cambian cómo llegan los bytes; el motor de transferencia es el mismo.

```
UI  ──►  commands (Tauri / Flutter)  ──►  transfer (motor)  ──►  protocol  ──►  Transport
                                                                                 ├─ wifi (TCP + TLS)
                                                                                 ├─ usb  (reutiliza wifi)
                                                                                 └─ bluetooth (opcional)
```

## Reglas de dependencia
- `core` no depende de nada del proyecto ni hace I/O: entidades y errores.
- `protocol` depende solo de `core`: codifica y decodifica mensajes.
- `transfer`, `discovery`, `pairing` dependen de `core` y `protocol`.
- `transports` implementa el trait `Transport`; se registra en un único lugar.
- La UI nunca toca sockets; habla con la capa de comandos.

## Desktop (`desktop/src-tauri/crates`)
| Crate | Qué hace |
| --- | --- |
| `core` | Constantes (versión, puerto) y errores del protocolo |
| `protocol` | Mensajes y frames, sin I/O |
| `pairing` | Códigos de 6 dígitos |
| `transfer` | Motor: servidor que recibe, cliente que envía, enlace persistente, eventos |
| `transports` | IP local (y más adelante USB/Bluetooth) |
| `discovery` | Búsqueda automática en el Wi-Fi (mDNS / DNS-SD) |

La app Tauri (`src-tauri/src`) solo arranca el motor, reenvía sus eventos al frontend (`transfer-event`) y expone comandos.

Para probar sin celular: `cargo run -p ft-transfer --example send -- <ip:puerto> <código> <archivos…>`.

## Mobile (`mobile/lib`)
`core` (tema, router, errores), `domain` (entidades e interfaces), `data` (transportes, mDNS, almacenamiento), `features/<x>/{presentation,application}`.

## Seguridad
Emparejamiento por QR/IP con token de un solo uso y huella del certificado; TLS autofirmado con pinning; confirmación en pantalla al recibir.
