import 'package:flutter_test/flutter_test.dart';

import 'package:client/src/app/confirmation.dart';

void main() {
  test(
    'matchesConfirmationText trims input but keeps exact target matching',
    () {
      expect(matchesConfirmationText(' room-name ', 'room-name'), isTrue);
      expect(matchesConfirmationText('Room-Name', 'room-name'), isFalse);
      expect(matchesConfirmationText('room-name-extra', 'room-name'), isFalse);
    },
  );
}
