import 'dart:io';

import 'package:intl/intl.dart';
import 'package:yaml/yaml.dart';

import '../../api/tiefile.dart';
import '../../api/types.dart';
import '../log.dart';
import '../handlers/kubernetes_handler.dart';
import '../handlers/gke_handler.dart';
import '../handlers/eks_handler.dart';
import '../util.dart';
import '../extensions.dart';
import 'base.dart';

class DeployExecutor extends BaseExecutor {
  DeployExecutor(super._config);

  final Map<String, Environment>  _environments = {};
  final Map<String, DeployHandler> _deployHandlers = {};

  @override
  String getVerb() {
    return 'deploying';
  }
  void preExpandEnvironment(Environment environment) {

    // if apiConfigFile is set load it
    if (environment.apiConfigFile != null) {
      if (!File(environment.apiConfigFile!).existsSync()) {
        throw TieError(
            "api config file: ${environment.apiConfigFile} does not exist");
      } else {
        environment.apiConfig ??=
            File(environment.apiConfigFile!).readAsStringSync();
      }
    }

    // if we haven't and apiType and we have apiConfig set check if it's kubernetes
    if (environment.apiType == null && environment.apiConfig != null) {
      var kubeConfig = loadYaml(environment.apiConfig!);
      if (kubeConfig is Map && kubeConfig["kind"] == "Config") {
        environment.apiType = "kubernetes";
      }
    }

    // if we still don't have a name
    if (environment.name == null && environment.apiUrl != null) {
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
    if (environmentName.isNotNullNorEmpty) {
      // we have have a specific subset of environments to target/use
      // filter the rest out
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

  DeployHandler buildHandler(Environment environment) {
    DeployHandler handler;
    if (environment.apiType == null) {
      Log.printObject(config,'environment', 'Environment in use:', environment.toJson());
      throw TieError('provider type is not set');
    } else if (environment.apiType == "kubernetes") {
      if (environment.apiProvider == "gke") {
        handler = GKEHandler(config);
      } else if (environment.apiProvider == "eks") {
        handler = EKSHandler(config);
      } else {
        handler = KubernetesHandler(config);
      }
    } else {
      Log.printObject(config, 'environment', 'Environment in use:', environment.toJson());
      throw TieError(
          'provider ${environment.apiType} type is not supported');
    }
    handler.expandEnvironment(environment);
    return handler;
  }

  @override
  initialize(Tie tieFile) async {
    List<Environment> environments =
    processEnvironments(tieFile.environments!);
    // build and initialize the environments for this tie file
    for (var environment in environments) {
      // save before handler login potentially changes the signature
      var signature = environment.signature();
      var clone = environment.clone();
      // create one in the factory if we don't have one already?
      if (_environments[signature] == null) {
        preExpandEnvironment(clone);
        DeployHandler handler = buildHandler(clone);
        await handler.login(clone);
        _environments[signature] = clone;
        _deployHandlers[signature] = handler;
        if (config.traceTieFile) {
          Log.info('Environment in use:');
          Log.printObject(config, 'environment', '',
              clone.toJson());
        }
      }
    }
  }

  @override
  execute(Tie tieFile, App app) async {
    if (tieFile.environments != null && tieFile.environments!.isNotEmpty) {
      app.deploy ??= Deploy();

      List<Environment> environments =
          processEnvironments(tieFile.environments!);

      // build and initialize the environments for this tie file
      for (var environment in environments) {
        // save before handler login potentially changes the signature
        var signature = environment.signature();

        if (_deployHandlers[signature] == null) {
          throw TieError('no handler setup for environment');
        }
        DeployHandler handler = _deployHandlers[signature]!;
        Environment expandedEnvironment = _environments[signature]!;

        Log.green(
            'processing app "${app.name!}" on ${expandedEnvironment.name!} environment');
        List<ImageRegistry> imageReregistries = [];
        if (tieFile.registries != null) {
          imageReregistries = tieFile.registries!;
        }
        var context = DeployContext(config, imageReregistries, handler, expandedEnvironment, app);
        var namespace = findNamespace(context);
        app.tiecdEnv ??= {};

        if (namespace.isNotNullNorEmpty) {
          app.tiecdEnv!["TIECD_NAMESPACE"] = namespace!;
          // setup deployed artifacts for this namespace
          var deployedArtifacts = context.environment.deployedArtifacts[namespace];
          if (deployedArtifacts == null) {
            deployedArtifacts = {};
            context.environment.deployedArtifacts[namespace] = deployedArtifacts;
          }
        }
        if (environment.label.isNotNullNorEmpty) {
          app.tiecdEnv!["TIECD_ENVIRONMENT_LABEL"] = environment.label!;
        }

        // only set if not already in environment
        if (Platform.environment['TIECD_DATE'] == null) {
          final DateFormat formatter = DateFormat('yyyy-MM-dd-HH-mm-ss');
          final String formatted = formatter.format(date);
          app.tiecdEnv!["TIECD_DATE"] = formatted;
        }

        if (config.traceTieFile) {
          Log.printArray(config,'apps', null, app.toJson());
        }

        try {

          var action = app.deploy!.action;
          action ??= Action.install;

          if (action == Action.install) {
            await handler.handleImage(context);
            if (app.deploy!.beforeScripts != null) {
              await handler.runScripts(
                  context, app.deploy!.beforeScripts!);
            }
            await handler.handleConfig(context);
            await handler.handleSecrets(context);
            if (app.deploy!.scripts != null) {
              await handler.runScripts(
                  context, app.deploy!.scripts!);
            }
            var checksum = await handler.deploy(context);
            if (checksum != '') {
              context.app.tiecdEnv!["TIECD_MANIFEST_HASH"] = checksum;
              if (config.verbose) {
                Log.info(
                    'adding TIECD_MANIFEST_HASH to environment: $checksum');
              }
            }
            await handler.handleHelm(context);
            if (app.deploy!.afterScripts != null) {
              await handler.runScripts(
                  context, app.deploy!.afterScripts!);
            }
          } else if (action == Action.uninstall) {
            await handler.removeHelm(context);
          } else {
            throw TieError('unknown action type: $action on app "${app.name}"');
          }
          if (config.verbose) {
            Log.printObject(config,'app', 'final computed app definition', app.toJson());
          }

          // cleanup
          await handler.cleanupResources(context);

        } catch (error) {
          rethrow;
        }
      }


    } else {
      throw TieError('no environments defined');
    }
  }

  @override
  cleanup() async {
    for (MapEntry<String, DeployHandler> item in _deployHandlers.entries) {
      await item.value.cleanupEnvironment(config, _environments[item.key]!);
      await item.value.logoff();
    }
  }
}
