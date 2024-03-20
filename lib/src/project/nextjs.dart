import 'dart:convert';
import 'dart:io';

import '../api/provider.dart';
import '../api/types.dart';
import '../commands/umoci.dart';
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

  @override
  void copyArtifactsIntoImage(UmociCommand umoci) async {
    await umoci.copyDirectory('.next/standalone', '/app');
    await umoci.copyDirectory('.next/static', '/app/.next/static');
    await umoci.copyDirectory('public', '/app/public');
  }

  @override
  List<String> getUmociOptions() {
    var options = [
      '--config.workingdir=/app',
      '--config.cmd=node',
      '--config.cmd=server.js',
      '--config.env=NODE_ENV=production',
      '--config.env=HOSTNAME=0.0.0.0',
      '--config.env=NEXT_TELEMETRY_DISABLED=1',
      '--config.exposedports=3000',
      '--config.label=tiecd.image.type=nextjs',
    ];
    return options;
  }


}
