import 'dart:convert';
import 'dart:io';

import 'package:yaml/yaml.dart';

import '../api/tiefile.dart';
import '../api/types.dart';

class FlutterProject extends ProjectProvider {

  bool _isFlutter = false;

  @override
  List<String>? beforeBuildScripts() {
    return null;
  }

  @override
  List<String>? buildScripts() {
    return ["flutter build web"];
  }

  @override
  List<String>? afterBuildScripts() {
    return null;
  }

  @override
  Map<String, String> buildEnv() {
    return {};
  }

  @override
  void init() {
    if (File('pubspec.yaml').existsSync()) {
      // lets check if there is a flutter dependency
      final pubspecFile = loadYaml(File('pubspec.yaml').readAsStringSync());
      name = pubspecFile['name'];
      version = pubspecFile['version'];
      var dependencies = pubspecFile['dependencies'];
      if (dependencies['flutter'] != null) {
        _isFlutter = true;
        // we default to nginx
        imageType ??= ImageType.nginx;
        buildType = BuildType.flutter;
      }
    }
  }

  @override
  bool isProject() {
    return _isFlutter;
  }

  static ImageDefinition defaultImageDefinition() {
    ImageDefinition definition = ImageDefinition();
    definition.from = 'nginx:alpine';
    definition.expose = ['80'];
    definition.label = ['tiecd.image.type=nginx'];
    definition.copy = ['build/web /usr/share/nginx/html'];
    return definition;
  }

}