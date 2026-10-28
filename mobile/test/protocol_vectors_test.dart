// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0.
// If a copy of the MPL was not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_transfer/domain/protocol/codec.dart';
import 'package:file_transfer/domain/protocol/message.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final raw = File('../protocol/test-vectors/control-messages.json').readAsStringSync();
  final vectors = (jsonDecode(raw) as List<dynamic>).cast<Map<String, dynamic>>();

  for (final v in vectors) {
    test('vector ${v['name']} roundtrips', () {
      final json = v['json'] as Map<String, dynamic>;
      final message = Message.fromJson(json);
      expect(message.toJson(), json);

      final bytes = encodeMessage(message);
      final (back, used) = decodeFrame(bytes);
      expect((back as ControlFrame).message.toJson(), json);
      expect(used, bytes.length);
    });
  }

  test('data frames roundtrip with the same header as Rust', () {
    final bytes = encodeFrame(DataFrame(Uint8List.fromList([0, 1, 2, 255])));
    expect(bytes.sublist(0, 5), [0, 0, 0, 5, frameData]);
    final (frame, used) = decodeFrame(bytes);
    expect((frame as DataFrame).bytes, [0, 1, 2, 255]);
    expect(used, 9);
  });

  test('incomplete frame is reported', () {
    expect(() => decodeFrame(Uint8List.fromList([0, 0])), throwsA(isA<IncompleteFrame>()));
    expect(() => decodeFrame(Uint8List.fromList([0, 0, 0, 5, 0])),
        throwsA(isA<IncompleteFrame>()));
  });

  test('oversized frames are rejected', () {
    final header = Uint8List(4)..buffer.asByteData().setUint32(0, maxFrameBody + 1);
    expect(() => decodeFrame(header), throwsA(isA<MessageTooLarge>()));
    expect(() => encodeFrame(DataFrame(Uint8List(maxChunkBytes + 1))),
        throwsA(isA<MessageTooLarge>()));
  });
}
