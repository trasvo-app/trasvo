// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0.
// If a copy of the MPL was not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

/** Texto para cada código de error del backend. */
const reasons: Record<string, string> = {
  declined: "El otro dispositivo lo rechazó.",
  invalid_code: "El código no es correcto.",
  invalid_ip: "Revisa la IP: debe verse como 192.168.1.20.",
  invalid_port: "El puerto debe ser un número entre 1 y 65535.",
  unreachable:
    "No encontramos el dispositivo. Revisa que la app esté abierta y que ambos estén en el mismo Wi-Fi.",
  locked: "Demasiados intentos con código incorrecto. Reinicia la app del otro dispositivo.",
  version_mismatch: "Las apps tienen versiones distintas. Actualiza ambas.",
  timeout: "El otro dispositivo no respondió a tiempo.",
  hash_mismatch: "Un archivo llegó dañado. Vuelve a intentarlo.",
  cancelled: "Se canceló la transferencia.",
  invalid_name: "Uno de los archivos tiene un nombre no válido.",
  empty: "No hay archivos para enviar.",
  io: "No se pudo leer o guardar un archivo.",
  protocol: "Se cortó la comunicación con el otro dispositivo.",
  not_connected: "No hay ningún celular conectado. Conéctalo primero.",
  invalid_folder: "Esa carpeta no existe o no se puede usar.",
};

export function reasonText(code: string | undefined) {
  return (code && reasons[code]) ?? "Algo salió mal. Vuelve a intentarlo.";
}
