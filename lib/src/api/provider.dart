
import 'dart:convert';
import 'dart:io';

import 'package:meta/meta.dart';
import 'package:tiecd/src/api/types.dart';
import 'package:tiecd/src/commands/skopeo.dart';
import 'package:tiecd/src/commands/umoci.dart';
import 'package:tiecd/src/extensions.dart';

import '../project/factory.dart';
import '../util.dart';
import 'tiefile.dart';

class TieContext {
  Config config;
  List<ImageRepository> repositories;
  App app;

  TieContext(this.config, this.repositories, this.app);

  Map<String, String> getEnv() {
    // build properties
    var properties = <String, String>{};
    // set process env first
    Map<String, String> envVars = Platform.environment;
    envVars.forEach((key, value) => properties[key] = value);

    if (app.deploy != null) {
      if (app.deploy!.envPropertyFiles != null &&
          app.deploy!.envPropertyFiles!.isNotEmpty) {
        for (var envFile in app.deploy!.envPropertyFiles!) {
          readProperties(config, envFile, properties);
        }
      }
      if (app.deploy!.env != null && app.deploy!.env!.isNotEmpty) {
        app.deploy!.env!.forEach((key, value) => properties[key] = value);
      }
    }

    // deploy env takes highest order
    if (app.tiecdEnvPropertyFiles != null &&
        app.tiecdEnvPropertyFiles!.isNotEmpty) {
      for (var deployFile in app.tiecdEnvPropertyFiles!) {
        readProperties(config, deployFile, properties);
      }
    }

    if (app.tiecdEnv != null && app.tiecdEnv!.isNotEmpty) {
      app.tiecdEnv!.forEach((key, value) => properties[key] = value);
    }

    //properties.forEach((k,v) => print('${k}: ${v}'));
    return properties;
  }
}

class DeployContext extends TieContext {

  Environment environment;

  DeployContext(super.config, super.repositories, this.environment, super.app);

}

class BuildContext extends TieContext {

  BuildContext(super.config, super.repositories, super.app);

}

void readProperties(Config config, String fileName, Map<String,String> properties) {
  if (File('${config.baseDir}/$fileName').existsSync()) {
    var value = File('${config.baseDir}/$fileName').readAsStringSync();
    LineSplitter splitter = LineSplitter();
    List<String> lines = splitter.convert(value);
    for(var line in lines) {
      var expanded = varExpandByLine(line, ".properties");
      var parts = split(expanded, "=", max: 2);
      if (parts.length == 2) {
        properties[parts[0]] = parts[1];
      } else if (parts.length == 1) {
        properties[parts[0]] = "\"\"";
      }
    }
  } else {
    throw TieError('property file file does not exist: $fileName');
  }
}


abstract class DeployProvider {
  void expandEnvironment(Environment environment);
  Future<void> login(DeployContext deployContext);
  Future<void> logoff(DeployContext deployContext);
  Future<void> processImage(DeployContext deployContext);
  Future<void> processConfig(DeployContext deployContext);
  Future<void> processSecrets(DeployContext deployContext);
  Future<void> processHelm(DeployContext deployContext);
  Future<String> processDeploy(DeployContext deployContext);
  Future<void> runScripts(DeployContext deployContext, List<String> scripts);
  Future<void> removeHelm(DeployContext deployContext);
  String getDestinationRegistry(Environment environment);
  String getDestinationImageName(Environment environment, Image image);
}

enum CIProvider { gitlab, github, unknown }

abstract class ProjectProvider {
  BuildType? _buildType;
  String? _name;
  String? _version;
  CIProvider? _ciProvider;

  @protected
  BuildType? get buildType => _buildType;
  @protected
  set buildType(BuildType? buildType) => _buildType = buildType;

  @protected
  String? get name => _name;
  @protected
  set name(String? name) => _name = name;

  @protected
  String? get version => _version;
  @protected
  set version(String? version) => _version = version;

  @protected
  CIProvider? get ciProvider => _ciProvider;
  @protected
  set ciProvider(CIProvider? ciProvider) => _ciProvider = ciProvider;

  ProjectProvider() {
    var test = Platform.environment['CI_PROJECT_NAME'];
    if (test.isNotNullNorEmpty) {
      _ciProvider = CIProvider.gitlab;
    } else {
      test = Platform.environment['GITHUB_REPOSITORY'];
      if (test.isNotNullNorEmpty) {
        _ciProvider = CIProvider.github;
      }
    }
    _ciProvider ??= CIProvider.unknown;
  }

  // if the ci environment provides one
  String? getImagePath() {
    if (_ciProvider == CIProvider.gitlab) {
      return Platform.environment['CI_REGISTRY_IMAGE'];
    } else if (_ciProvider == CIProvider.gitlab) {
      if (Platform.environment['GITHUB_REPOSITORY'].isNotNullNorEmpty) {
        return 'ghcr.io/${Platform.environment['GITHUB_REPOSITORY']}';
      }
    }
    return null;
  }

  void init();
  bool isProject();

  List<String>? beforeBuildScripts();
  List<String>? buildScripts();
  List<String>? afterBuildScripts();
  Map<String,String> buildEnv();
  String getBaseImage();
  void copyArtifactsIntoImage(UmociCommand umoci);
  List<String> getUmociOptions();
}
