import 'dart:convert';
import 'dart:io';

import 'package:tiecd/src/api/provider.dart';
import 'package:tiecd/src/commands/skopeo.dart';
import 'package:tiecd/src/extensions.dart';

import '../commands/umoci.dart';
import '../log.dart';
import '../project/factory.dart';
import '../util.dart';
import '../api/dsl.dart';
import 'base.dart';

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
        build.buildType ??= project.buildType;
        build.beforeScripts ??= project.beforeBuildScripts();
        build.scripts ??= project.buildScripts();
        build.afterScripts ??= project.afterBuildScripts();

        if (app.image != null) {
          // expand path if null

          if (app.image!.path.isNullOrEmpty) {
            app.image!.path = projectProvider!.getImagePath();
          }
          build.imageDefinition ??= ImageDefinition();

          if (build.imageDefinition!.from.isNullOrEmpty) {
            build.imageDefinition!.from = project.getBaseImage();
          }
        }
      } else {
        Log.info(
            'multiple apps configured skipping using code project settings');
      }
    }
  }

  @override
  execute(Tie tieFile, App app) async {
    List<ImageRepository> imageRepositories = [];
    if (tieFile.repositories != null && tieFile.repositories!.image != null) {
      imageRepositories = tieFile.repositories!.image!;
    }


    if (projectProvider != null) {

      var project = projectProvider!;

      expandApp(app);

      Log.green('build app "${app.name!}"');

      if (config.traceTieFile) {
        printArray('apps', null, app.toJson());
      }

      BuildContext buildContext = BuildContext(config, imageRepositories, app);

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

      if (app.image != null && app.image!.path != null && app.build!.imageDefinition != null) {
        Log.info('building app image');

        var umoci = UmociCommand(config);
        var skopeo = SkopeoCommand(config);
        var baseImage = app.build!.imageDefinition!.from!;
        var imageUrl = ImagePath(baseImage);
        var ociPath = imageUrl.path;
        if (ociPath.contains('/')) {
          ociPath = ociPath.substring(ociPath.lastIndexOf('/') + 1);
        }

        try {
          Log.info('pulling image: $baseImage');
          skopeo.initSourceRepo(buildContext.repositories, baseImage);
          await skopeo.pullImageForBuild(baseImage);

          await umoci.unpack('$ociPath:${imageUrl.version}');
          project.copyArtifactsIntoImage(umoci);
          await umoci.repack('$ociPath:tiecd');
          List<String> options = project.getUmociOptions();

          // carry old config to new image
          var config = await skopeo.ociInspect('$ociPath:${imageUrl.version}');
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

          if (app.build!.imageDefinition!.ports != null) {
            for (var port in app.build!.imageDefinition!.ports!) {
              options.add('--config.exposedports=$port');
            }
          }
          if (app.build!.imageDefinition!.author != null) {
            options
                .add('--history.author=${app.build!.imageDefinition!.author}');
          }
          await umoci.config('$ociPath:tiecd', [
            ...options,
            '--config.label=tiecd.image.base=$baseImage',
            '--history.comment=TieCD Umoci Image Build',
            '--history.created_by=TieCD',
          ]);

          Log.info("pushing image to repo");
          skopeo.reset();
          skopeo.initTargetRepo(buildContext.repositories,app.image!.path!);
          await skopeo.pushImageBuild(buildContext, '$ociPath:tiecd',
              app.image!.path!);
        } catch (error) {
          Log.error("got error building");
          rethrow;
        } finally {
          try {
            Log.info("cleaning up image build");
            await umoci.cleanup('$ociPath:tiecd');
            await umoci.cleanup('$ociPath:${imageUrl.version}');
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
