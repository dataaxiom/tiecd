import 'dart:convert';
import 'dart:io';

import '../api/tiefile.dart';
import 'node.dart';

class NextJSProject extends NodeProject {

  bool _isNextjs = false;

  @override
  Map<String, String> buildEnv() {
    var env = <String,String>{};
    env['NEXT_TELEMETRY_DISABLED'] = '1';
    return env;
  }

  @override
  void init() {
    super.init();
    if (File('package.json').existsSync()) {

      final packageFile = jsonDecode(File('package.json').readAsStringSync());
      var dependencies = packageFile['dependencies'];
      if (dependencies != null) {
        if (dependencies['next'] != null) {
          _isNextjs = true;
          imageType = ImageType.nextjs;
        }
      }

    }
  }

  @override
  bool isProject() {
    return _isNextjs;
  }

  // check for stand alone setup
// mjs
//  /** @type {import('next').NextConfig} */
//  const nextConfig = {
//    output: "standalone",
//  };
//  export default nextConfig;

  static ImageDefinition defaultImageDefinition() {
    ImageDefinition definition = NodeProject.defaultImageDefinition();
    definition.expose = ['3000'];
    definition.cmd = ['node','server.js'];
    definition.workdir = '/app';
    definition.env = ['NODE_ENV=production','HOSTNAME=0.0.0.0','NEXT_TELEMETRY_DISABLED=1'];
    definition.label = ['tiecd.image.type=nextjs'];
    definition.copy = ['.next/standalone /app','.next/static /app/.next/static','public /app/public'];
    return definition;
  }

}
