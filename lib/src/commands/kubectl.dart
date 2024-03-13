import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:uuid/uuid.dart';

import '../api/types.dart';
import '../util.dart';
import '../log.dart';

class KubeCtlResult {
  final String _output;
  final String _template;

  KubeCtlResult(this._output, this._template);

  String get template => _template;
  String get output => _output;
}

class KubeCtlCommand {
  final Config _config;
  final String _kubeConfigFile;

  KubeCtlCommand(this._config, this._kubeConfigFile);

  Future<KubeCtlResult> applyTemplateByValue(
      String filename,
      String templateValue,
      Map<String, String> properties,
      String? namespace) async {
    var templateFile = "${_config.scratchDir}/${Uuid().v4()}";
    File(templateFile).writeAsStringSync(templateValue);
    var result = await applyTemplateByFileName(
        filename, templateFile, properties, namespace);
    File(templateFile).deleteSync();
    return result;
  }

  Future<KubeCtlResult> applyTemplateByFileName(
      String filename,
      String templateFileName,
      Map<String, String> properties,
      String? namespace) async {
    // expand any variables in the template
    var expanded = expandFileByNameWithProperties(templateFileName, properties);
    var bytes = utf8.encode(expanded);
    var digest = md5.convert(bytes);

    var processedFilename = "${_config.scratchDir}/${Uuid().v4()}";
    try {
      File(processedFilename).writeAsStringSync(expanded);
      List<String> args = [];
      if (namespace != null && namespace != "") {
        args.add("--namespace=$namespace");
      }
      args.add("--wait=true");
      Log.info("applying template: $filename");

      Log.traceCommand(_config, 'kubectl apply -f $filename', args);

      var kubeProperties = Map.of(properties);
      kubeProperties["KUBECONFIG"] = _kubeConfigFile;
      args = ['apply', '-f', processedFilename, ...args];
      var process = await Process.start('kubectl', args,
          environment: kubeProperties, runInShell: true);
      process.stdout.transform(utf8.decoder).forEach(print);
      process.stderr.transform(utf8.decoder).forEach(print);
      if (await process.exitCode != 0) {
        throw TieError("applying template: $filename");
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
      if (namespace != null && namespace != "") {
        args.add('--namespace=$namespace');
      }
      var kubeProperties = <String, String>{};
      kubeProperties['KUBECONFIG'] = _kubeConfigFile;
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
    if (namespace != null && namespace != "") {
      args.add('--namespace=$namespace');
    }
    var kubeProperties = <String, String>{};
    kubeProperties['KUBECONFIG'] = _kubeConfigFile;
    args = ['rollout', 'status', '$type/$name', '--watch=true', ...args];

    Log.traceCommand(_config, 'kubectl', args);

    var process = await Process.start('kubectl', args,
        environment: kubeProperties, runInShell: true);
    process.stdout.transform(utf8.decoder).forEach(print);
    process.stderr.transform(utf8.decoder).forEach(print);
    if (await process.exitCode != 0) {
      throw TieError("Rollout: $type/$name, revision:$revision failed.");
    }
  }
}
