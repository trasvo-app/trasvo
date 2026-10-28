// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0.
// If a copy of the MPL was not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

//! Búsqueda automática en el Wi-Fi (mDNS / DNS-SD): cada app anuncia el servicio
//! `_ftransfer._tcp` y busca a las demás. Encontrar un dispositivo no da acceso a nada:
//! para conectarse hay que emparejar igual (ver docs/protocol.md).

use std::collections::HashMap;
use std::net::Ipv4Addr;
use std::sync::{Arc, Mutex};

use mdns_sd::{IfKind, ServiceDaemon, ServiceEvent, ServiceInfo};
use serde::Serialize;

pub const SERVICE_TYPE: &str = "_ftransfer._tcp.local.";

#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct NearbyDevice {
    pub id: String,
    pub name: String,
    pub ip: String,
    pub port: u16,
}

type Devices = Arc<Mutex<HashMap<String, NearbyDevice>>>;

/// Anuncio + búsqueda. Al soltarse deja de anunciar.
pub struct Discovery {
    daemon: ServiceDaemon,
    devices: Devices,
}

impl Discovery {
    /// Anuncia este dispositivo en `ip:port` y busca a los demás. `on_change` recibe
    /// la lista completa cada vez que cambia (desde otro hilo).
    pub fn start(
        id: &str,
        name: &str,
        ip: Ipv4Addr,
        port: u16,
        on_change: impl Fn(Vec<NearbyDevice>) + Send + 'static,
    ) -> Result<Self, mdns_sd::Error> {
        let daemon = ServiceDaemon::new()?;
        let _ = daemon.disable_interface(IfKind::IPv6);

        let properties = [("id", id), ("name", name), ("v", "1")];
        let host = format!("{id}.local.");
        let address = std::net::IpAddr::V4(ip);
        let info = ServiceInfo::new(SERVICE_TYPE, id, &host, address, port, &properties[..])?;
        daemon.register(info)?;

        let devices: Devices = Arc::default();
        let events = daemon.browse(SERVICE_TYPE)?;
        let own_id = id.to_owned();
        let found = devices.clone();
        std::thread::spawn(move || {
            while let Ok(event) = events.recv() {
                let changed = match event {
                    ServiceEvent::ServiceResolved(service) => {
                        let id = service.get_property_val_str("id").unwrap_or_default();
                        let Some(addr) = pick_ipv4(&service.get_addresses_v4(), ip) else {
                            continue;
                        };
                        if id.is_empty() || id == own_id {
                            continue;
                        }
                        let device = NearbyDevice {
                            id: id.to_owned(),
                            name: service.get_property_val_str("name").unwrap_or(id).to_owned(),
                            ip: addr.to_string(),
                            port: service.get_port(),
                        };
                        let mut map = found.lock().unwrap();
                        // Un anuncio viejo de la misma app (cerrada sin despedirse) queda
                        // un rato en la red: en la misma IP y puerto vale el más nuevo.
                        let fullname = service.get_fullname();
                        map.retain(|name, d| {
                            name == fullname || (d.ip != device.ip || d.port != device.port)
                        });
                        map.insert(fullname.to_owned(), device.clone()) != Some(device)
                    }
                    ServiceEvent::ServiceRemoved(_, fullname) => {
                        found.lock().unwrap().remove(&fullname).is_some()
                    }
                    _ => false,
                };
                if changed {
                    on_change(snapshot(&found));
                }
            }
        });
        Ok(Self { daemon, devices })
    }

    pub fn devices(&self) -> Vec<NearbyDevice> {
        snapshot(&self.devices)
    }
}

impl Drop for Discovery {
    fn drop(&mut self) {
        let _ = self.daemon.shutdown();
    }
}

fn snapshot(devices: &Devices) -> Vec<NearbyDevice> {
    let mut list: Vec<_> = devices.lock().unwrap().values().cloned().collect();
    list.sort_by(|a, b| a.name.cmp(&b.name).then_with(|| a.id.cmp(&b.id)));
    list
}

/// Si el otro anuncia varias IPs, la de nuestra misma red (/24) primero.
fn pick_ipv4<'a>(
    addrs: impl IntoIterator<Item = &'a Ipv4Addr>,
    ours: Ipv4Addr,
) -> Option<Ipv4Addr> {
    let addrs: Vec<Ipv4Addr> = addrs.into_iter().copied().collect();
    let same_net = |a: &Ipv4Addr| a.octets()[..3] == ours.octets()[..3];
    addrs.iter().copied().find(same_net).or_else(|| addrs.first().copied())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn prefers_an_address_in_our_network() {
        let ours = Ipv4Addr::new(10, 10, 1, 203);
        let vpn = Ipv4Addr::new(26, 49, 86, 98);
        let lan = Ipv4Addr::new(10, 10, 1, 205);
        assert_eq!(pick_ipv4(&[vpn, lan], ours), Some(lan));
        assert_eq!(pick_ipv4(&[vpn], ours), Some(vpn));
        assert_eq!(pick_ipv4(&[], ours), None);
    }
}
