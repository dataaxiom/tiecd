
import "package:tiecd/tiecd.dart" as tiecd;
import 'package:test/test.dart';

void main() {
  group('Move Image ', ()
  {
    test('push image', () async {
      var result = await tiecd.main(['deploy','-b','test/resources/move_image_test']);
      expect(result, 0);
    });
  });
}