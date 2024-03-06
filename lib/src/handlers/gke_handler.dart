import 'dart:convert';
import 'dart:io';

import 'package:tiecd/src/api/types.dart';
import 'package:uuid/uuid.dart';

import '../extensions.dart';
import '../log.dart';
import 'kubernetes_handler.dart';


class GKEHandler extends KubernetesHandler {

  bool _keyFileOutputted = false;
  String? _keyFile;

  GKEHandler(super.config);

  @override
  Future<void> login(DeployContext deployContext) async {

    // if a kube_config hasn't been provided use gcloud service account login approach
    if (deployContext.environment.apiConfig == null) {
      // preform a gcloud login
      if (deployContext.environment.serviceAccountName.isNullOrEmpty) {
        throw TieError("environment serviceAccountName has not been set");
      }
      if (deployContext.environment.projectId.isNullOrEmpty) {
        throw TieError("environment projectId has not been set");
      }
      if (deployContext.environment.zone.isNullOrEmpty) {
        throw TieError("environment zone has not been set");
      }
      if (deployContext.environment.name.isNullOrEmpty) {
        throw TieError("environment name has not been set, set to cluster name");
      }

      if (deployContext.environment.apiClientKeyFile.isNotNullNorEmpty) {
        if (File(deployContext.environment.apiClientKeyFile!).existsSync()) {
          _keyFile = deployContext.environment.apiClientKeyFile!;
        } else {
          throw TieError("environment apiClientKeyFile: $deployContext.environment.apiClientKeyFile doest not exist");
        }
      } else {
        if (deployContext.environment.apiClientKey.isNotNullNorEmpty) {
          _keyFile = "${config.scratchDir}/${Uuid().v4()}";
          File(_keyFile!).writeAsStringSync(deployContext.environment.apiClientKey!);
          _keyFileOutputted = true;
        } else {
          throw TieError("environment apiClientKey/apiClientKeyFile has not been set");
        }
      }

      // gcloud auth activate-service-account ci-cd-pipeline@PROJECT_ID.iam.gserviceaccount.com --key-file=gsa-key.json
      List<String> args = ['auth', 'activate-service-account', '${deployContext.environment.serviceAccountName}@${deployContext.environment.projectId}.iam.gserviceaccount.com', '--key-file=$_keyFile'];
      Log.traceCommand(config,'gcloud',args);
      var process = await Process.start('gcloud', args, runInShell: true);
      process.stdout.transform(utf8.decoder).forEach(print);
      process.stderr.transform(utf8.decoder).forEach(print);
      if (await process.exitCode != 0) {
        throw TieError("failed to authenticate with gke");
      }

      // gcloud config set project PROJECT_ID
      args = ['config', 'set', 'project', deployContext.environment.projectId!];
      Log.traceCommand(config,'gcloud',args);
      process = await Process.start('gcloud', args, runInShell: true);
      process.stdout.transform(utf8.decoder).forEach(print);
      process.stderr.transform(utf8.decoder).forEach(print);
      if (await process.exitCode != 0) {
        throw TieError("failed to setup project on gke");
      }

      // setup kube_config file
      // gcloud container clusters get-credentials CLUSTER_NAME --zone=COMPUTE_ZONE
      args = ['container', 'clusters', 'get-credentials', deployContext.environment.name!, '--zone=${deployContext.environment.zone}'];
      Log.traceCommand(config,'gcloud',args);
      process = await Process.start('gcloud', args, environment: getHandlerEnv(), runInShell: true);
      process.stdout.transform(utf8.decoder).forEach(print);
      process.stderr.transform(utf8.decoder).forEach(print);
      if (await process.exitCode != 0) {
        throw TieError("failed to get gke credentials");
      }

      // set the api config to generated kubeconfig
      deployContext.environment.apiConfigFile = kubeConfigFilename;

      // expand the environment again now that a kubeconfig file has been created
      await super.expandEnvironment(deployContext.environment);

      // now preform super login
      await super.login(deployContext);
    }
  }

  @override
  Future<void> logoff(DeployContext deployContext) async {
    List<String> args = ['auth', 'revoke', '--all'];
    Log.traceCommand(config,'gcloud',args);
    await Process.run('gcloud', args, runInShell: true);
    if (_keyFileOutputted && _keyFile.isNotNullNorEmpty) {
      File(_keyFile!).deleteSync();
      _keyFileOutputted = false;
      _keyFile = null;
    }
    super.logoff(deployContext);
  }


}