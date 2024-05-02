import 'dart:core';
import 'dart:io';
import 'package:json2yaml/json2yaml.dart';
import 'package:meta/meta.dart';
import 'package:path/path.dart';
import 'package:tiecd/src/extensions.dart';
import 'package:yaml/yaml.dart';
import 'package:checked_yaml/checked_yaml.dart';

import '../api/tiefile.dart';
import '../api/types.dart';
import '../log.dart';
import '../project/factory.dart';
import '../util.dart';

abstract class BaseExecutor {
  final Config _config;
  final _date = DateTime.now();
  ProjectProvider? _projectProvider;
  bool fileSubset = false;
  final Set<String> _fileList = {};
  final Set<String> _appList = {};
  bool _appListDeployment = false;
  int _numberOfApps = 0; // for each processed file

  BaseExecutor(this._config) {
    _projectProvider = buildProject();
  }

  @protected
  Config get config => _config;
  @protected
  DateTime get date => _date;
  @protected
  int get numberOfApps => _numberOfApps;
  @protected
  ProjectProvider? get projectProvider => _projectProvider;

  String getVerb() {
    return '';
  }

  bool initTieDirectory(String path) {
    bool found = false;
    if (Directory(path).existsSync()) {
      // has files been passed to program
      if (_config.files != '') {
        fileSubset = true;
        var files = _config.files.split(',');
        if (files.isNotEmpty) {
          for (var file in files) {
            if (File('$path/$file').existsSync()) {
              _fileList.add(file);
              _config.baseDir = path;
              found = true;
            } else {
              throw TieError('file $file does not exist');
            }
          }
        }
      } else {
        var files = Directory(path).listSync();
        for (var file in files) {
          var filename = basename(file.path);
          if (filename.startsWith(_config.filePrefix) &&
              (filename.endsWith(".yaml") || filename.endsWith(".yml"))) {
            _config.baseDir = path;
            found = true;
            break;
          }
        }
      }
    }
    return found;
  }

  bool setupTieFileList() {
    var error = false;

    // is there a fileorder.yml file, use that first
    var orderFileName = '';
    if (File('${_config.baseDir}/fileorder.yml').existsSync()) {
      orderFileName = 'fileorder.yml';
    } else if (File('${_config.baseDir}/fileorder.yaml').existsSync()) {
      orderFileName = "fileorder.yaml";
    }
    if (orderFileName != '') {
      var fileContents =
          File('${_config.baseDir}/$orderFileName').readAsStringSync();
      var fileOrder = loadYaml(fileContents.toString());
      for (var file in fileOrder) {
        if (File("${_config.baseDir}/$file").existsSync()) {
          _fileList.add(file);
        } else {
          Log.error('file $file referenced in $orderFileName does not exist');
          error = true;
          break;
        }
      }
    }

    if (!error) {
      // now check for all other tie files
      var files = Directory(_config.baseDir).listSync();
      for (var file in files) {
        var filename = basename(file.path);
        if (filename.startsWith(_config.filePrefix) &&
            (filename.endsWith(".yaml") || filename.endsWith(".yml"))) {
          if (!_fileList.contains(filename)) {
            _fileList.add(filename);
          }
        }
      }
    }

    return !error;
  }

  // process includes and spec inheritance
  String transformTieFile(String input) {
    return input;
  }

  initialize(Tie tieFile) async {
    //subclasses override this method if necessary
  }

  execute(Tie tieFile, App app) async {
    // subclasses override this method
  }

  cleanup() async {
    // subclasses override this method
  }


  bool directoryCheck() {
    var success = false;

    if (_config.baseDir == '') {
      success = initTieDirectory('.');
      if (!success) {
        success = initTieDirectory('tiecd');
      }
      if (!success) {
        success = initTieDirectory('src/main/deploy');
      }
    } else {
      // check for tie file current directory
      success = initTieDirectory(_config.baseDir);
    }

    if (success) {
      Log.info('using base directory: ${_config.baseDir}');
    } else {
      if (_config.baseDir == '') {
        throw TieError(
            'could not find ${_config.filePrefix}.yml files in the current directory or project default directories');
      } else {
        throw TieError(
            'could not find ${_config.filePrefix}.yml files in the directory: ${_config.baseDir}');
      }
    }

    if (success && !fileSubset) {
      // build the file list
      success = setupTieFileList();
    }

    if (success) {
      // process app name if set
      if (_config.apps != '') {
        var apps = _config.apps.split(',');
        for (var app in apps) {
          if (app == "all") {
            _appList.clear();
            break;
          } else {
            _appList.add(app);
          }
        }
      }

      if (_appList.isNotEmpty) {
        _appListDeployment = true;
        var currentApps = 'apps to be deployed: ';
        for (var app in _appList) {
          currentApps += "$app,";
        }
        currentApps = currentApps.substring(0, currentApps.length - 1);
        Log.info(currentApps);
      } else {
        Log.info("${getVerb()} all apps");
      }

      // create scratch area
      if (!Directory(_config.scratchDir).existsSync()) {
        Directory(_config.scratchDir).createSync(recursive: true);
      }
    }

    return success;
  }

  void mergeFile(Tie tieFile, String yamlFile, Set<String> includedFiles) {
    // recursively process includes
    if (File('${_config.baseDir}/$yamlFile').existsSync()) {
      Map<String, String> properties = {};

      if (projectProvider != null) {
        if (projectProvider!.name.isNotNullNorEmpty) {
          properties['TIECD_PROJECT_NAME'] = projectProvider!.name!;
        }
        if (projectProvider!.version.isNotNullNorEmpty) {
          properties['TIECD_PROJECT_VERSION'] = projectProvider!.version!;
        }
      }

      var expandedFile =
          expandFileByName("${_config.baseDir}/$yamlFile", properties);
      if (expandedFile.isNullOrEmpty) {
        Log.info('${_config.baseDir}/$yamlFile is empty using defaults');
        expandedFile = '{}';
      }
      final tieIncludeFile = checkedYamlDecode(
        expandedFile,
        (m) => Tie.fromJson(loadYaml(expandedFile)),
      );
      if (tieIncludeFile.includes != null) {
        for (var include in tieIncludeFile.includes!) {
          if (!includedFiles.contains(include)) {
            includedFiles.add(include);
            mergeFile(tieFile, include, includedFiles);
          } else {
            throw TieError(
                "duplicate include file detected, $include already has been included");
          }
        }
      }

      if (tieIncludeFile.registries != null) {
          tieFile.registries ??= [];
          for (var imageRegistry in tieIncludeFile.registries!) {
            tieFile.registries!.add(imageRegistry);
          }

      }

      if (tieIncludeFile.environments != null) {
        tieFile.environments ??= [];
        for (var environment in tieIncludeFile.environments!) {
          tieFile.environments!.add(environment);
        }
      }

      if (tieIncludeFile.apps != null) {
        tieFile.apps ??= [];
        for (var app in tieIncludeFile.apps!) {
          tieFile.apps!.add(app);
        }
      }
    } else {
      throw TieError("file: $yamlFile doesn't exist");
    }
  }

  // process app includes
  mergeApp(Tie tieFile, App app, Set<String> includedApps) {
    if (app.includes != null) {
      for (var includeAppName in app.includes!.reversed) {
        // find the app
        App? includeApp;
        for (var fileApp in tieFile.apps!) {
          if (fileApp.name == includeAppName) {
            includeApp = fileApp;
            break;
          }
        }
        if (includeApp != null) {
          // merge the app
          if (app.label == null && includeApp.label != null) {
            app.label = includeApp.label;
          }
          // autoRun doesn't inherit

          if (includeApp.tiecdEnv != null) {
            app.tiecdEnv ??= {};
            includeApp.tiecdEnv!.forEach(
                (key, value) => app.tiecdEnv!.putIfAbsent(key, () => value));
          }

          if (includeApp.tiecdEnvPropertyFiles != null) {
            app.tiecdEnvPropertyFiles ??= [];
            for (var propertyFile in includeApp.tiecdEnvPropertyFiles!) {
              app.tiecdEnvPropertyFiles!.add(propertyFile);
            }
          }

          if (includeApp.deploy != null) {
            app.deploy ??= Deploy();

            if (app.deploy!.action == null &&
                includeApp.deploy!.action != null) {
              app.deploy!.action = includeApp.deploy!.action;
            }

            //  String? dependsOn;
            if (app.deploy!.namespace == null &&
                includeApp.deploy!.namespace != null) {
              app.deploy!.namespace = includeApp.deploy!.namespace;
            }

            app.image ??= includeApp.image;

            if (app.deploy!.deploymentMode == null &&
                includeApp.deploy!.deploymentMode != null) {
              app.deploy!.deploymentMode = includeApp.deploy!.deploymentMode!;
            }

            if (includeApp.deploy!.mountFiles != null) {
              app.deploy!.mountFiles ??= [];
              for (var mountFile in includeApp.deploy!.mountFiles!) {
                app.deploy!.mountFiles!.add(mountFile);
              }
            }

            if (includeApp.deploy!.manifests != null) {
              app.deploy!.manifests ??= [];
              for (var templateFile in includeApp.deploy!.manifests!) {
                app.deploy!.manifests!.add(templateFile);
              }
            }

            if (includeApp.deploy!.ytt != null) {
              if (app.deploy!.ytt == null) {
                app.deploy!.ytt = Ytt();
              }
              if (includeApp.deploy!.ytt!.args != null) {
                var args = app.deploy!.ytt!.args;
                args ??= '';
                app.deploy!.ytt!.args = '$args ${includeApp.deploy!.ytt!.args!}';
              }
              if (includeApp.deploy!.ytt!.files != null) {
                app.deploy!.ytt!.files ??= [];
                for (var file in includeApp.deploy!.ytt!.files!) {
                  app.deploy!.ytt!.files!.add(file);
                }
              }
            }

            if (includeApp.deploy!.env != null) {
              app.deploy!.env ??= {};
              includeApp.deploy!.env!.forEach((key, value) =>
                  app.deploy!.env!.putIfAbsent(key, () => value));
            }

            if (includeApp.deploy!.envPropertyFiles != null) {
              app.deploy!.envPropertyFiles ??= [];
              for (var propertyFile in includeApp.deploy!.envPropertyFiles!) {
                app.deploy!.envPropertyFiles!.add(propertyFile);
              }
            }

            if (includeApp.deploy!.volumes != null) {
              app.deploy!.volumes ??= [];
              for (var volume in includeApp.deploy!.volumes!) {
                app.deploy!.volumes!.add(volume);
              }
            }

            if (app.deploy!.helmChart == null) {
              app.deploy!.helmChart = includeApp.deploy!.helmChart;
            }

            if (includeApp.deploy!.postApps != null) {
              app.deploy!.postApps ??= [];
              for (var postApp in includeApp.deploy!.postApps!) {
                app.deploy!.postApps!.add(postApp);
              }
            }

            if (includeApp.deploy!.errorApps != null) {
              app.deploy!.errorApps ??= [];
              for (var errorApp in includeApp.deploy!.errorApps!) {
                app.deploy!.errorApps!.add(errorApp);
              }
            }

            if (includeApp.deploy!.beforeScripts != null) {
              app.deploy!.beforeScripts ??= [];
              for (var command in includeApp.deploy!.beforeScripts!) {
                app.deploy!.beforeScripts!.add(command);
              }
            }

            if (includeApp.deploy!.scripts != null) {
              app.deploy!.scripts ??= [];
              for (var command in includeApp.deploy!.scripts!) {
                app.deploy!.scripts!.add(command);
              }
            }

            if (includeApp.deploy!.afterScripts != null) {
              app.deploy!.afterScripts ??= [];
              for (var command in includeApp.deploy!.afterScripts!) {
                app.deploy!.afterScripts!.add(command);
              }
            }

            if (includeApp.deploy!.errorScripts != null) {
              app.deploy!.errorScripts ??= [];
              for (var command in includeApp.deploy!.errorScripts!) {
                app.deploy!.errorScripts!.add(command);
              }
            }

            app.deploy!.hostname ??= includeApp.deploy!.hostname;
            app.deploy!.generateManifests ??= includeApp.deploy!.generateManifests;
          }

          if (includeApp.build != null) {
            app.build ??= Build();
            if (includeApp.build!.artifacts != null) {
              app.build!.artifacts ??= [];
              for (var artifact in includeApp.build!.artifacts!) {
                app.build!.artifacts!.add(artifact);
              }
            }
            if (includeApp.build!.imageDefinition != null) {
              app.image ??= Image();
              // TODO
            }
          }

          // comment doesn't inherit

          // now recursively process app includes
          includedApps.add(includeAppName);
          mergeApp(tieFile, includeApp, includedApps);
        } else {
          throw TieError("included app: $includeAppName not found");
        }
      }
    }
  }

  // Inject default repos - gitlab/github currently supported
  void expandImageRegistries(Tie tieFile) {
    Map<String, ImageRegistry> reposByHost = {};

    if (tieFile.registries != null) {
      for (ImageRegistry registry in tieFile.registries!) {
        if (registry.host.isNotNullNorEmpty) {
          reposByHost[registry.host!] = registry;
        }
      }
    }

    // add gitlab
    String? gitlabRegistry = Platform.environment["CI_REGISTRY"];
    if (gitlabRegistry.isNotNullNorEmpty) {
      if (!reposByHost.containsKey(gitlabRegistry)) {
        var gitlab = ImageRegistry();
        gitlab.host = gitlabRegistry;
        gitlab.username = Platform.environment["CI_REGISTRY_USER"];
        gitlab.password = Platform.environment["CI_JOB_TOKEN"];
        // add it
        tieFile.registries ??= [];
        tieFile.registries!.add(gitlab);
      }
    }

    // add github
    String? githubRepository = Platform.environment["GITHUB_REPOSITORY"];
    String? githubActor = Platform.environment["GITHUB_ACTOR"];
    String? githubToken = Platform.environment["GITHUB_TOKEN"];
    if (githubRepository.isNotNullNorEmpty &&
        githubActor.isNotNullNorEmpty &&
        githubToken.isNotNullNorEmpty) {
      String ghcr = 'ghcr.io';
      if (!reposByHost.containsKey(ghcr)) {
        var githubRegistry = ImageRegistry();
        githubRegistry.host = ghcr;
        githubRegistry.username = githubActor;
        githubRegistry.password = githubToken;
        // add it
        tieFile.registries ??= [];
        tieFile.registries!.add(githubRegistry);
      }
    }

    if (tieFile.registries != null && _config.traceTieFile) {
      List<Map> mapList = [];
      for (ImageRegistry registry in tieFile.registries!) {
        mapList.add(registry.toJson());
      }
      Log.printList(config, 'registry', 'Registries in use:', mapList);
    }
  }

  Future<void> run() async {
    try {
      if (directoryCheck()) {
        var hasError = false;

        for (var file in _fileList) {
          // process any includes
          Set<String> includedFiles = {};
          Tie tieFile = Tie();
          mergeFile(tieFile, file, includedFiles);

          expandImageRegistries(tieFile);

          await initialize(tieFile);

          if (tieFile.apps == null) {
            if (projectProvider != null) {
              // generate the very minimum app - gets expanded in build/deploy
              var genApp = App();
              if (projectProvider != null &&
                  projectProvider!.name.isNotNullNorEmpty) {
                genApp.name = projectProvider!.name;
              }
              tieFile.apps = [];
              tieFile.apps!.add(genApp);
            }
          }

          if (tieFile.apps != null) {
            _numberOfApps = tieFile.apps!.length;
            for (var app in tieFile.apps!) {
              try {
                // check we have a container name
                final appName = app.name;
                if (appName == null) {
                  throw TieError("app name can't be empty");
                }
                // we only use alpha-numeric lowercase chars - validate other chars?
                if (appName.contains(RegExp("[^a-z0-9-]"))) {
                  throw TieError(
                      'app names can only use alpha numeric and lower case characters (DNS label standard RFC 1123), app name: \'${app
                          .name}\' is invalid.');
                }
                // if we have an applist and it includes the app name or we are processing all apps which autoRun isn't false
                if (_appList.isNotEmpty && _appList.contains(appName) ||
                    !_appListDeployment && (app.autoRun == null || app.autoRun!)) {
                  // expand the app if necessary
                  Set<String> includedApps = {};
                  mergeApp(tieFile, app, includedApps);
                  // set label to app name if not set
                  if (app.label == null) {
                    app.label = appName;
                  } else if (app.label!.contains(RegExp("[^a-z0-9-]"))) {
                    throw TieError(
                        'app label can only use alpha numeric and lower case characters (DNS label standard RFC 1123), app label: \'${app
                            .label!}\' is invalid.');
                  }
                  // no execute the app
                  await execute(tieFile, app);

                  if (_appList.isNotEmpty) {
                    _appList.remove(appName);
                  }
                }
              } on TieError catch (te) {
                if (!_config.ignoreErrors) {
                  rethrow;
                } else {
                  hasError = true;
                  Log.error(te.cause);
                }
              } on Exception {
                rethrow;
              } catch (e, s) {
                Log.error('Error occurred: $e');
                print('Stack trace:\n $s');
                rethrow;
              }
            }
            await cleanup();
          } else {
            throw TieError("no apps defined in $file");
          }
        }

        if (!hasError) {
          // are there any apps not deployed?
          if (_appList.isNotEmpty) {
            var apps = '';
            for (var app in _appList) {
              apps += '$app ';
            }
            throw TieError('the following apps were not found: $apps');
          }
        } else {
          exit(1);
        }
      } else {
        exit(1);
      }
    } catch (error) {
      rethrow;
    } finally {
      if (Directory(_config.scratchDir).existsSync()) {
        Directory(_config.scratchDir).deleteSync(recursive: true);
      }
    }
  }
}

