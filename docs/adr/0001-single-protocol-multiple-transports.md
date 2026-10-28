# ADR 0001: Un protocolo, varios transportes

**Estado:** aceptada

## Contexto
La app debe mover archivos por Wi-Fi, cable y Bluetooth. Implementar un motor de transferencia por cada medio triplica el código y los errores.

## Decisión
- Un único protocolo (`docs/protocol.md`) y un único motor de transferencia.
- Wi-Fi: TCP + TLS en el mismo router, con conexión automática (mDNS), por QR o por IP.
- Cable: USB tethering o `adb reverse`, que reutilizan el transporte Wi-Fi (sin MTP).
- Bluetooth: opcional, solo para descubrimiento, emparejamiento y archivos pequeños.
- Cada transporte implementa el trait `Transport`.

## Consecuencias
- Menos código y una sola ruta de pruebas.
- El modo cable exige activar USB tethering en el celular; la UI debe guiar el paso.
- Bluetooth queda para la última fase y puede omitirse si el hardware no lo tiene.
