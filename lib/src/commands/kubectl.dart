import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:uuid/uuid.dart';

import '../../api/types.dart';
import '../util.dart';
import '../log.dart';
import '../extensions.dart';

class KubeCtlResult {
  final String _output;
  final String _manifest;

  KubeCtlResult(this._output, this._manifest);

  String get manifest => _manifest;
  String get output => _output;
}

class KubeCtlCommand {
  final Config _config;
  final DeployHandler _handler;

  KubeCtlCommand(this._config, this._handler);

  Future<KubeCtlResult> applyManifestByValue(
      String filename,
      String manifestValue,
      Map<String, String> properties,
      String? namespace) async {
    var manifest = "${_config.scratchDir}/${Uuid().v4()}";
    File(manifest).writeAsStringSync(manifestValue);
    var result = await applyManifestByFileName(
        filename, manifest, properties, namespace);
    File(manifest).deleteSync();
    return result;
  }

  Future<KubeCtlResult> applyManifestByFileName(
      String filename,
      String manifestFileName,
      Map<String, String> properties,
      String? namespace) async {
    // expand any variables in the manifest
    var expanded = expandFileByNameWithProperties(manifestFileName, properties);
    var bytes = utf8.encode(expanded);
    var digest = sha256.convert(bytes);

    var processedFilename = "${_config.scratchDir}/${Uuid().v4()}";
    try {
      File(processedFilename).writeAsStringSync(expanded);
      List<String> args = [];
      if (namespace.isNotNullNorEmpty) {
        args.add("--namespace=$namespace");
      }
      args.add("--wait=true");
      Log.info("applying manifest: $filename");

      Log.traceCommand(_config, 'kubectl apply -f $filename', args);

      var kubeProperties = Map.of(properties);
      kubeProperties.addAll(_handler.getHandlerEnv());
      args = ['apply', '-f', processedFilename, ...args];
      var process = await Process.start('kubectl', args,
          environment: kubeProperties, runInShell: true);
      process.stdout.transform(utf8.decoder).forEach((line) {stdout.write(line);});
      process.stderr.transform(utf8.decoder).forEach((line) {stdout.write(line);});
      if (await process.exitCode != 0) {
        throw TieError("applying manifest: $filename");
      }
      if (File(processedFilename).existsSync()) {
        File(processedFilename).deleteSync();
      }
    } catch (error) {
      if (File(processedFilename).existsSync()) {
        File(processedFilename).deleteSync();
      }
      rethrow;
    }
    var result = KubeCtlResult(digest.toString(), expanded);
    return result;
  }

  // not in use - using native lib call
  Future<int> getCurrentRevision(
      String? namespace, String type, String name) async {
    int revision = 0;
    try {
      List<String> args = [];
      if (namespace.isNotNullNorEmpty) {
        args.add('--namespace=$namespace');
      }
      var kubeProperties = <String, String>{};
      kubeProperties.addAll(_handler.getHandlerEnv());
      args = [
        'get',
        '$type/$name',
        '-o',
        'template',
        '--template={{.status.observedGeneration}}',
        ...args
      ];
      Log.traceCommand(_config, 'kubectl', args);
      var result = await Process.run('kubectl', args,
          environment: kubeProperties, runInShell: true);
      if (result.exitCode == 0) {
        revision = int.parse(result.stdout);
      }
    } catch (error) {
      // swallow exception
    }
    return revision;
  }

  Future<void> waitForRollout(
      String? namespace, String type, String name, String revision) async {
    List<String> args = [];
    if (namespace.isNotNullNorEmpty) {
      args.add('--namespace=$namespace');
    }
    var kubeProperties = <String, String>{};
    kubeProperties.addAll(_handler.getHandlerEnv());
    args = ['rollout', 'status', '$type/$name', '--watch=true', ...args];

    Log.traceCommand(_config, 'kubectl', args);

    var process = await Process.start('kubectl', args,
        environment: kubeProperties, runInShell: true);
    process.stdout.transform(utf8.decoder).forEach((line) {stdout.write(line);});
    process.stderr.transform(utf8.decoder).forEach((line) {stdout.write(line);});
    if (await process.exitCode != 0) {
      throw TieError("Rollout: $type/$name, revision:$revision failed.");
    }
  }
}
