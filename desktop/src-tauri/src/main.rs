// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0.
// If a copy of the MPL was not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

// Evita la ventana de consola extra en Windows en release. No quitar.
#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

fn main() {
    file_transfer_desktop_lib::run()
}
