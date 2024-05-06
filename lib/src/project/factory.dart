import '../../api/types.dart';
import '../../api/tiefile.dart';
import '../project/flutter.dart';
import '../project/java.dart';
import '../project/nextjs.dart';
import '../project/node.dart';
import '../project/springboot.dart';

ProjectProvider? buildProject() {
  // cycle through to find the project time
  NodeProject node = NodeProject();
  node.init();

  if (node.isProject()) {
    // test if it's a nextjs project
    NextJSProject nextjs = NextJSProject();
    nextjs.init();
    if (nextjs.isProject()) {
      return nextjs;
    }

    // return default node project
    return node;
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

  FlutterProject flutter = FlutterProject();
  flutter.init();
  if (flutter.isProject()) {
    return flutter;
  }

  return null;
}


ImageDefinition? defaultImageDefinition(ImageType imageType, BuildType? buildType) {
  ImageDefinition? definition;
  switch (imageType) {
    case (ImageType.springboot):
      return SpringbootProject.defaultImageDefinition();
    case (ImageType.node):
      return NodeProject.defaultImageDefinition();
    case (ImageType.nextjs):
      return NextJSProject.defaultImageDefinition();
    case (ImageType.nginx): {
      if (buildType == BuildType.flutter) {
        return FlutterProject.defaultImageDefinition();
      }
    }
    default:
  }
  return definition;
}