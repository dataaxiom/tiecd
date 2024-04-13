
import 'dart:convert';
import 'dart:io';

import 'package:tiecd/src/extensions.dart';
import 'package:uuid/uuid.dart';

import '../api/tiefile.dart';
import '../api/types.dart';
import '../log.dart';
import '../util.dart';
import '../util/command_splitter.dart';

class HelmCommand {

  final Config _config;
  final String _kubeConfigFile;
  String? _tempDir;

  HelmCommand(this._config, this._kubeConfigFile) {
    _tempDir =  Uuid().v4().toString();
    Directory("${_config.scratchDir}/$_tempDir").createSync(recursive: true);
  }

  Future<void> addRepo(DeployContext deployContext, HelmChart chart) async {
    var args = ['repo','add', 'repo', (chart.url!)];
    Log.traceCommand(_config, 'helm', args);
    var kubeProperties = Map.of(deployContext.getEnv());
    kubeProperties.addAll(deployContext.handler.getHandlerEnv());
    kubeProperties['HELM_CACHE_HOME'] = "${_config.scratchDir}/${_tempDir!}/cache";
    kubeProperties['HELM_CONFIG_HOME'] = "${_config.scratchDir}/${_tempDir!}/config";
    kubeProperties['HELM_DATA_HOME'] = "${_config.scratchDir}/${_tempDir!}/data";
    var process = await Process.start('helm', args, environment: kubeProperties, runInShell: true);
    process.stdout
        .transform(utf8.decoder)
        .forEach((line) {stdout.write(line);});
    process.stderr
        .transform(utf8.decoder)
        .forEach((line) {stdout.write(line);});
    if (await process.exitCode != 0) {
      throw TieError('setting helm repo " + chart.url!');
    }
  }

  Future<void> update(DeployContext deployContext) async {
    var args = ['repo','update'];
    Log.traceCommand(_config, 'helm', args);
    var kubeProperties = Map.of(deployContext.getEnv());
    kubeProperties.addAll(deployContext.handler.getHandlerEnv());
    kubeProperties['HELM_CACHE_HOME'] = "${_config.scratchDir}/${_tempDir!}/cache";
    kubeProperties['HELM_CONFIG_HOME'] = "${_config.scratchDir}/${_tempDir!}/config";
    kubeProperties['HELM_DATA_HOME'] = "${_config.scratchDir}/${_tempDir!}/data";
    var process = await Process.start('helm', args, environment: kubeProperties, runInShell: true);
    process.stdout
        .transform(utf8.decoder)
        .forEach((line) {stdout.write(line);});
    process.stderr
        .transform(utf8.decoder)
        .forEach((line) {stdout.write(line);});
    if (await process.exitCode != 0) {
      throw TieError('helm repo update');
    }
  }

  Future<void> install(DeployContext deployContext, HelmChart helmChart) async {
    List<String> args = [];
    Map<String,String> fileMapping = {};
    args.add('upgrade');
    var name = helmChart.name;
    if (name == null) {
      if (deployContext.app.label != null) {
        name = deployContext.app.label;
      }
    }
    args.add(name!);
    if (helmChart.url!.startsWith('oci://')) {
      args.add(helmChart.url!);
    } else {
      args.add('repo/${helmChart.chart}');
    }
    args.add('--install');
    args.add('--wait');
    args.add('--history-max=1');
    var namespace = findNamespace(deployContext);
    if (namespace != null) {
      args.add("--namespace=$namespace");
    }
    Map<String,String> env = deployContext.getEnv();
    if (helmChart.values != null) {
      for (var valueFile in helmChart.values!) {
        // expand the file into a temporary file
        var expanded = expandFileByName("${_config.baseDir}/$valueFile", env);
        var fileName = valueFile.replaceAll("/","-");
        fileName = "${_config.scratchDir}/${_tempDir!}/$fileName";
        File(fileName).writeAsStringSync(expanded);
        args.add('-f');
        args.add(fileName);
        fileMapping[fileName] = valueFile;
      }
    }
    if (helmChart.version != null && helmChart.version != '') {
      args.add('--version');
      args.add(helmChart.version!);
    }
    if (helmChart.flags != null) {
      for (var flag in helmChart.flags!) {
        args.add(flag);
      }
    }
    if (helmChart.args.isNotNullNorEmpty) {
        var helmArgValue = varExpandByLineWithProperties(helmChart.args!, "", env);
        var splitter = CommandlineSplitter();
        var commandArgs = splitter.convert(helmArgValue);
        for (var commandArg in commandArgs) {
          args.add(commandArg);
        }
    }
    if (_config.traceCommands) {
      var outputString = 'helm ';
      for (var arg in args) {
        if (isPassword(_config,arg)) {
          if (arg.contains('=')) {
             var parts = arg.split('=');
            outputString += '${parts[0]}=**** ';
          } else {
            outputString += '**** ';
          }
        } else if (arg.startsWith('-f ')) {
          var tempFile = arg.substring(3);
          outputString += '-f ${fileMapping[tempFile]!} ';
        } else {
          outputString += '$arg ';
        }
      }
      Log.info(outputString);
    }
    var kubeProperties = Map.of(deployContext.getEnv());
    kubeProperties.addAll(deployContext.handler.getHandlerEnv());
    kubeProperties['HELM_CACHE_HOME'] = "${_config.scratchDir}/${_tempDir!}/cache";
    kubeProperties['HELM_CONFIG_HOME'] = "${_config.scratchDir}/${_tempDir!}/config";
    kubeProperties['HELM_DATA_HOME'] = "${_config.scratchDir}/${_tempDir!}/data";

    var process = await Process.start('helm', args, environment: kubeProperties, runInShell: true);
    process.stdout
        .transform(utf8.decoder)
        .forEach((line) {stdout.write(line);});
    process.stderr
        .transform(utf8.decoder)
        .forEach((line) {stdout.write(line);});
    if (await process.exitCode != 0) {
      throw TieError('helm install');
    }
  }

  Future<void> remove(DeployContext deployContext, HelmChart helmChart) async {
    var name = helmChart.name;
    if (name == null && deployContext.app.name != null) {
      name = deployContext.app.name!;
    }
    var args = ['uninstall', '--wait', name!];
    var namespace = findNamespace(deployContext);
    if (namespace != null) {
      args.add('--namespace=$namespace');
    }
    Log.traceCommand(_config, 'helm', args);
    var kubeProperties = Map.of(deployContext.getEnv());
    kubeProperties.addAll(deployContext.handler.getHandlerEnv());
    kubeProperties['HELM_CACHE_HOME'] = "${_config.scratchDir}/${_tempDir!}/cache";
    kubeProperties['HELM_CONFIG_HOME'] = "${_config.scratchDir}/${_tempDir!}/config";
    kubeProperties['HELM_DATA_HOME'] = "${_config.scratchDir}/${_tempDir!}/data";

    var process = await Process.start('helm', args, environment: kubeProperties, runInShell: true);
    process.stdout
        .transform(utf8.decoder)
        .forEach((line) {stdout.write(line);});
    process.stderr
        .transform(utf8.decoder)
        .forEach((line) {stdout.write(line);});
    if (await process.exitCode != 0) {
      throw TieError('helm uninstall: $name');
    }
  }

  Future<void> clean(DeployContext deployContext, HelmChart chart) async {
    try {
      if (Directory("${_config.scratchDir}/$_tempDir").existsSync()) {
        Directory("${_config.scratchDir}/$_tempDir").deleteSync(recursive: true);
      }
    } catch (error) {
      Log.error('cleaning up helm scratch dir');
    }
  }
}
