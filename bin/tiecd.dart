import 'dart:io';

import "package:tiecd/tiecd.dart" as tiecd;

Future<void> main(List<String> arguments) async {
 exit(await tiecd.main(arguments));
}
