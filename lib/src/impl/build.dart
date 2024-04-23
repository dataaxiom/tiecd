import 'dart:convert';
import 'dart:io';

import 'package:tiecd/src/commands/skopeo.dart';
import 'package:tiecd/src/extensions.dart';

import '../api/types.dart';
import '../commands/umoci.dart';
import '../log.dart';
import '../project/factory.dart';
import '../util.dart';
import '../api/tiefile.dart';
import 'base.dart';
import '../util/image_tag.dart';

class BuildExecutor extends BaseExecutor {
  BuildExecutor(super._config);

  @override
  String getVerb() {
    return 'building';
  }

  void expandApp(App app) {
    app.build ??= Build();
    var build = app.build!;
    // only expand from project if there is one app
    if (projectProvider != null) {
      var project = projectProvider!;
      if (numberOfApps == 1) {
        build.type ??= project.buildType;
        build.beforeScripts ??= project.beforeBuildScripts();
        build.scripts ??= project.buildScripts();
        build.afterScripts ??= project.afterBuildScripts();

        if (app.image != null) {
          app.image!.type ??= project.imageType;
          app.image!.tag ??= projectProvider!.imagePath();
        }
      } else {
        Log.info(
            'multiple apps configured skipping using code project settings');
      }
    }
    // expand off the image type if set
    if (app.image != null &&  app.image!.type != null) {
      // get the image default image definition for that type and
      // merge it into the current image definition
      var defaultDefinition = defaultImageDefinition(app.image!.type!, build.type);
      if (build.imageDefinition == null) {
        build.imageDefinition = defaultDefinition;
      } else if (defaultDefinition != null) {
        if (build.imageDefinition!.from.isNullOrEmpty) {
          build.imageDefinition!.from = defaultDefinition.from;
        }
        if (build.imageDefinition!.workdir.isNullOrEmpty) {
          build.imageDefinition!.workdir = defaultDefinition.workdir;
        }
        if (build.imageDefinition!.author.isNullOrEmpty) {
          build.imageDefinition!.author = defaultDefinition.author;
        }
        if (defaultDefinition.expose != null) {
          if (build.imageDefinition!.expose == null) {
            build.imageDefinition!.expose = defaultDefinition.expose;
          } else {
            build.imageDefinition!.expose = _mergeValues(build.imageDefinition!.expose,defaultDefinition.expose);
          }
        }
        if (defaultDefinition.label != null) {
          if (build.imageDefinition!.label == null) {
            build.imageDefinition!.label = defaultDefinition.label;
          } else {
            build.imageDefinition!.label = _mergeValues(build.imageDefinition!.label, defaultDefinition.label);
          }
        }
        if (defaultDefinition.env != null) {
          if (build.imageDefinition!.env == null) {
            build.imageDefinition!.env = defaultDefinition.env;
          } else {
            build.imageDefinition!.env = _mergeValues(build.imageDefinition!.env!, defaultDefinition.env!);
          }
        }
        if (defaultDefinition.copy != null) {
          if (build.imageDefinition!.copy == null) {
            build.imageDefinition!.copy = defaultDefinition.copy;
          } else {
            build.imageDefinition!.copy = _mergeValues(build.imageDefinition!.copy!, defaultDefinition.copy);
          }
        }
      }
    }
  }

  List<String> _mergeValues(List<String>? first, List<String>? second) {
    // merge the values
    Set<String> values = {};
    if (first != null) {
      for (var element in first) {
        values.add(element);
      }
    }
    if (second != null) {
      for (var element in second) {
        values.add(element);
      }
    }
    return values.toList();
  }

  @override
  execute(Tie tieFile, App app) async {
    List<ImageRegistry> imageReregistries = [];
    if (tieFile.registries != null) {
      imageReregistries = tieFile.registries!;
    }

    if (projectProvider != null) {
      var project = projectProvider!;
      expandApp(app);
      Log.green('build app "${app.name!}"');
      if (config.traceTieFile) {
        Log.printArray(config,'apps', null, app.toJson());
      }
      BuildContext buildContext = BuildContext(config, imageReregistries, app);
      var buildEnv = project.buildEnv();
      buildContext.app.tiecdEnv ??= {};
      buildEnv.forEach((key, value) => buildContext.app.tiecdEnv![key] = value);
      if (app.build != null) {
        if (app.build!.beforeScripts != null) {
          for (var script in app.build!.beforeScripts!) {
            await runScript(buildContext, script);
          }
        }
        if (app.build!.scripts != null) {
          for (var script in app.build!.scripts!) {
            await runScript(buildContext, script);
          }
        }
        if (app.build!.afterScripts != null) {
          for (var script in app.build!.afterScripts!) {
            await runScript(buildContext, script);
          }
        }
      }

      if (app.image != null && app.image!.tag != null && app.build!.imageDefinition != null) {
        Log.info('building app image');
        var umoci = UmociCommand(config);
        var skopeo = SkopeoCommand(config);
        var baseImage = app.build!.imageDefinition!.from!;
        var imageUrl = ImageTag(baseImage);
        var ociPath = imageUrl.path;
        if (ociPath.contains('/')) {
          ociPath = ociPath.substring(ociPath.lastIndexOf('/') + 1);
        }
        try {
          Log.info('pulling image: $baseImage');
          skopeo.initSourceRepo(buildContext.registries, baseImage);
          await skopeo.pullImageForBuild(baseImage);
          await umoci.unpack('$ociPath:${imageUrl.tag}');
          if (app.build!.imageDefinition!.copy != null) {
            for (var artifact in app.build!.imageDefinition!.copy!) {
              List<String> parts = artifact.split(' ');
              if (parts.length == 2) {
                Log.info("copying ${parts[0]} to ${parts[1]}");
                await umoci.copyDirectory(parts[0],parts[1]);
              } else {
                Log.error("copy command doesn't have '<source> <destination>' format: $artifact" );
              }
            }
          }
          await umoci.repack('$ociPath:tiecd');
          List<String> options = [];
          // carry old config to new image
          var config = await skopeo.ociInspect('$ociPath:${imageUrl.tag}');
          if (config.isNotNullNorEmpty) {
            var doc = jsonDecode(config);
            if (doc["config"] != null) {
              var config = doc["config"];
              if (config["ExposedPorts"] != null) {
                Map<String, dynamic> ports = config["ExposedPorts"];
                ports.forEach((key, value) {
                  options.add('--config.exposedports=$key');
                });
              }
              if (config["Env"] != null) {
                for (var env in config["Env"]) {
                  options.add('--config.env=$env');
                }
              }
              if (config["Label"] != null) {
                for (var label in config["Label"]) {
                  options.add('--config.label=$label');
                }
              }
            }
          }
          if (app.build!.imageDefinition!.workdir != null) {
            options.add('--config.workingdir=${app.build!.imageDefinition!.workdir}');
          }
          if (app.build!.imageDefinition!.env != null) {
            for (var env in app.build!.imageDefinition!.env!) {
              options.add('--config.env=$env');
            }
          }
          if (app.build!.imageDefinition!.label != null) {
            for (var label in app.build!.imageDefinition!.label!) {
              options.add('--config.label=$label');
            }
          }
          if (app.build!.imageDefinition!.expose != null) {
            for (var port in app.build!.imageDefinition!.expose!) {
              options.add('--config.exposedports=$port');
            }
          }
          if (app.build!.imageDefinition!.cmd != null) {
            for (var cmd in app.build!.imageDefinition!.cmd!) {
              options.add('--config.cmd=$cmd');
            }
          }
          if (app.build!.imageDefinition!.author != null) {
            options
                .add('--history.author=${app.build!.imageDefinition!.author}');
          }
          await umoci.config('$ociPath:tiecd', [
            ...options,
            '--config.label=tiecd.image.base=$baseImage',
            '--history.comment=TieCD umoci image build',
            '--history.created_by=TieCD',
          ]);

          Log.info("pushing ${app.image!.tag!}");
          skopeo.reset();
          skopeo.initTargetRepo(buildContext.registries,app.image!.tag!);
          await skopeo.pushImageBuild(buildContext, '$ociPath:tiecd',
              app.image!.tag!);
        } catch (error) {
          Log.error("got error building");
          rethrow;
        } finally {
          try {
            Log.info("cleaning up image build");
            await umoci.cleanup('$ociPath:tiecd');
            await umoci.cleanup('$ociPath:${imageUrl.tag}');
            if (Directory(ociPath).existsSync()) {
              Directory(ociPath).deleteSync(recursive: true);
            }
          } catch (error) {
            Log.error("error cleaning up image $error");
          }
        }
      }
    } else {
      Log.info("skipping over app build, unknown project type");
    }
  }
}