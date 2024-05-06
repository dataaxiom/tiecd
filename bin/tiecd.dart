import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:tiecd/api/types.dart';
import "package:tiecd/tiecd.dart" as tiecd;

Future<void> main(List<String> arguments) async {
 try {
  await tiecd.main(arguments);
 } catch (error) {
   if (error is TieError) {
     exit(1);
   }
   if (error is! UsageException) rethrow;
   print(error);
   exit(64); // Exit code 64 indicates a usage error.
 }
 exit(0);
}
