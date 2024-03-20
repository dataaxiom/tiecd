import 'dart:io';
import 'package:tiecd/src/extensions.dart';
import 'package:xml/xml.dart';
import '../api/types.dart';
import 'java.dart';

class SpringbootProject extends JavaProject {
  bool _isSpringboot = false;

  @override
  void init() {
    super.init();
    var pom = File('pom.xml').readAsStringSync();
    final document = XmlDocument.parse(pom);

    // check if pom has springboot parent
    var groupId = document
        .getElement('project')?.getElement('parent')?.getElement('groupId')?.innerText;
    var artifactId = document
        .getElement('project')?.getElement('parent')?.getElement('artifactId')?.innerText;

    if (groupId.isNotNullNorEmpty && groupId == 'org.springframework.boot' && artifactId.isNotNullNorEmpty && artifactId == 'spring-boot-starter-parent') {
      _isSpringboot = true;
    }

    var javaVersion = document
        .getElement("project")
        ?.getElement("properties")
        ?.getElement("java.version")
        ?.innerText;

    if (javaVersion.isNotNullNorEmpty) {

      if (javaVersion == '1.8') {
        javaVersion = '8';
      }
      var jdkRelease = int.parse(javaVersion!);
      var tiecdJdkVersion = int.parse(sourceJdkVersion!);
      if (jdkRelease > tiecdJdkVersion) {
        // target release compilation is greater then build environment jdk
        throw TieError(
            'jdk java.version compiler version is greater than build environment, switch to jdk $jdkRelease tiecd image version or higher');
      } else {
        targetJdkVersion = javaVersion;
        sourceJdkVersion = javaVersion;
      }
    }
  }

  @override
  bool isProject() {
    return _isSpringboot;
  }

}
