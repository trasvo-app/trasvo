// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0.
// If a copy of the MPL was not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

//! Dos motores en la misma máquina: uno recibe, otro envía, por TCP real.

use std::fs;
use std::net::SocketAddr;
use std::path::{Path, PathBuf};

use ft_transfer::{new_transfer_id, Direction, Engine, EngineConfig, Event, TransferError};
use tokio::sync::mpsc;

const CODE: &str = "123456";

fn engine(name: &str, code: &str, dir: &Path) -> (Engine, mpsc::UnboundedReceiver<Event>) {
    let (tx, rx) = mpsc::unbounded_channel();
    let config = EngineConfig {
        device_id: format!("{name}-id"),
        device_name: name.to_owned(),
        code: code.to_owned(),
        download_dir: dir.to_path_buf(),
    };
    (Engine::new(config, tx), rx)
}

/// Receptor escuchando en localhost que acepta (o rechaza) todo lo que le ofrecen.
/// Devuelve su dirección y un canal con sus eventos.
async fn receiver(dir: &Path, accept: bool) -> (Engine, SocketAddr, mpsc::UnboundedReceiver<Event>) {
    let (engine, mut events) = engine("PC", CODE, dir);
    let addr = engine.listen("127.0.0.1:0".parse().unwrap()).await.unwrap();
    let (tx, rx) = mpsc::unbounded_channel();
    let responder = engine.clone();
    tokio::spawn(async move {
        while let Some(event) = events.recv().await {
            if let Event::Offer { transfer_id, .. } = &event {
                assert!(responder.respond(transfer_id, accept));
            }
            let _ = tx.send(event);
        }
    });
    (engine, addr, rx)
}

fn sender() -> (Engine, mpsc::UnboundedReceiver<Event>, tempfile::TempDir) {
    let dir = tempfile::tempdir().unwrap();
    let (engine, events) = engine("Celular", "000000", dir.path());
    (engine, events, dir)
}

fn pseudo_random(len: usize) -> Vec<u8> {
    let mut x: u32 = 2463534242;
    (0..len)
        .map(|_| {
            x ^= x << 13;
            x ^= x >> 17;
            x ^= x << 5;
            x as u8
        })
        .collect()
}

fn drain(rx: &mut mpsc::UnboundedReceiver<Event>) -> Vec<Event> {
    let mut out = Vec::new();
    while let Ok(event) = rx.try_recv() {
        out.push(event);
    }
    out
}

#[tokio::test(flavor = "multi_thread")]
async fn sends_files_and_folders_end_to_end() {
    let downloads = tempfile::tempdir().unwrap();
    let (_receiver, addr, mut receiver_events) = receiver(downloads.path(), true).await;

    let src = tempfile::tempdir().unwrap();
    // Más grande que un trozo (256 KiB) y no múltiplo exacto.
    let big = pseudo_random(1024 * 1024 + 123);
    fs::write(src.path().join("video.bin"), &big).unwrap();
    fs::write(src.path().join("vacio.txt"), b"").unwrap();
    fs::create_dir_all(src.path().join("Album").join("Día 1")).unwrap();
    fs::write(src.path().join("Album").join("Día 1").join("foto.jpg"), b"jpeg!").unwrap();

    let (sender, mut sender_events, _dir) = sender();
    let paths: Vec<PathBuf> = ["video.bin", "vacio.txt", "Album"]
        .iter()
        .map(|p| src.path().join(p))
        .collect();
    let id = new_transfer_id();
    sender.send(id.clone(), addr, CODE.into(), paths).await.unwrap();

    assert_eq!(fs::read(downloads.path().join("video.bin")).unwrap(), big);
    assert_eq!(fs::read(downloads.path().join("vacio.txt")).unwrap(), b"");
    assert_eq!(
        fs::read(downloads.path().join("Album").join("Día 1").join("foto.jpg")).unwrap(),
        b"jpeg!"
    );

    let sent = drain(&mut sender_events);
    assert!(matches!(sent.first(), Some(Event::Waiting { peer_name, file_count: 3, .. }) if peer_name == "PC"));
    assert!(sent.iter().any(|e| matches!(e,
        Event::Completed { transfer_id, direction: Direction::Send, .. } if *transfer_id == id)));
    let last_progress = sent.iter().rev().find_map(|e| match e {
        Event::Progress { bytes_done, bytes_total, .. } => Some((*bytes_done, *bytes_total)),
        _ => None,
    });
    let total = big.len() as u64 + 5;
    assert_eq!(last_progress, Some((total, total)));

    // El receptor avisa cuando termina: esperamos su evento final.
    loop {
        match receiver_events.recv().await.unwrap() {
            Event::Completed { direction: Direction::Receive, files, .. } => {
                assert_eq!(files.len(), 3);
                break;
            }
            Event::Failed { reason, .. } => panic!("receiver failed: {reason}"),
            _ => {}
        }
    }
    // No quedan archivos temporales.
    let leftovers: Vec<_> = walk(downloads.path())
        .into_iter()
        .filter(|p| p.extension().is_some_and(|e| e == "part"))
        .collect();
    assert!(leftovers.is_empty(), "{leftovers:?}");
}

fn walk(dir: &Path) -> Vec<PathBuf> {
    let mut out = Vec::new();
    for entry in fs::read_dir(dir).unwrap() {
        let path = entry.unwrap().path();
        if path.is_dir() {
            out.extend(walk(&path));
        } else {
            out.push(path);
        }
    }
    out
}

#[tokio::test(flavor = "multi_thread")]
async fn existing_files_are_not_overwritten() {
    let downloads = tempfile::tempdir().unwrap();
    fs::write(downloads.path().join("nota.txt"), b"vieja").unwrap();
    let (_receiver, addr, _events) = receiver(downloads.path(), true).await;

    let src = tempfile::tempdir().unwrap();
    fs::write(src.path().join("nota.txt"), b"nueva").unwrap();
    let (sender, _events, _dir) = sender();
    sender
        .send(new_transfer_id(), addr, CODE.into(), vec![src.path().join("nota.txt")])
        .await
        .unwrap();

    assert_eq!(fs::read(downloads.path().join("nota.txt")).unwrap(), b"vieja");
    assert_eq!(fs::read(downloads.path().join("nota (1).txt")).unwrap(), b"nueva");
}

#[tokio::test(flavor = "multi_thread")]
async fn wrong_code_is_rejected_and_nothing_is_written() {
    let downloads = tempfile::tempdir().unwrap();
    let (_receiver, addr, _events) = receiver(downloads.path(), true).await;

    let src = tempfile::tempdir().unwrap();
    fs::write(src.path().join("a.txt"), b"a").unwrap();
    let (sender, mut sender_events, _dir) = sender();
    let error = sender
        .send(new_transfer_id(), addr, "999999".into(), vec![src.path().join("a.txt")])
        .await
        .unwrap_err();

    assert!(matches!(error, TransferError::WrongCode), "{error:?}");
    assert!(fs::read_dir(downloads.path()).unwrap().next().is_none());
    assert!(drain(&mut sender_events).iter().any(|e| matches!(e,
        Event::Failed { reason, .. } if reason == "invalid_code")));
}

#[tokio::test(flavor = "multi_thread")]
async fn declined_offer_is_reported_to_the_sender() {
    let downloads = tempfile::tempdir().unwrap();
    let (_receiver, addr, _events) = receiver(downloads.path(), false).await;

    let src = tempfile::tempdir().unwrap();
    fs::write(src.path().join("a.txt"), b"a").unwrap();
    let (sender, _events, _dir) = sender();
    let error = sender
        .send(new_transfer_id(), addr, CODE.into(), vec![src.path().join("a.txt")])
        .await
        .unwrap_err();

    assert!(matches!(&error, TransferError::Rejected(r) if r == "declined"), "{error:?}");
    assert_eq!(error.code(), "declined");
    assert!(fs::read_dir(downloads.path()).unwrap().next().is_none());
}

#[tokio::test(flavor = "multi_thread")]
async fn check_pairing_returns_the_peer_name() {
    let downloads = tempfile::tempdir().unwrap();
    let (_receiver, addr, _events) = receiver(downloads.path(), true).await;
    let (sender, _events, _dir) = sender();

    assert_eq!(sender.check_pairing(addr, CODE).await.unwrap(), "PC");
    assert!(matches!(
        sender.check_pairing(addr, "000001").await,
        Err(TransferError::WrongCode)
    ));
}

#[tokio::test(flavor = "multi_thread")]
async fn too_many_wrong_codes_lock_pairing() {
    let downloads = tempfile::tempdir().unwrap();
    let (_receiver, addr, _events) = receiver(downloads.path(), true).await;
    let (sender, _events, _dir) = sender();

    for _ in 0..10 {
        let _ = sender.check_pairing(addr, "000000").await;
    }
    // Ni siquiera el código correcto sirve ya: protege contra probar los 10⁶ códigos.
    assert!(matches!(sender.check_pairing(addr, CODE).await, Err(TransferError::Locked)));
}

/// Archivo grande en una carpeta temporal, para tener tiempo de cancelar a mitad.
fn big_file() -> (tempfile::TempDir, PathBuf) {
    let src = tempfile::tempdir().unwrap();
    let path = src.path().join("grande.bin");
    fs::write(&path, vec![7u8; 48 * 1024 * 1024]).unwrap();
    (src, path)
}

fn no_part_files(dir: &Path) {
    let files = walk(dir);
    assert!(files.is_empty(), "quedaron archivos: {files:?}");
}

#[tokio::test(flavor = "multi_thread")]
async fn sender_can_cancel_mid_transfer() {
    let downloads = tempfile::tempdir().unwrap();
    let (_receiver, addr, mut receiver_events) = receiver(downloads.path(), true).await;
    let (src, path) = big_file();

    let (sender, mut sender_events, _dir) = sender();
    let id = new_transfer_id();
    // Cancela apenas empieza a mandar el primer archivo.
    let canceller = sender.clone();
    let watched = id.clone();
    tokio::spawn(async move {
        while let Some(event) = sender_events.recv().await {
            if matches!(event, Event::Progress { .. }) {
                assert!(canceller.cancel(&watched));
                break;
            }
        }
    });

    let error = sender.send(id, addr, CODE.into(), vec![path]).await.unwrap_err();
    assert!(matches!(error, TransferError::Cancelled), "{error:?}");

    loop {
        match receiver_events.recv().await.unwrap() {
            Event::Failed { reason, direction: Direction::Receive, .. } => {
                assert_eq!(reason, "cancelled");
                break;
            }
            Event::Completed { .. } => panic!("should not complete"),
            _ => {}
        }
    }
    no_part_files(downloads.path());
    drop(src);
}

#[tokio::test(flavor = "multi_thread")]
async fn receiver_can_cancel_mid_transfer() {
    let downloads = tempfile::tempdir().unwrap();
    let (receiver, mut events) = engine("PC", CODE, downloads.path());
    let addr = receiver.listen("127.0.0.1:0".parse().unwrap()).await.unwrap();
    let (done_tx, mut done_rx) = mpsc::unbounded_channel();
    let control = receiver.clone();
    tokio::spawn(async move {
        while let Some(event) = events.recv().await {
            match &event {
                Event::Offer { transfer_id, .. } => assert!(control.respond(transfer_id, true)),
                // Cancela en cuanto empieza a llegar el archivo.
                Event::Progress { transfer_id, .. } => {
                    control.cancel(transfer_id);
                }
                Event::Failed { .. } | Event::Completed { .. } => {
                    let _ = done_tx.send(event.clone());
                }
                _ => {}
            }
        }
    });
    let (src, path) = big_file();

    let (sender, _events, _dir) = sender();
    let error = sender.send(new_transfer_id(), addr, CODE.into(), vec![path]).await.unwrap_err();
    assert!(matches!(error, TransferError::Cancelled), "{error:?}");

    assert!(matches!(done_rx.recv().await, Some(Event::Failed { reason, .. }) if reason == "cancelled"));
    no_part_files(downloads.path());
    drop(src);
}

#[tokio::test(flavor = "multi_thread")]
async fn cancelling_a_pending_offer_rejects_it() {
    let downloads = tempfile::tempdir().unwrap();
    let (receiver, mut events) = engine("PC", CODE, downloads.path());
    let addr = receiver.listen("127.0.0.1:0".parse().unwrap()).await.unwrap();
    let control = receiver.clone();
    tokio::spawn(async move {
        while let Some(event) = events.recv().await {
            if let Event::Offer { transfer_id, .. } = event {
                assert!(control.cancel(&transfer_id));
            }
        }
    });

    let src = tempfile::tempdir().unwrap();
    fs::write(src.path().join("a.txt"), b"a").unwrap();
    let (sender, _events, _dir) = sender();
    let error = sender
        .send(new_transfer_id(), addr, CODE.into(), vec![src.path().join("a.txt")])
        .await
        .unwrap_err();
    assert_eq!(error.code(), "declined");
}

#[tokio::test(flavor = "multi_thread")]
async fn unreachable_address_fails_fast() {
    let (sender, _events, _dir) = sender();
    let closed = std::net::TcpListener::bind("127.0.0.1:0").unwrap().local_addr().unwrap();
    let error = sender.check_pairing(closed, CODE).await.unwrap_err();
    assert_eq!(error.code(), "unreachable");
}
