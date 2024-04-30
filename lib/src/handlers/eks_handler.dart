import 'dart:convert';
import 'dart:io';

import '../api/tiefile.dart';
import '../extensions.dart';
import '../log.dart';
import '../api/types.dart';
import '../util.dart';
import 'kubernetes_handler.dart';

class EKSHandler extends KubernetesHandler {

  EKSHandler(super.config);

  @override
  Future<void> login(Environment environment) async {

    if (environment.name.isNullOrEmpty) {
      throw TieError("environment name has not been set, set to cluster name");
    }
    if (environment.region.isNullOrEmpty) {
      throw TieError("environment region has not been set and is required for eks");
    }
    if (environment.accessKey.isNullOrEmpty) {
      throw TieError("environment accessKey has not been set and is required for eks");
    }
    if (environment.secretAccessKey.isNullOrEmpty) {
      throw TieError("environment secretAccessKey has not been set and is required for eks");
    }

    // build aws config/credentials file
    var ewsConfigFile = File('${config.scratchDir}/awsconfig');;
    await ewsConfigFile.writeAsString('[default]\n', mode: FileMode.write);
    await ewsConfigFile.writeAsString('output = json\n', mode: FileMode.append);
    await ewsConfigFile.writeAsString('region = ${environment.region}\n', mode: FileMode.append);
    await ewsConfigFile.writeAsString('aws_access_key_id = ${environment.accessKey}\n', mode: FileMode.append);
    await ewsConfigFile.writeAsString('aws_secret_access_key = ${environment.secretAccessKey}\n', mode: FileMode.append);
    // aws eks update-kubeconfig --region region-code --name my-cluster
    List<String> args = ['eks', 'update-kubeconfig', '--region', environment.region!, '--name', environment.name!];
    Log.traceCommand(config,'aws',args);
    var process = await Process.start('aws', args,environment: getHandlerEnv(), runInShell: true);
    process.stdout.transform(utf8.decoder).forEach(print);
    process.stderr.transform(utf8.decoder).forEach(print);
    if (await process.exitCode != 0) {
      throw TieError("failed to authenticate with eks");
    }
    // set the api config to generated kubeconfig
    environment.apiConfigFile = kubeConfigFilename;
    // expand the environment again now that a kubeconfig file has been created
    await super.expandEnvironment(environment);
    await super.login(environment);
  }

  @override
  Future<void> logoff() async {
    try {
      if (File('${config.scratchDir}/awsconfig').existsSync()) {
        File('${config.scratchDir}/awsconfig').deleteSync();
      }
    } finally {
      await super.logoff();
    }
  }

  @override
  Map<String, String> getHandlerEnv() {
    var env = <String,String>{};
    env['KUBECONFIG'] = kubeConfigFilename!;
    env['AWS_CONFIG_FILE'] = '${config.scratchDir}/awsconfig';
    env['AWS_SHARED_CREDENTIALS_FILE'] = '${config.scratchDir}/awsconfig';
    return env;
  }
}