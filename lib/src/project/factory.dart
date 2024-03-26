import 'package:tiecd/src/api/tiefile.dart';
import 'package:tiecd/src/project/java.dart';
import 'package:tiecd/src/project/nextjs.dart';
import 'package:tiecd/src/project/node.dart';
import 'package:tiecd/src/project/springboot.dart';

import '../api/types.dart';

ProjectProvider? buildProject() {
  // cycle through to find the project time
  NodeProject node = NodeProject();
  node.init();

  if (node.isProject()) {
    // test if it's a nextjs project
    NextJSProject nextjs = NextJSProject();
    nextjs.init();
    if (nextjs.isProject()) {
      print("is nextjs");
      return nextjs;
    }
  }

  JavaProject java = JavaProject();
  java.init();
  if (java.isProject()) {
    SpringbootProject springboot = SpringbootProject();
    springboot.init();
    if (springboot.isProject()) {
      return springboot;
    } else {
      return java;
    }
  }

  return null;
}


ImageDefinition? defaultImageDefinition(ImageType imageType) {
  ImageDefinition? definition;
  switch (imageType) {
    case (ImageType.springboot):
      return SpringbootProject.defaultImageDefinition();
    case (ImageType.node):
      return NodeProject.defaultImageDefinition();
    case (ImageType.nextjs):
      return NextJSProject.defaultImageDefinition();
    default:
  }
  return definition;
}