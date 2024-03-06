

import 'package:json2yaml/json2yaml.dart';
import 'package:tiecd/src/extensions.dart';
import 'package:tiecd/src/util.dart';

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

  static void printObject(Config config, String name, String? message, Map contents) {
    if (message.isNotNullNorEmpty) {
      Log.info(message!);
    }
    print('---');
    Map<String, dynamic> wrapper = {};
    wrapper[name] = contents;
    sanitizeDoc(config, wrapper);
    print(json2yaml(wrapper));
    print('---');
  }

  static void printArray(Config config, String name, String? message, Map contents) {
    if (message.isNotNullNorEmpty) {
      Log.info(message!);
    }
    print('---');
    List<Map> array = [contents];
    Map<String, dynamic> wrapper = {};
    wrapper[name] = array;
    sanitizeDoc(config, wrapper);
    print(json2yaml(wrapper));
    print('---');
  }
}
