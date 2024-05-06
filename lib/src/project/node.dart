import 'dart:convert';
import 'dart:io';

import '../../api/tiefile.dart';
import '../../api/types.dart';
import '../extensions.dart';

class NodeProject extends ProjectProvider {

  bool _isNode = false;

  @override
  void init() {
    if (File('package.json').existsSync()) {
      _isNode = true;
      final packageFile = jsonDecode(File('package.json').readAsStringSync());
      name = packageFile['name'];
      version = packageFile['version'];

      // figure out the package manager
      if (File('yarn.lock').existsSync()) {
        buildType = BuildType.yarn;
      } else if (File('package-lock.json').existsSync()) {
        buildType = BuildType.npm;
      } else if (File('pnpm-lock.yaml').existsSync()) {
        buildType = BuildType.pnpm;
      } else {
        throw TieError("package lock file not found although a package.json was found");
      }
    }
  }

  @override
  bool isProject() {
    return _isNode;
  }

  @override
  List<String>? beforeBuildScripts() {
    if (buildType == BuildType.yarn) {
      return ['yarn --frozen-lockfile'];
    } else if (buildType == BuildType.npm) {
      return ['npm clean-install'];
    } else if (buildType == BuildType.pnpm) {
      return ['pnpm i --frozen-lockfile'];
    } else {
      return null;
    }
  }
  @override
  List<String>? buildScripts() {
    if (buildType == BuildType.yarn) {
      return ['yarn run build'];
    } else if (buildType == BuildType.npm) {
      return ['npm run build'];
    } else if (buildType == BuildType.pnpm) {
      return ['pnpm run build'];
    } else {
      return null;
    }
  }
  @override
  List<String>? afterBuildScripts() {
    return [];
  }

  @override
  Map<String, String> buildEnv() {
    return {};
  }

  static ImageDefinition defaultImageDefinition() {
    ImageDefinition definition = ImageDefinition();
    var version = Platform.environment['TIECD_NODE_VERSION'];
    if (version.isNotNullNorEmpty) {
      definition.from = 'node:$version-alpine';
    } else {
      definition.from = 'node:20-alpine';
    }
    return definition;
  }

}