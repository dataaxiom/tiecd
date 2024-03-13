

import 'api/types.dart';

const redChar = "\u001b[31m";
const greenChar = "\u001b[32m";
const resetChar = "\u001b[0m";

class Log {
  static void info(String message) {
    print("[TIECD] $message");
  }

  static void green(String message) {
    print("$greenChar[TIECD] $message$resetChar");
  }

  static void error(String message) {
    print("$redChar[TIECD] ERROR $message$resetChar");
  }

  static void traceCommand(Config config, String command, List<String> args) {
    if (config.traceCommands) {
      var message = '$command ';
      for (var arg in args) {
        message += '$arg ';
      }
      print("[TIECD] $message");
    }
  }
}
