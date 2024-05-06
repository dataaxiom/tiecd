
import 'dart:convert';
import 'dart:io';

import '../../api/tiefile.dart';
import '../../api/types.dart';
import '../util/command_splitter.dart';
import '../log.dart';
import '../extensions.dart';

class YttCommand {

  final Config _config;

  YttCommand(this._config);

  Future<String> transform(String manifest, Ytt ytt) async {
    var generated = '';
    try {
      List<String> args = [
        "-f",
        "-",
      ];
      if (ytt.args.isNotNullNorEmpty) {
         var splitter = CommandlineSplitter();
         splitter.convert(ytt.args!).forEach((element) {args.add(element);});
      }
      if (ytt.files!.isNotEmpty) {
        for (var overlay in ytt.files!) {
          args.add('-f');
          args.add(overlay);
        }
      } else {
        throw TieError('not ytt files are provided');
      }
      Log.traceCommand(_config, 'ytt', args);
      var process = await Process.start('ytt', args, runInShell: true);
      process.stdin.write(manifest);
      await process.stdin.close();
      if (await process.exitCode != 0) {
        await process.stdout.transform(utf8.decoder).forEach((line) {
          stdout.write(line);
        });
        await process.stderr.transform(utf8.decoder).forEach((line) {
          stdout.write(line);
        });
        throw TieError('ytt overlay failed');
      } else {
        generated = await process.stdout.transform(utf8.decoder).join();
        await process.stderr.transform(utf8.decoder).forEach((line) {
          stdout.write(line);
        });
      }
    } catch (error) {
      rethrow;
    }
    return generated;
  }
}