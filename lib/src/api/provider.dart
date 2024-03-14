
import 'dart:convert';
import 'dart:io';

import 'package:tiecd/src/api/types.dart';

import '../util.dart';
import 'dsl.dart';

class TieContext {
  Config config;
  List<ImageRepository> repositories;
  Environment environment;
  App app;

  TieContext(this.config, this.repositories, this.environment, this.app);

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


abstract class TieProvider {
  void expandEnvironment(Environment environment);
  Future<void> login(TieContext tieContext);
  Future<void> logoff(TieContext tieContext);
  Future<void> processImage(TieContext tieContext);
  Future<void> processConfig(TieContext tieContext);
  Future<void> processSecrets(TieContext tieContext);
  Future<void> processHelm(TieContext tieContext);
  Future<String> processDeploy(TieContext tieContext);
  Future<void> runLocalCommands(TieContext tieContext, List<Command> command);
  Future<void> removeHelm(TieContext tieContext);
  String getDestinationRegistry(Environment environment);
  String getDestinationImageName(Environment environment, Image image);
}
