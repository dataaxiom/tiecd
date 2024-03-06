import 'dart:core';
import 'dart:io';
import 'package:meta/meta.dart';
import 'package:path/path.dart';
import 'package:yaml/yaml.dart';
import 'package:checked_yaml/checked_yaml.dart';

import '../api/dsl.dart';
import '../api/types.dart';
import '../log.dart';
import '../util.dart';

abstract class BaseExecutor {
  final Config _config;
  final _date = DateTime.now();
  bool fileSubset = false;
  final Set<String> _fileList = {};
  final Set<String> _appList = {};

  BaseExecutor(this._config);

  @protected
  Config get config => _config;
  @protected
  DateTime get date => _date;

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

  execute(Tie tieFile, App app) async {
    // subclasses override this method
  }

  bool init() {
    var success = false;

    if (_config.baseDir == '') {
      success = initTieDirectory('.');
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
        var currentApps = 'apps to be deployed: ';
        for (var app in _appList) {
          currentApps += "$app,";
        }
        currentApps = currentApps.substring(0, currentApps.length - 1);
        Log.info(currentApps);
      } else {
        Log.info("deploying all apps");
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
      var expandedFile = expandFileByName("${_config.baseDir}/$yamlFile");
      if (expandedFile != '') {
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

        if (tieIncludeFile.repositories != null) {
          if (tieIncludeFile.repositories!.image != null) {
            tieFile.repositories ??= Repositories();
            tieFile.repositories!.image ??= [];
            for (var imageRepo in tieIncludeFile.repositories!.image!) {
              tieFile.repositories!.image!.add(imageRepo);
            }
          }
          if (tieIncludeFile.repositories!.maven != null) {
            tieFile.repositories ??= Repositories();
            tieFile.repositories!.maven ??= [];
            for (var mavenRepo in tieIncludeFile.repositories!.maven!) {
              tieFile.repositories!.maven!.add(mavenRepo);
            }
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
        throw TieError('file: $yamlFile is empty');
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

          if (app.action == null && includeApp.action != null) {
            app.action = includeApp.action;
          }

          //  String? dependsOn;
          if (app.namespace == null && includeApp.namespace != null) {
            app.namespace;
          }

          if (includeApp.images != null) {
            app.images ??= [];
            for (var image in includeApp.images!) {
              app.images!.add(image);
            }
          }

          if (includeApp.artifacts != null) {
            app.artifacts ??= [];
            for (var artifact in includeApp.artifacts!) {
              app.artifacts!.add(artifact);
            }
          }

          if (app.deploymentMode == null && includeApp.deploymentMode != null) {
            app.deploymentMode = includeApp.deploymentMode!;
          }

          if (includeApp.facets != null) {
            app.facets ??= [];
            for (var facet in includeApp.facets!) {
              app.facets!.add(facet);
            }
          }

          if (includeApp.mountFiles != null) {
            app.mountFiles ??= [];
            for (var mountFile in includeApp.mountFiles!) {
              app.mountFiles!.add(mountFile);
            }
          }

          if (includeApp.templateFiles != null) {
            app.templateFiles ??= [];
            for (var templateFile in includeApp.templateFiles!) {
              app.templateFiles!.add(templateFile);
            }
          }

          if (includeApp.deployEnv != null) {
            app.deployEnv ??= {};
            includeApp.deployEnv!.forEach(
                (key, value) => app.deployEnv!.putIfAbsent(key, () => value));
          }

          if (includeApp.deployEnvPropertyFiles != null) {
            app.deployEnvPropertyFiles ??= [];
            for (var propertyFile in includeApp.deployEnvPropertyFiles!) {
              app.deployEnvPropertyFiles!.add(propertyFile);
            }
          }

          if (includeApp.env != null) {
            app.env ??= {};
            includeApp.env!.forEach(
                (key, value) => app.env!.putIfAbsent(key, () => value));
          }

          if (includeApp.envPropertyFiles != null) {
            app.envPropertyFiles ??= [];
            for (var propertyFile in includeApp.envPropertyFiles!) {
              app.envPropertyFiles!.add(propertyFile);
            }
          }

          if (includeApp.volumes != null) {
            app.volumes ??= [];
            for (var volume in includeApp.volumes!) {
              app.volumes!.add(volume);
            }
          }

          if (includeApp.helmCharts != null) {
            app.helmCharts ??= [];
            for (var chart in includeApp.helmCharts!) {
              app.helmCharts!.add(chart);
            }
          }

          if (includeApp.postApps != null) {
            app.postApps ??= [];
            for (var postApp in includeApp.postApps!) {
              app.postApps!.add(postApp);
            }
          }

          if (includeApp.errorApps != null) {
            app.errorApps ??= [];
            for (var errorApp in includeApp.errorApps!) {
              app.errorApps!.add(errorApp);
            }
          }

          if (includeApp.preCommands != null) {
            app.preCommands ??= [];
            for (var command in includeApp.preCommands!) {
              app.preCommands!.add(command);
            }
          }

          if (includeApp.preDeployCommands != null) {
            app.preDeployCommands ??= [];
            for (var command in includeApp.preDeployCommands!) {
              app.preDeployCommands!.add(command);
            }
          }

          if (includeApp.postCommands != null) {
            app.postCommands ??= [];
            for (var command in includeApp.postCommands!) {
              app.postCommands!.add(command);
            }
          }

          if (includeApp.errorCommands != null) {
            app.errorCommands ??= [];
            for (var command in includeApp.errorCommands!) {
              app.errorCommands!.add(command);
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

  run() async {
    if (init()) {
      var hasError = false;

      for (var file in _fileList) {
        // process any includes
        Set<String> includedFiles = {};
        Tie tieFile = Tie();
        mergeFile(tieFile, file, includedFiles);

        if (tieFile.apps != null) {
          for (var app in tieFile.apps!) {
            try {
              // check we have a container name
              final appName = app.name;
              if (appName == null) {
                throw TieError('app name can\'t be empty');
              }
              // we only use alpha-numeric lowercase chars - validate other chars?
              if (appName.contains(RegExp("[^a-z0-9-]"))) {
                throw TieError(
                    'app names can only use alpha numeric and lower case characters (DNS label standard RFC 1123), app name: \'${app.name}\' is invalid.');
              }
              // if we have an applist and it includes the app name or we are processing all apps which autoRun isn't false
              if (_appList.isNotEmpty && _appList.contains(appName) ||
                  _appList.isEmpty && (app.autoRun == null || app.autoRun!)) {
                // expand the app if necessary
                Set<String> includedApps = {};
                mergeApp(tieFile, app, includedApps);
                // set label to app name if not set
                if (app.label == null) {
                  app.label = appName;
                } else if (app.label!.contains(RegExp("[^a-z0-9-]"))) {
                  throw TieError(
                      'app label can only use alpha numeric and lower case characters (DNS label standard RFC 1123), app label: \'${app.label!}\' is invalid.');
                }
                // no execute the app
                await execute(tieFile, app);

                if (_appList.isNotEmpty) {
                  _appList.remove(appName);
                }
              } else {
                // only throw error if we are using applist
                if (_appList.isNotEmpty) {
                  throw TieError(
                      'app name \'$appName\' does not exist in file $file');
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
  }
}
