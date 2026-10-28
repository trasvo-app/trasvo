// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0.
// If a copy of the MPL was not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

import 'dart:convert';
import 'dart:typed_data';

import 'message.dart';

/// Encuadre (ver docs/protocol.md): `u32` big-endian con la longitud del resto,
/// `u8` tipo (0 control JSON, 1 datos) y la carga.

const frameControl = 0;
const frameData = 1;
const maxChunkBytes = 256 * 1024;
const maxFrameBody = 1 + maxControlMessageBytes;

class IncompleteFrame implements Exception {
  const IncompleteFrame();
}

class MessageTooLarge implements Exception {
  const MessageTooLarge(this.size);

  final int size;
}

sealed class Frame {
  const Frame();
}

class ControlFrame extends Frame {
  const ControlFrame(this.message);

  final Message message;
}

class DataFrame extends Frame {
  const DataFrame(this.bytes);

  final Uint8List bytes;
}

Uint8List encodeFrame(Frame frame) {
  final (kind, payload) = switch (frame) {
    ControlFrame(:final message) => (frameControl, utf8.encode(jsonEncode(message.toJson()))),
    DataFrame(:final bytes) => (frameData, bytes),
  };
  final limit = kind == frameControl ? maxControlMessageBytes : maxChunkBytes;
  if (payload.length > limit) throw MessageTooLarge(payload.length);

  final out = Uint8List(5 + payload.length);
  ByteData.sublistView(out).setUint32(0, payload.length + 1);
  out[4] = kind;
  out.setRange(5, out.length, payload);
  return out;
}

Uint8List encodeMessage(Message message) => encodeFrame(ControlFrame(message));

/// Decodifica un frame. Devuelve el frame y los bytes consumidos.
(Frame, int) decodeFrame(Uint8List buffer) {
  if (buffer.length < 4) throw const IncompleteFrame();
  final length = ByteData.sublistView(buffer).getUint32(0);
  if (length == 0) throw const FormatException('Empty frame');
  if (length > maxFrameBody) throw MessageTooLarge(length);
  if (buffer.length < 4 + length) throw const IncompleteFrame();

  final kind = buffer[4];
  final payload = Uint8List.sublistView(buffer, 5, 4 + length);
  final frame = switch (kind) {
    frameControl => ControlFrame(
        Message.fromJson(jsonDecode(utf8.decode(payload)) as Map<String, dynamic>),
      ),
    frameData when payload.length <= maxChunkBytes => DataFrame(Uint8List.fromList(payload)),
    frameData => throw MessageTooLarge(payload.length),
    _ => throw FormatException('Unknown frame type $kind'),
  };
  return (frame, 4 + length);
}
