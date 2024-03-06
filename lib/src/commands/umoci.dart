import 'dart:convert';
import 'dart:io';
import 'package:io/io.dart';

import '../api/types.dart';
import '../log.dart';

class UmociCommand {


  final Config _config;

  UmociCommand(this._config);

  Future<void> unpack(String image) async {
    try {
      // ensure there is no bundle directory
      if (Directory('bundle').existsSync()) {
        Directory('bundle').deleteSync(recursive: true);
      }
      List<String> args = ['unpack', '--keep-dirlinks', '--rootless', '--image', image, 'bundle'];
      Log.traceCommand(_config, 'umoci', args);
      var process = await Process.start('umoci', args, runInShell: true);
      process.stdout.transform(utf8.decoder).forEach((line) {stdout.write(line);});
      process.stderr.transform(utf8.decoder).forEach((line) {stdout.write(line);});
      if (await process.exitCode != 0) {
        throw TieError("unpacking image: $image");
      }
    } catch (error) {
      rethrow;
    }
  }

  Future<void> repack(String image ) async {
    try {
      List<String> args = ['repack', '--image', image, 'bundle'];
      Log.traceCommand(_config, 'umoci', args);
      var process = await Process.start('umoci', args, runInShell: true);
      process.stdout.transform(utf8.decoder).forEach((line) {stdout.write(line);});
      process.stderr.transform(utf8.decoder).forEach((line) {stdout.write(line);});
      if (await process.exitCode != 0) {
        throw TieError("repacking image: $image");
      }
    } catch (error) {
      rethrow;
    }
  }

  // copy into bundle
  Future<void> copyDirectory(String source, String destination) async {
    var file = File(source);
    if (file.statSync().type == FileSystemEntityType.directory || file.statSync().type == FileSystemEntityType.link ) {
      copyPathSync(source,'bundle/rootfs/$destination');
    } else if (file.statSync().type == FileSystemEntityType.file) {
      file.copySync('bundle/rootfs/$destination');
    } else {
      Log.error('source file: $source is an unknown type');
    }

  }

  Future<void> config(String image, List<String> args) async {
    try {
      List<String> configArgs = ['config', '--image', image, ...args];
      Log.traceCommand(_config, 'umoci', configArgs);
      var process = await Process.start('umoci', configArgs, runInShell: true);
      process.stdout.transform(utf8.decoder).forEach((line) {stdout.write(line);});
      process.stderr.transform(utf8.decoder).forEach((line) {stdout.write(line);});
      if (await process.exitCode != 0) {
        throw TieError("setting config on image: $image");
      }
    } catch (error) {
      rethrow;
    }
  }


  Future<void> cleanup(String image) async {

    try {

      if (Directory('bundle').existsSync()) {
        // fix permissions to be sure
        var process = await Process.start('umoci-perm.sh', ['bundle'], runInShell: true);
        if (await process.exitCode != 0) {
          process.stdout.transform(utf8.decoder).forEach((line) {stdout.write(line);});
          process.stderr.transform(utf8.decoder).forEach((line) {stdout.write(line);});
        }
        Directory('bundle').deleteSync(recursive: true);
      }

      List<String> configArgs = ['rm', '--image', image];
      Log.traceCommand(_config, 'umoci', configArgs);
      var process = await Process.start('umoci', configArgs, runInShell: true);
      process.stdout.transform(utf8.decoder).forEach((line) {stdout.write(line);});
      process.stderr.transform(utf8.decoder).forEach((line) {stdout.write(line);});
      if (await process.exitCode != 0) {
        throw TieError("removing image: oci:$image");
      }
    } catch (error) {
      // ignore
    }
    try {
      List<String> imageName = image.split(":");
      if (imageName.length == 2) {
        List<String> configArgs = ['gc', '--layout', imageName[0]];
        Log.traceCommand(_config, 'umoci', configArgs);
        var process = await Process.start(
            'umoci', configArgs, runInShell: true);
        process.stdout.transform(utf8.decoder).forEach((line) {stdout.write(line);});
        process.stderr.transform(utf8.decoder).forEach((line) {stdout.write(line);});
        if (await process.exitCode != 0) {
          throw TieError("cleaning image blobs: $image");
        }
      }
    } catch (error) {
      // ignore
    }
  }
}