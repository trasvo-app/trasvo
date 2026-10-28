// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0.
// If a copy of the MPL was not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

import 'package:file_transfer/domain/protocol/pairing_uri.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses the QR the desktop app shows', () {
    final info = PairingInfo.tryParse(
      'ftransfer://pair?ip=192.168.1.20&port=47520&code=012345&name=PC+de+Ana+%26+Co',
    )!;
    expect(info.host, '192.168.1.20');
    expect(info.port, 47520);
    expect(info.code, '012345');
    expect(info.name, 'PC de Ana & Co');
  });

  test('rejects anything that is not a valid pairing QR', () {
    for (final raw in [
      'https://example.com',
      'ftransfer://other?ip=1.2.3.4&code=123456',
      'ftransfer://pair?ip=999.1.1.1&code=123456',
      'ftransfer://pair?ip=1.2.3.4&code=12',
      'ftransfer://pair?ip=1.2.3.4&code=123456&port=70000',
      '',
    ]) {
      expect(PairingInfo.tryParse(raw), isNull, reason: raw);
    }
  });

  test('validators', () {
    expect(isValidIpv4('10.0.2.2'), isTrue);
    expect(isValidIpv4('10.0.2'), isFalse);
    expect(isValidPort('47520'), isTrue);
    expect(isValidPort('0'), isFalse);
    expect(isValidPort('8a'), isFalse);
    expect(isValidCode('000000'), isTrue);
    expect(isValidCode('00000a'), isFalse);
  });
}
