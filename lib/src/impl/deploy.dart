import 'dart:io';

import 'package:intl/intl.dart';
import 'package:tiecd/src/impl/base.dart';
import 'package:tiecd/src/providers/gke_provider.dart';
import 'package:yaml/yaml.dart';

import '../api/dsl.dart';
import '../api/provider.dart';
import '../api/types.dart';
import '../log.dart';
import '../providers/kubernetes_provider.dart';

class Deploy extends BaseExecutor {
  Deploy(super._config);

  void preExpandEnvironment(Environment environment) {
    // if we haven't and apiType and we have apiConfig set check if it's kubernetes
    if (environment.apiType == null && environment.apiConfig != null) {
      var kubeConfig = loadYaml(environment.apiConfig!);
      if (kubeConfig is Map && kubeConfig["kind"] == "Config") {
        environment.apiType = "kubernetes";
      }
    }

    // if we still don't have a name
    if (environment.name == null && environment.label != null) {
      environment.name = environment.label!;
    } else if (environment.name == null && environment.apiUrl != null) {
      environment.name = environment.apiUrl;
    }
  }

  List<Environment> processEnvironments(List<Environment> environments) {
    // expand environments if necessary
    for (var environment in environments) {
      if (environment.name != null && environment.name != "") {
        // todo support named environments
        //expandEnvironment(environment.name, environment);
      }
    }

    final Map<String, String> envVars = Platform.environment;

    String? environmentName = envVars['TIECD_ENVIRONMENT_LABEL'];
    if (environmentName != null && environmentName != ('')) {
      // we have have a specific subset of environments to target/use
      Log.green('Using environment $environmentName');
      List<Environment> subEnvironments = [];
      // find the environments - there could be multiple physical locations for the
      // same name
      for (var environment in environments) {
        if (environmentName == environment.label) {
          subEnvironments.add(environment);
        }
      }
      environments = subEnvironments;
    }
    return environments;
  }


  @override
  execute(Tie tieFile, App app) async {

    if (tieFile.environments != null && tieFile.environments!.isNotEmpty) {

      List<Environment> environments = processEnvironments(tieFile.environments!);

      for (var environment in environments) {

        // lets take a copy to support to expand on that
        environment = environment.clone();

        preExpandEnvironment(environment);
        TieProvider provider;
        if (environment.apiType == null) {
          throw TieError('provider type is not set');
        } else if (environment.apiType == "kubernetes") {
          if (environment.apiProvider == "gke") {
            provider = GKEProvider(config);
          } else {
            provider = KubernetesProvider(config);
          }
        } else {
          throw TieError('provider ${environment.apiType} type is not supported');
        }

        provider.expandEnvironment(environment);
        Log.green('processing app "${app.name!}" on ${environment.name!} environment');
        List<ImageRepository> imageRepositories = [];
        if (tieFile.repositories != null && tieFile.repositories!.image != null) {
          imageRepositories = tieFile.repositories!.image!;
        }
        var context = TieContext(config, imageRepositories, environment, app);
        var namespace = app.namespace;
        namespace ??= environment.namespace;
        app.deployEnv ??= {};

        if (namespace != null) {
          app.deployEnv!["TIECD_NAMESPACE"] = namespace;
        }
        if (environment.label != null) {
          app.deployEnv!["TIECD_ENVIRONMENT_LABEL"] = environment.label!;
        }

        // only set if not already in environment
        if (Platform.environment['TIECD_DATE'] == null) {
          final DateFormat formatter = DateFormat('yyyy-MM-dd-HH-mm-ss');
          final String formatted = formatter.format(date);
          app.deployEnv!["TIECD_DATE"] = formatted;
        }

        try {
          await provider.login(context);

          var action = app.action;
          action ??= Action.install;

          if (action == Action.install) {
            await provider.processImage(context);
            if (app.preCommands != null) {
              await provider.runLocalCommands(context, app.preCommands!);
            }
            await provider.processConfig(context);
            await provider.processSecrets(context);
            if (app.preDeployCommands != null) {
              await provider.runLocalCommands(context, app.preDeployCommands!);
            }
            var checksum = await provider.processDeploy(context);
            if (checksum != '') {
              context.app.deployEnv!["TIECD_TEMPLATE_HASH"] = checksum;
            }
            await provider.processHelm(context);
            if (app.postCommands != null) {
              await provider.runLocalCommands(context, app.postCommands!);
            }

          } else if (action == Action.uninstall) {
            await provider.removeHelm(context);
          } else {
            throw TieError('unknown action type: $action on app "${app.name}"');
          }

        } catch (error) {
          rethrow;
        } finally {
          await provider.logoff(context);
        }
      }
    } else {
      throw TieError('no environments defined');
    }
  }
}