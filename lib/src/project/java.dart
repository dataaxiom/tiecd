import 'dart:io';
import 'package:meta/meta.dart';
import 'package:xml/xml.dart';

import '../api/tiefile.dart';
import '../api/types.dart';

class JavaProject extends ProjectProvider {

  bool _isJava = false;
  String? _sourceJdkVersion;
  String? _targetJdkVersion;

  @protected
  String? get sourceJdkVersion => _sourceJdkVersion;
  @protected
  set sourceJdkVersion(String? sourceJdkVersion) => _sourceJdkVersion = sourceJdkVersion;

  @protected
  String? get targetJdkVersion => _targetJdkVersion;
  @protected
  set targetJdkVersion(String? targetJdkVersion) => _targetJdkVersion = targetJdkVersion;

  @override
  void init() {
    if (File('pom.xml').existsSync()) {
      _isJava = true;
      buildType = BuildType.maven;
      var tiecdJdkVersionEnv = Platform.environment['TIECD_JDK_VERSION'];
      var pom = File('pom.xml').readAsStringSync();
      final document = XmlDocument.parse(pom);
      name =
          document
              .getElement("project")
              ?.getElement("artifactId")
              ?.innerText;
      version =
          document
              .getElement("project")
              ?.getElement("version")
              ?.innerText;

      // try to compiler plugin way
      _sourceJdkVersion = document
          .getElement("project")
          ?.getElement("properties")
          ?.getElement("maven.compiler.target")
          ?.innerText;
      _targetJdkVersion = document
          .getElement("project")
          ?.getElement("properties")
          ?.getElement("maven.compiler.target")
          ?.innerText;

      // if _jdkVersion is not set look for plugin config
      if (_targetJdkVersion == null || _sourceJdkVersion == null) {
        var plugins = document
            .getElement("project")
            ?.getElement("build")
            ?.getElement("plugins")
            ?.childElements;
        if (plugins != null) {
          for (var plugin in plugins) {
            if (plugin
                .getElement("artifactId")
                ?.innerText ==
                "maven-compiler-plugin") {
              _sourceJdkVersion = plugin
                  .getElement("configuration")
                  ?.getElement("source")
                  ?.innerText;
              _targetJdkVersion = plugin
                  .getElement("configuration")
                  ?.getElement("target")
                  ?.innerText;
              break;
            }
          }
        }

        if (_targetJdkVersion == null || _sourceJdkVersion == null) {
          // try new jdk9+ way
          // todo make work calling runtime java --version
          if (tiecdJdkVersionEnv != null) {
            var tiecdJdkVersion = int.parse(tiecdJdkVersionEnv);
            if (tiecdJdkVersion > 8) {
              var releaseValue = document
                  .getElement("project")
                  ?.getElement("properties")
                  ?.getElement("maven.compiler.release")
                  ?.innerText;
              if (releaseValue == null) {
                // try plugin config
                var plugins = document
                    .getElement("project")
                    ?.getElement("build")
                    ?.getElement("plugins")
                    ?.childElements;
                if (plugins != null) {
                  for (var plugin in plugins) {
                    if (plugin
                        .getElement("artifactId")
                        ?.innerText ==
                        "maven-compiler-plugin") {
                      releaseValue = plugin
                          .getElement("configuration")
                          ?.getElement("release")
                          ?.innerText;
                      break;
                    }
                  }
                }
              }
              if (releaseValue != null) {
                if (releaseValue == '1.8') {
                  releaseValue = '8';
                }
                var jdkRelease = int.parse(releaseValue);
                if (jdkRelease > tiecdJdkVersion) {
                  // target release compilation is greater then build environment jdk
                  throw TieError(
                      'jdk release compiler version is greater than build environment, switch to jdk $jdkRelease tiecd image version or higher');
                } else {
                  _sourceJdkVersion = tiecdJdkVersionEnv;
                  _targetJdkVersion = releaseValue;
                }
              }
            }
          }
        }
      }

      if (_targetJdkVersion == null && _sourceJdkVersion == null &&
          tiecdJdkVersionEnv != null) {
        _targetJdkVersion = tiecdJdkVersionEnv;
        _sourceJdkVersion = tiecdJdkVersionEnv;
      } else if (_targetJdkVersion == null && _sourceJdkVersion == null) {
        // todo to use java -version output
        throw TieError ("could not determine java version is use");
      }else if (_targetJdkVersion == null && _sourceJdkVersion != null) {
        _targetJdkVersion = _sourceJdkVersion;
      } else if (_sourceJdkVersion == null && _targetJdkVersion != null) {
        _sourceJdkVersion = _targetJdkVersion;
      }

    } else if (File('build.gradle').existsSync()) {
      _isJava = true;
      buildType = BuildType.gradle;
      throw TieError("todo gradle support");
    }
  }

  @override
  bool isProject() {
    return _isJava;
  }

  @override
  Map<String, String> buildEnv() {
    return {};
  }

  @override
  List<String>? beforeBuildScripts() {
    if (buildType == BuildType.maven) {
      return ['mvn -B clean'];
    }
    return null;
  }

  @override
  List<String>? buildScripts() {
    if (buildType == BuildType.maven) {
      return ['mvn -B install'];
    }
    return null;
  }

  @override
  List<String>? afterBuildScripts() {
    return null;
  }

  static ImageDefinition defaultImageDefinition() {
    ImageDefinition definition = ImageDefinition();
     // "quay.io/jkube/jkube-java:0.0.23";
    return definition;
  }

}
