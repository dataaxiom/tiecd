
import 'dart:convert';
import 'dart:io';

import 'package:uuid/uuid.dart';

import '../api/dsl.dart';
import '../api/provider.dart';
import '../api/types.dart';
import '../log.dart';
import '../util.dart';

class HelmCommand {

  final Config _config;
  final String _kubeConfigFile;
  String? _tempDir;

  HelmCommand(this._config, this._kubeConfigFile) {
    _tempDir =  Uuid().v4().toString();
    Directory("${_config.scratchDir}/$_tempDir").createSync(recursive: true);
  }

  Future<void> addRepo(TieContext tieContext, HelmChart chart) async {
    var args = ['repo','add', 'repo', (chart.url!)];

    if (_config.traceCommands) {
      Log.info('helm repo add repo ${chart.url!}');
    }

    var kubeProperties = Map.of(tieContext.getEnv());
    kubeProperties["KUBECONFIG"] = _kubeConfigFile;
    kubeProperties['HELM_CACHE_HOME'] = "${_config.scratchDir}/${_tempDir!}/cache";
    kubeProperties['HELM_CONFIG_HOME'] = "${_config.scratchDir}/${_tempDir!}/config";
    kubeProperties['HELM_DATA_HOME'] = "${_config.scratchDir}/${_tempDir!}/data";

    var process = await Process.start('helm', args, environment: kubeProperties, runInShell: true);
    process.stdout
        .transform(utf8.decoder)
        .forEach(print);
    process.stderr
        .transform(utf8.decoder)
        .forEach(print);
    if (await process.exitCode != 0) {
      throw TieError('setting helm repo " + chart.url!');
    }
  }

  Future<void> update(TieContext tieContext) async {
    var args = ['repo','update'];

    if (_config.traceCommands) {
      Log.info('helm repo update');
    }

    var kubeProperties = Map.of(tieContext.getEnv());
    kubeProperties["KUBECONFIG"] = _kubeConfigFile;
    kubeProperties['HELM_CACHE_HOME'] = "${_config.scratchDir}/${_tempDir!}/cache";
    kubeProperties['HELM_CONFIG_HOME'] = "${_config.scratchDir}/${_tempDir!}/config";
    kubeProperties['HELM_DATA_HOME'] = "${_config.scratchDir}/${_tempDir!}/data";

    var process = await Process.start('helm', args, environment: kubeProperties, runInShell: true);
    process.stdout
        .transform(utf8.decoder)
        .forEach(print);
    process.stderr
        .transform(utf8.decoder)
        .forEach(print);
    if (await process.exitCode != 0) {
      throw TieError('helm repo update');
    }
  }

  Future<void> install(TieContext tieContext, HelmChart helmChart) async {
    List<String> args = [];
    Map<String,String> fileMapping = {};
    args.add('upgrade');

    var name = helmChart.name;
    if (name == null) {
      if (tieContext.app.label != null) {
        name = tieContext.app.label;
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

    var namespace = helmChart.namespace;
    namespace ??= tieContext.app.namespace;
    namespace ??= tieContext.environment.namespace;

    if (namespace != null) {
      args.add("--namespace=$namespace");
    }

    if (helmChart.sets != null) {
      for (var setValue in helmChart.sets!) {
        args.add('--set');
        args.add(varExpandByLineWithProperties(setValue, "", null));
      }
    }

    if (helmChart.values != null) {
      for (var valueFile in helmChart.values!) {
        // expand the file into a temporary file
        var expanded = expandFileByName("${_config.baseDir}/$valueFile");
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

    if (helmChart.args != null) {
      for (var arg in helmChart.args!) {
        args.add(arg);
      }
    }

    if (_config.traceCommands) {
      var outputString = 'helm ';
      for (var arg in args) {
        if (isPassword(arg)) {
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

    var kubeProperties = Map.of(tieContext.getEnv());
    kubeProperties["KUBECONFIG"] = _kubeConfigFile;
    kubeProperties['HELM_CACHE_HOME'] = "${_config.scratchDir}/${_tempDir!}/cache";
    kubeProperties['HELM_CONFIG_HOME'] = "${_config.scratchDir}/${_tempDir!}/config";
    kubeProperties['HELM_DATA_HOME'] = "${_config.scratchDir}/${_tempDir!}/data";

    var process = await Process.start('helm', args, environment: kubeProperties, runInShell: true);
    process.stdout
        .transform(utf8.decoder)
        .forEach(print);
    process.stderr
        .transform(utf8.decoder)
        .forEach(print);
    if (await process.exitCode != 0) {
      throw TieError('helm install');
    }

  }

  Future<void> remove(TieContext tieContext, HelmChart helmChart) async {
    var name = helmChart.name;
    if (name == null && tieContext.app.name != null) {
      name = tieContext.app.name!;
    }

    var args = ['uninstall', '--wait', name!];

    var namespace = helmChart.namespace;
    namespace ??= tieContext.app.namespace;
    namespace ??= tieContext.environment.namespace;

    if (namespace != null) {
      args.add('--namespace=$namespace');
    }

    if (_config.traceCommands) {
      Log.info('helm ${_generateCommand(args)}');
    }

    var kubeProperties = Map.of(tieContext.getEnv());
    kubeProperties["KUBECONFIG"] = _kubeConfigFile;
    kubeProperties['HELM_CACHE_HOME'] = "${_config.scratchDir}/${_tempDir!}/cache";
    kubeProperties['HELM_CONFIG_HOME'] = "${_config.scratchDir}/${_tempDir!}/config";
    kubeProperties['HELM_DATA_HOME'] = "${_config.scratchDir}/${_tempDir!}/data";

    var process = await Process.start('helm', args, environment: kubeProperties, runInShell: true);
    process.stdout
        .transform(utf8.decoder)
        .forEach(print);
    process.stderr
        .transform(utf8.decoder)
        .forEach(print);
    if (await process.exitCode != 0) {
      throw TieError('helm uninstall: $name');
    }
  }

  void clean(TieContext tieContext, HelmChart chart) {
    try {
      if (File("${_config.scratchDir}/$_tempDir").existsSync()) {
          File("${_config.scratchDir}/$_tempDir").deleteSync(recursive: true);
      }
    } catch (error) {
      Log.error('cleaning up helm scratch dir');
    }
  }
}

String _generateCommand(List<String> args) {
  StringBuffer output = StringBuffer();
  for (var arg in args) {
    output.write(arg);
    output.write(" ");
  }
  return output.toString();
}

