import 'dart:convert';

import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/io_client.dart';
import 'package:json2yaml/json2yaml.dart';
import 'package:meta/meta.dart';
import 'package:posix/posix.dart';
import 'package:tiecd/src/commands/ytt.dart';
import 'package:uuid/uuid.dart';
import 'package:yaml/yaml.dart';
import 'package:kubernetes/kubernetes.dart';
import 'package:kubernetes/core_v1.dart' as api_core_v1;

import '../api/tiefile.dart';
import '../api/types.dart';
import '../commands/helm.dart';
import '../commands/kubectl.dart';
import '../commands/skopeo.dart';
import '../log.dart';
import '../util.dart';
import '../extensions.dart';
import '../util/image_tag.dart';

class KubernetesHandler implements DeployHandler {
  final Config _config;
  String? _kubeConfigFilename;
  KubernetesClient? _kubernetesClient;
  IOClient? _ioClient;
  final Set<String> _namespaces = {};

  @protected
  String? get kubeConfigFilename => _kubeConfigFilename;
  @protected
  set kubeConfigFilename(newValue) {
    _kubeConfigFilename = newValue;
  }

  @protected
  Config get config => _config;

  KubernetesHandler(this._config) {
    _kubeConfigFilename = "${_config.scratchDir}/${Uuid().v4()}";
  }

  @override
  Future<void> expandEnvironment(Environment environment) async {

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
    // if we have an apiConfig set to a KUBE_CONFIG file extract the values
    if (environment.apiConfig != null) {
      var kubeConfig = loadYaml(environment.apiConfig!);
      if (kubeConfig['kind'] == 'Config') {
        if (environment.name == null && kubeConfig["current-context"] != null) {
          environment.name = kubeConfig["current-context"];
        }
        var currentContext = kubeConfig["current-context"];
        if (kubeConfig["contexts"] != null) {
          for (var context in kubeConfig["contexts"]) {
            if (context['name'] == currentContext) {
              var clusterName = context['context']['cluster'];
              // set namespace if not set
              var clusterNamespace = context['context']['namespace'];
              if (environment.namespace == null && clusterNamespace != null) {
                environment.namespace = clusterNamespace;
              }
              for (var cluster in kubeConfig['clusters']) {
                if (clusterName == cluster['name']) {
                  environment.apiUrl ??= cluster['cluster']['server'];
                  environment.apiClientCA ??=
                      cluster['cluster']['certificate-authority-data'];
                  break;
                }
              }

              var userName = context['context']['user'];
              for (var user in kubeConfig['users']) {
                if (userName == user['name']) {
                  environment.apiToken ??= user['user']['token'];
                  environment.apiClientCert ??=
                      user['user']['client-certificate-data'];
                  environment.apiClientKey ??= user['user']['client-key-data'];

                  // check if the user credential is external
                  if (user['user']['exec'] != null) {
                    var command = user['user']['exec']['command'];
                    if (command != null) {
                      //  run the external credential provider
                      var args = <String>[];
                      var commandArgs = user['user']['exec']['args'];
                      if (commandArgs != null) {
                        for (var arg in commandArgs) {
                          args.add(arg);
                        }
                      }
                      var result = await Process.run(command, args,
                          environment: getHandlerEnv(), runInShell: true);
                      if (result.exitCode == 0) {
                        var response = result.stdout;
                        final authResult = jsonDecode(response);
                        var kind = authResult['kind'];
                        if (kind != null && kind == 'ExecCredential') {
                          if (authResult['status'] != null) {
                            environment.apiToken =
                                authResult['status']['token'];
                          } else {
                            throw TieError(
                                "unknown credential status response: $response");
                          }
                        } else {
                          throw TieError("unknown credential type: $kind");
                        }
                      } else {
                        var response = result.stdout;
                        print("tf: $response");
                        throw TieError("could not get external credentials");
                      }
                    }
                  }

                  break;
                }
              }
              break;
            }
          }
        }
      }
    }
  }

  @override
  Future<void> login(DeployContext deployContext) async {
    var environmentName = deployContext.environment.name;
    environmentName ??= '';
    if (deployContext.environment.apiUrl.isNullOrEmpty) {
      throw TieError("cluster $environmentName apiUrl is not set");
    }
    if (deployContext.environment.apiToken.isNullOrEmpty &&
        deployContext.environment.apiClientCert.isNullOrEmpty &&
        deployContext.environment.apiClientKey.isNullOrEmpty) {
      throw TieError(
          "cluster $environmentName apiToken or apiClientCert/apiClientKey is not set");
    }
    // if we still don't have a name
    deployContext.environment.name ??= deployContext.environment.apiUrl;

    // only output if file level config isn't already created
    if (!File(_kubeConfigFilename!).existsSync()) {
      if (deployContext.environment.apiConfig.isNotNullNorEmpty) {
        File(_kubeConfigFilename!).writeAsStringSync(
            deployContext.environment.apiConfig!,
            flush: true);
        // set restricted file permissions
        chmod(_kubeConfigFilename!, "400");
      }
    }
    SecurityContext context = SecurityContext(withTrustedRoots: true);
    HttpClient httpClient = HttpClient(context: context);
    if (deployContext.environment.apiTlsVerify == false) {
      // todo - probably should narrow the callback to only the api endpoint
      httpClient.badCertificateCallback =
          (X509Certificate cert, String host, int port) => true;
    }
    if (deployContext.environment.apiClientCA != null) {
      context.setTrustedCertificatesBytes(
          base64.decode(deployContext.environment.apiClientCA!));
    }
    _ioClient = IOClient(httpClient);

    if (deployContext.environment.apiToken.isNotNullNorEmpty) {
      _kubernetesClient = KubernetesClient(
          serverUrl: deployContext.environment.apiUrl!,
          accessToken: deployContext.environment.apiToken!,
          httpClient: _ioClient);
    } else if (deployContext.environment.apiClientCert.isNotNullNorEmpty &&
        deployContext.environment.apiClientKey.isNotNullNorEmpty) {
      context.useCertificateChainBytes(
          base64.decode(deployContext.environment.apiClientCert!));
      context.usePrivateKeyBytes(
          base64.decode(deployContext.environment.apiClientKey!));

      _kubernetesClient = KubernetesClient(
          serverUrl: deployContext.environment.apiUrl!,
          accessToken: '',
          httpClient: _ioClient);
    }

    // get list of namespaces
    if (_config.createNamespaces) {
      var namespaces = await _kubernetesClient!.listCoreV1Namespace();
      for (var namespace in namespaces.items) {
        _namespaces.add(namespace.metadata!.name!);
      }
    }
  }

  @override
  Future<void> logoff(DeployContext deployContext) async {
    if (_kubeConfigFilename.isNotNullNorEmpty &&
        File(_kubeConfigFilename!).existsSync()) {
      File(_kubeConfigFilename!).deleteSync();
    }
    if (_ioClient != null) {
      _ioClient!.close();
    }
  }

  @override
  bool isDestinationRegistryAuthRequired(Environment environment) {
    return true;
  }

  @override
  String getDestinationImageName(Environment environment, Image image) {
    ImageTag imageTag = ImageTag(image.tag!);
    return '${environment.registry!.host}/${imageTag.path}';
  }

  Future<String?> buildNamespace(DeployContext deployContext,
      {String? namespace}) async {
    var buildName = namespace; // maybe we've been passed one
    buildName ??= findNamespace(deployContext);
    if (buildName != null) {
      // create namespace if necessary
      if (_config.createNamespaces &&
          !_namespaces.contains(buildName) &&
          buildName != 'default') {
        var namespaceJson = {
          "apiVersion": "v1",
          "kind": "Namespace",
          "metadata": {
            "name": buildName,
          }
        };
        Log.info('creating namespace $buildName');
        var v1namespace = api_core_v1.Namespace.fromJson(namespaceJson);
        await _kubernetesClient!.createCoreV1Namespace(body: v1namespace);
        !_namespaces.add(buildName);
      }
    }
    return buildName;
  }

  @override
  Future<void> handleImage(DeployContext deployContext) async {
    if (deployContext.app.image != null) {
      var skopeoCmd = SkopeoCommand(_config);
      var image = deployContext.app.image!;
      if (image.tag != null) {
        ImageTag imageTag = ImageTag(image.tag!);
        skopeoCmd.initSourceRepo(deployContext.registries, image.tag!);
        skopeoCmd.setTargetRepo(deployContext.environment.registry);

        var tag = imageTag.tag;
        if (tag.isNullOrEmpty) {
          tag = "latest";
        }
        // get the sha for the image and setup deploy vars
        var sha = await skopeoCmd.imageSha(image.tag!);

        deployContext.app.tiecdEnv!['TIECD_IMAGE_SHA'] = sha;
        deployContext.app.tiecdEnv!['TIECD_IMAGE_NAME'] = imageTag.name;
        deployContext.app.tiecdEnv!['TIECD_IMAGE_TAG'] = tag;
        if (_config.verbose) {
          Log.info('adding TIECD_IMAGE_SHA to environment: $sha');
          Log.info('adding TIECD_IMAGE_NAME to environment: ${imageTag.name}');
          Log.info('adding TIECD_IMAGE_TAG to environment: $tag');
        }
        var envImageName = imageTag.name
            .toUpperCase()
            .replaceAll('-', "_")
            .replaceAll('/', '_');
        deployContext.app.tiecdEnv!['TIECD_IMAGE_${envImageName}_SHA'] = sha;
        deployContext.app.tiecdEnv!['TIECD_IMAGE_${envImageName}_NAME'] =
            imageTag.name;
        deployContext.app.tiecdEnv!['TIECD_IMAGE_${envImageName}_TAG'] =
            tag;

        if (_config.verbose) {
          Log.info(
              'adding TIECD_IMAGE_${envImageName}_SHA to environment: $sha');
          Log.info(
              'adding TIECD_IMAGE_${envImageName}_NAME to environment: ${imageTag.name}');
          Log.info(
              'adding TIECD_IMAGE_${envImageName}_TAG to environment: $tag');
        }

        // push the image if setup
        if (deployContext.environment.registry != null &&
            deployContext.environment.registry!.host != null) {
          var destImageName =
          getDestinationImageName(deployContext.environment, image);
          var fullDestImageName = "$destImageName:$tag";
          await skopeoCmd.deployImage(image.tag!, fullDestImageName);

          // generate docker pull registry credential
          if (isDestinationRegistryAuthRequired(deployContext.environment)) {
            String? auth;
            if (deployContext.environment.registry!.token.isNotNullNorEmpty) {
              auth = 'token:${deployContext.environment.registry!.token}';
            } else if (deployContext.environment.registry!.username.isNotNullNorEmpty &&
                  deployContext.environment.registry!.password.isNotNullNorEmpty) {
              auth = '${deployContext.environment.registry!.username}:${deployContext.environment.registry!.password}';
            }
            if (auth.isNotNullNorEmpty) {
              auth = base64.encode(utf8.encode(auth!));

              // build docker config.json
              var dockerCred = {
                "auths": {
                  deployContext.environment.registry!.host!: {
                    "auth": auth
                  }
                }
              };
              auth = base64.encode(utf8.encode(jsonEncode(dockerCred)));
              var name = sanitizeDNSName(
                  '${deployContext.app.name}-${deployContext.environment.registry!.host!}-regcred');
              var dockerSecret = {
                "apiVersion": "v1",
                "kind": "Secret",
                "type": "kubernetes.io/dockerconfigjson",
                "metadata": {
                  "name": name,
                  "labels": {
                    "app.kubernetes.io/component": deployContext.app.label,
                    "app.kubernetes.io/instance": deployContext.app.label,
                    "app.kubernetes.io/managed-by": "tiecd",
                    "app.kubernetes.io/name": deployContext.app.label
                  }
                },
                "data": {
                  ".dockerconfigjson": auth
                }
              };
              var dockerSecretYaml = json2yaml(dockerSecret);
              if (deployContext.app.deploy!.ytt != null && deployContext.app.deploy!.ytt!.files != null) {
                Log.verbose(_config,'applying ytt files for docker auth config secret');
                YttCommand ytt = YttCommand(_config);
                dockerSecretYaml = await ytt.transform(dockerSecretYaml, deployContext.app.deploy!.ytt!);
              }
              var namespace = await buildNamespace(deployContext);
              KubeCtlCommand kubectl = KubeCtlCommand(_config, this);
              await kubectl.applyManifestByValue('dockerauthconfig.yaml',
                  dockerSecretYaml, deployContext.getEnv(), namespace);
              deployContext.deployedArifacts.add('secret/$name');
            }
          }
        }
      } else {
        throw TieError('Image tag is missing');
      }
    }
    // else just skip over processing
  }

  String generateMountName(String appName, String mountFile) {
    var mountString = (mountFile != "") ? mountFile : "";
    if (mountString.startsWith("/")) {
      mountString = mountFile.substring(1); // strip /
    }
    mountString = mountString
        .replaceAll("/", "-")
        .replaceAll(".", "-")
        .toLowerCase()
        .replaceAll("[^-a-z0-9]", "");
    var name = (mountString == "") ? appName : "$appName-$mountString";
    if (name.length > 63) {
      // we can only use 63 chars in names
      var newMountFileLength = 62 - appName.length;
      name =
          "$appName-${mountString.substring(mountString.length - newMountFileLength + 1)}";
    }
    return name;
  }

  String stripConfigFilePath(String fileName) {
    if (fileName.contains("/")) {
      return fileName.substring(fileName.lastIndexOf('/') + 1);
    } else {
      return fileName;
    }
  }

  @override
  Future<void> handleConfig(DeployContext deployContext) async {
    if (deployContext.app.deploy!.mountFiles != null) {
      StringBuffer checksum = StringBuffer();
      for (var mountFile in deployContext.app.deploy!.mountFiles!) {
        if (mountFile.file != null &&
            File("${_config.baseDir}/${mountFile.file}").existsSync()) {
          String mountPath = "";
          if (mountFile.mount != null) {
            mountPath = mountFile.mount!;
          } else {
            // use the mountFile as the mountFile
            mountPath = mountFile.file!;
            //}
            mountFile.mount = mountPath;
          }

          var logicalName =
              generateMountName(deployContext.app.name!, mountPath);
          var strippedName = stripConfigFilePath(mountPath);

          // properties expansion
          var rawFile =
              File('${_config.baseDir}/${mountFile.file!}').readAsStringSync();

          var configMap = {
            "apiVersion": "v1",
            "kind": "ConfigMap",
            "metadata": {
              "name": logicalName,
              "labels": {
                "app.kubernetes.io/component": deployContext.app.label,
                "app.kubernetes.io/instance": deployContext.app.label,
                "app.kubernetes.io/managed-by": "tiecd",
                "app.kubernetes.io/name": deployContext.app.label
              }
            },
            "data": {strippedName: rawFile}
          };

          var kubectl = KubeCtlCommand(_config, this);
          var namespace = await buildNamespace(deployContext);

          // apply the manifest and save the cksum hash
          checksum.write(await kubectl.applyManifestByValue(mountFile.file!,
              json2yaml(configMap), deployContext.getEnv(), namespace));
        } else {
          if (mountFile.file == null) {
            throw TieError('file attribute does not exist in mountFile entry');
          } else {
            throw TieError('file: ${mountFile.file!} does not exist');
          }
        }
      }
      // calc total config checksum
      var bytes = utf8.encode(checksum.toString());
      var digest = md5.convert(bytes);
      deployContext.app.tiecdEnv!['TIECD_CONFIG_HASH'] = digest.toString();
      Log.info('adding TIECD_CONFIG_HASH to environment: $digest');
    }
  }

  @override
  Future<void> handleSecrets(DeployContext deployContext) async {
    //throw new Error('Method not implemented.');
  }

  @override
  Future<void> handleHelm(DeployContext deployContext) async {
    if (deployContext.app.deploy!.helmChart != null) {
      var chart = deployContext.app.deploy!.helmChart!;
      var chartLog = chart.url;
      if (chartLog != null) {
        if (!chartLog.startsWith("oci://") && chart.chart != null) {
          chartLog += " ${chart.chart!}";
        } else if (!chartLog.startsWith("oci://")) {
          throw TieError('chart name can\'t be empty');
        }

        Log.info('applying helm chart: $chartLog');
        var helmCommand = HelmCommand(_config, _kubeConfigFilename!);
        try {
          // verify the namespace
          buildNamespace(deployContext, namespace: chart.namespace);
          if (chart.url != null && !chart.url!.startsWith("oci://")) {
            await helmCommand.addRepo(deployContext, chart);
            await helmCommand.update(deployContext);
          }
          await helmCommand.install(deployContext, chart);
          await helmCommand.clean(deployContext, chart);
        } catch (error) {
          rethrow;
        } finally {
          await helmCommand.clean(deployContext, chart);
        }
      } else {
        throw TieError('helm chart url is not set');
      }
    }
  }

  @override
  Future<void> removeHelm(DeployContext deployContext) async {
    if (deployContext.app.deploy!.helmChart != null) {
      var chart = deployContext.app.deploy!.helmChart!;
      var helmCommand = HelmCommand(_config, _kubeConfigFilename!);
      await helmCommand.remove(deployContext, chart);
      helmCommand.clean(deployContext, chart);
    }
  }

  @override
  Future<String> deploy(DeployContext deployContext) async {
    var checkSum = '';
    if (deployContext.app.deploy!.manifests != null) {
      for (var templateFile in deployContext.app.deploy!.manifests!) {
        var kubectl = KubeCtlCommand(_config, this);
        var namespace = await buildNamespace(deployContext);
        // pre expand the file to check the deployment status
        if (!File('${_config.baseDir}/$templateFile').existsSync()) {
          throw TieError('${_config.baseDir}/$templateFile doesn\'t exist');
        }
        var expanded = expandFileByNameWithProperties(
            '${_config.baseDir}/$templateFile', deployContext.getEnv());
        // split the yaml doc if necessary
        List<String> docs = expanded.split(RegExp(multiLine: true, "^---\$"));
        // get all the current revisions - 0 if not deployed - currently supporting Deployment/StatefulSet/DeploymentConfig
        Map<String, Map<String, String>> revisions = {};
        for (var doc in docs) {
          Map yamlDoc = loadYaml(doc);
          String? name = yamlDoc["metadata"]["name"];
          if (name != null) {
            String? nameSpaceInUse = namespace;
            String? docNamespace = yamlDoc["metadata"]["namespace"];
            if (docNamespace != null) {
              nameSpaceInUse =
                  await buildNamespace(deployContext, namespace: docNamespace);
            }
            nameSpaceInUse ??= "default";

            // lets now get the revision
            if (yamlDoc["kind"] == "Deployment") {
              int currentVersion = 0;
              try {
                var deployment = await _kubernetesClient!
                    .readAppsV1NamespacedDeployment(
                        name: name, namespace: nameSpaceInUse);
                if (deployment.status != null &&
                    deployment.status!.observedGeneration != null) {
                  currentVersion = deployment.status!.observedGeneration!;
                  print(
                      'Current revision for deployment/$name = $currentVersion');
                }
              } catch (error) {
                // need to find a better way - api doesn't support not found approach
              }
              revisions['Deployment-$name'] = {
                'name': name,
                'version': currentVersion.toString(),
                'namespace': nameSpaceInUse
              };
            } else if (yamlDoc['kind'] == "StatefulSet") {
              int currentVersion = 0;
              try {
                var deployment = await _kubernetesClient!
                    .readAppsV1NamespacedStatefulSet(
                        name: name, namespace: nameSpaceInUse);
                if (deployment.status != null &&
                    deployment.status!.observedGeneration != null) {
                  currentVersion = deployment.status!.observedGeneration!;
                  print(
                      'Current revision for statefulset/$name = $currentVersion');
                }
              } catch (error) {
                // need to find a better way - api doesn't support not found approach
              }
              revisions['StatefulSet-$name'] = {
                'name': name,
                'version': currentVersion.toString(),
                'namespace': nameSpaceInUse
              };
            }
          }
        }

        // do the actual deployment
        KubeCtlResult result = await kubectl.applyManifestByFileName(
            '${_config.baseDir}/$templateFile',
            '${_config.baseDir}/$templateFile',
            deployContext.getEnv(),
            namespace);
        checkSum += result.output;

        // sleep for 4 seconds to allow rollout status to update - if necessary
        if (revisions.isNotEmpty) {
          sleep(4);
        }

        // now check on the rollout status
        for (var entry in revisions.entries) {
          var name = entry.value['name']!;
          var version = entry.value['version']!;
          var entryNamespace = entry.value['namespace'];
          if (entry.key.startsWith("Deployment-")) {
            var deployment = await _kubernetesClient!
                .readAppsV1NamespacedDeployment(
                    name: name, namespace: entryNamespace!);
            if (deployment.status != null &&
                deployment.status!.observedGeneration != null) {
              var currentVersion = deployment.status!.observedGeneration!;
              if (currentVersion != int.parse(version)) {
                Log.info(
                    'latest revision for deployment/$name = $currentVersion');
                await kubectl.waitForRollout(
                    entryNamespace, "Deployment", name, version);
              }
            }
          } else if (entry.key.startsWith("StatefulSet-")) {
            var statefulset = await _kubernetesClient!
                .readAppsV1NamespacedStatefulSet(
                    name: name, namespace: entryNamespace!);
            if (statefulset.status != null &&
                statefulset.status!.observedGeneration != null) {
              var currentVersion = statefulset.status!.observedGeneration!;
              if (currentVersion != int.parse(version)) {
                Log.info(
                    'latest revision for statefulset/$name = $currentVersion');
                await kubectl.waitForRollout(
                    entryNamespace, "StatefulSet", name, version);
              }
            }
          }
        }
      }
    }
    return checkSum;
  }

  @override
  Future<void> runScripts(
      DeployContext deployContext, List<String> scripts) async {
    for (var script in scripts) {
      await runScript(deployContext, script, environment: getHandlerEnv());
    }
  }

  @override
  Map<String, String> getHandlerEnv() {
    Map<String, String> env = {};
    env['KUBECONFIG'] = _kubeConfigFilename!;
    return env;
  }

  void addTiecdResources(String appname, String resourceName, Map<String,String> labels, Set<String> resources) {
    if (labels.containsKey('app.kubernetes.io/name') &&
        labels['app.kubernetes.io/name'] == appname &&
        labels.containsKey('app.kubernetes.io/managed-by') &&
        labels['app.kubernetes.io/managed-by'] == 'tiecd') {
      resources.add(resourceName);
    }
  }

  @override
  Future<void> cleanup(DeployContext deployContext) async {
    if (deployContext.config.autoGeneratedCleanup || deployContext.config.autoGeneratedCleanupDryRun) {
      var namespace = await buildNamespace(deployContext);
      namespace ??= 'default';
      Set<String> currentResources = {};
      // secrets
      api_core_v1.SecretList secrets = await _kubernetesClient!
          .listCoreV1NamespacedSecret(namespace: namespace);
      for (api_core_v1.Secret secret in secrets.items) {
        var labels = secret.metadata!.labels;
        if (labels != null) {
          addTiecdResources(deployContext.app.name!,'secret/${secret.metadata!.name}',labels, currentResources);
        }
      }
      // configmaps
      api_core_v1.ConfigMapList configMaps = await _kubernetesClient!
          .listCoreV1NamespacedConfigMap(namespace: namespace);
      for (api_core_v1.ConfigMap configMap in configMaps.items) {
        var labels = configMap.metadata!.labels;
        if (labels != null) {
          addTiecdResources(deployContext.app.name!,'configmap/${configMap.metadata!.name}',labels, currentResources);
        }
      }
      // services

      for (var element in currentResources) {
        if (!deployContext.deployedArifacts.contains(element)) {
          List<String> parts = element.controlledSplit('/');
          switch (parts[0]) {
            case 'secret':
              {
                if (deployContext.config.autoGeneratedCleanupDryRun) {
                  Log.info(
                      'dry run - deleting secret ${parts[1]} in $namespace namespace');
                } else {
                  Log.info(
                      'deleting secret ${parts[1]} in $namespace namespace');
                  await _kubernetesClient!.deleteCoreV1NamespacedSecret(
                      name: parts[1], namespace: namespace);
                }
              }
            case 'configmap':
              {
                if (deployContext.config.autoGeneratedCleanupDryRun) {
                  Log.info(
                      'dry run - deleting configmap ${parts[1]} in $namespace namespace');
                } else {
                  Log.info(
                      'deleting configmap ${parts[1]} in $namespace namespace');
                  await _kubernetesClient!.deleteCoreV1NamespacedConfigMap(
                      name: parts[1], namespace: namespace);
                }
              }
          }
        }
      }
    }
  }
}
