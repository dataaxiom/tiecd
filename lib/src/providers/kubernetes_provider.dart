import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:http/io_client.dart';
import 'package:json2yaml/json2yaml.dart';
import 'package:meta/meta.dart';
import 'package:posix/posix.dart';
import 'package:tiecd/src/extensions.dart';
import 'package:uuid/uuid.dart';
import 'package:yaml/yaml.dart';
import 'package:kubernetes/kubernetes.dart';
import 'package:kubernetes/core_v1.dart' as api_core_v1;

import '../api/dsl.dart';
import '../api/provider.dart';
import '../api/types.dart';
import '../commands/helm.dart';
import '../commands/kubectl.dart';
import '../commands/skopeo.dart';
import '../log.dart';
import '../util.dart';

class KubernetesProvider implements DeployProvider {
  final Config _config;
  String? _kubeConfigFilename;
  KubernetesClient? _kubernetesClient;
  KubernetesClient? kubernetesClient;
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

  KubernetesProvider(this._config) {
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
                      var result =
                          await Process.run(command, [], runInShell: true);
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
  String getDestinationRegistry(Environment environment) {
    return "";
  }

  @override
  String getDestinationImageName(Environment environment, Image image) {
    return image.name!;
  }

  String? buildNamespace(DeployContext deployContext, {String? namespace}) {
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
        _kubernetesClient!.createCoreV1Namespace(body: v1namespace);
      }
    }
    return buildName;
  }

  @override
  Future<void> processImage(DeployContext deployContext) async {
    if (deployContext.app.images != null) {
      var skopeoCmd = SkopeoCommand(_config);
      var images = deployContext.app.images;
      if (images != null) {
        for (var image in images) {
          ImageRepository? imageRepository;
          if (deployContext.repositories.length == 1) {
            imageRepository = deployContext.repositories[0];
          } else if (deployContext.repositories.length > 1) {
            // find the correct one
            if (image.registry != null) {
              for (var registry in deployContext.repositories) {
                if (image.registry == registry.name) {
                  imageRepository = registry;
                  break;
                }
              }
            } else {
              // let's just use first repo by default
              imageRepository = deployContext.repositories[0];
            }
          } else {
            if (image.registry != null) {
              throw TieError(
                  'No valid image repo found for: ${image.registry}');
            } else {
              throw TieError('No valid image repo found');
            }
          }

          if (imageRepository != null) {
            if (imageRepository.url.isNotNullNorEmpty) {
              skopeoCmd.srcRepo = imageRepository.url;
            } else {
              throw TieError("Source image repo is empty");
            }
            if (imageRepository.username.isNotNullNorEmpty) {
              skopeoCmd.srcUsername = imageRepository.username!;
            }
            if (imageRepository.password != null) {
              skopeoCmd.srcPassword = imageRepository.password!;
            } else if (imageRepository.token.isNotNullNorEmpty) {
              skopeoCmd.srcToken = imageRepository.token!;
            }
            if (imageRepository.tlsVerify != null) {
              skopeoCmd.srcTlsVerify = imageRepository.tlsVerify!;
            }

            if (deployContext.environment.repository != null) {
              var destImageRepo = deployContext.environment.repository;
              if (destImageRepo != null) {
                if (destImageRepo.url != null) {
                  skopeoCmd.destRepo = destImageRepo.url!;
                } else {
                  throw TieError(
                      'Destination image repo url is empty in environment');
                }
                if (destImageRepo.username.isNotNullNorEmpty) {
                  skopeoCmd.destUsername = destImageRepo.username!;
                }
                if (destImageRepo.password.isNotNullNorEmpty) {
                  skopeoCmd.destPassword = destImageRepo.password!;
                }
                if (destImageRepo.token.isNotNullNorEmpty) {
                  skopeoCmd.destToken = destImageRepo.token!;
                }
                if (destImageRepo.tlsVerify != null) {
                  skopeoCmd.destTlsVerify = destImageRepo.tlsVerify!;
                }
              } else {
                throw TieError(
                    'No destination image repository specified in target environment');
              }
            }

            if (image.name != null) {
              var version = image.version;
              version ??= "latest";
              var imageName = "${image.name}:$version";
              // image stream doesn't support sub paths
              var destImageName =
                  getDestinationImageName(deployContext.environment, image);
              var fullDestImageName = "$destImageName:$version";

              // get the sha for the image and setup deploy vars
              var sha = await skopeoCmd.imageSha(imageName);

              if (images.length == 1) {
                deployContext.app.tiecdEnv!['TIECD_IMAGE_SHA'] = sha;
                deployContext.app.tiecdEnv!['TIECD_IMAGE_NAME'] = destImageName;
                deployContext.app.tiecdEnv!['TIECD_IMAGE_VERSION'] = version;
                if (_config.verbose) {
                  Log.info('adding TIECD_IMAGE_SHA to environment: $sha');
                  Log.info(
                      'adding TIECD_IMAGE_NAME to environment: $destImageName');
                  Log.info(
                      'adding TIECD_IMAGE_VERSION to environment: $version');
                }
                var envImageName = image.name!
                    .toUpperCase()
                    .replaceAll('-', "_")
                    .replaceAll('/', '_');
                deployContext.app.tiecdEnv!['TIECD_IMAGE_${envImageName}_SHA'] =
                    sha;
                deployContext
                        .app.tiecdEnv!['TIECD_IMAGE_${envImageName}_NAME'] =
                    destImageName;
                deployContext.app
                    .tiecdEnv!['TIECD_IMAGE_${envImageName}_VERSION'] = version;

                if (_config.verbose) {
                  Log.info(
                      'adding TIECD_IMAGE_${envImageName}_SHA to environment: $sha');
                  Log.info(
                      'adding TIECD_IMAGE_${envImageName}_NAME to environment: $destImageName');
                  Log.info(
                      'adding TIECD_IMAGE_${envImageName}_VERSION to environment: $version');
                }

                // push the image if setup
                if (deployContext.environment.repository?.mode ==
                    ImageMode.push) {
                  await skopeoCmd.deployImage(imageName, fullDestImageName);
                }
              }
            } else {
              throw TieError('image name can not be null');
            }
          } else {
            throw TieError('Source image registry is missing');
          }
        }
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
  Future<void> processConfig(DeployContext deployContext) async {
    if (deployContext.app.deploy!.mountFiles != null) {
      StringBuffer cksum = StringBuffer();
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

          var kubectl = KubeCtlCommand(_config, _kubeConfigFilename!);
          var namespace = buildNamespace(deployContext);

          // apply the manifest and save the cksum hash
          cksum.write(await kubectl.applyManifestByValue(mountFile.file!,
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
      var bytes = utf8.encode(cksum.toString());
      var digest = md5.convert(bytes);
      deployContext.app.tiecdEnv!['TIECD_CONFIG_HASH'] = digest.toString();
      Log.info('adding TIECD_CONFIG_HASH to environment: $digest');
    }
  }

  @override
  Future<void> processSecrets(DeployContext deployContext) async {
    //throw new Error('Method not implemented.');
  }

  @override
  Future<void> processHelm(DeployContext deployContext) async {
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
        // verify the namespace
        buildNamespace(deployContext, namespace: chart.namespace);
        if (chart.url != null && !chart.url!.startsWith("oci://")) {
          await helmCommand.addRepo(deployContext, chart);
          await helmCommand.update(deployContext);
        }
        await helmCommand.install(deployContext, chart);
        helmCommand.clean(deployContext, chart);
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
  Future<String> processDeploy(DeployContext deployContext) async {
    var checkSum = '';
    if (deployContext.app.deploy!.manifests != null) {
      for (var templateFile in deployContext.app.deploy!.manifests!) {
        var kubectl = KubeCtlCommand(_config, _kubeConfigFilename!);
        var namespace = buildNamespace(deployContext);

        // pre expand the file to check the deployment status
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
                  buildNamespace(deployContext, namespace: docNamespace);
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
    Map<String, String> env = {};
    env['KUBECONFIG'] = _kubeConfigFilename!;
    for (var script in scripts) {
      await runScript(deployContext, script, environment: env);
    }
  }

  Future<void> processRemove(DeployContext deployContext) async {
    //throw new Error('Method not implemented.');
  }
}
