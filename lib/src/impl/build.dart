import 'dart:convert';
import 'dart:io';

import 'package:tiecd/src/api/provider.dart';
import 'package:tiecd/src/commands/skopeo.dart';
import 'package:tiecd/src/extensions.dart';

import '../commands/umoci.dart';
import '../log.dart';
import '../project/factory.dart';
import '../util.dart';
import 'base.dart';
import '../api/dsl.dart';

class BuildExecutor extends BaseExecutor {
  BuildExecutor(super._config);

  @override
  String getVerb() {
    return 'building';
  }

  void expandApp(ProjectProvider project,App app) {
    app.build ??= Build();
    var build = app.build!;

    build.buildType ??= project.buildType;
    build.beforeScripts ??= project.beforeBuildScripts();
    build.scripts ??= project.buildScripts();
    build.afterScripts ??= project.afterBuildScripts();

    build.imageDefinition ??= ImageDefinition();

    if (build.imageDefinition!.baseImage.isNullOrEmpty) {
      build.imageDefinition!.baseImage = project.getBaseImage();
    }
  }

  @override
  execute(Tie tieFile, App app) async {
    List<ImageRepository> imageRepositories = [];
    if (tieFile.repositories != null && tieFile.repositories!.image != null) {
      imageRepositories = tieFile.repositories!.image!;
    }

    var project = buildProject();

    if (project != null) {

      expandApp(project, app);

      Log.green('build app "${app.name!}"');

      if (config.traceTieFile) {
        printObject('app', null, app.toJson());
      }

      BuildContext buildContext =
      BuildContext(config, imageRepositories, project, app);

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

      var umoci = UmociCommand(config);
      var skopeo = SkopeoCommand(config);
      var baseImage = app.build!.imageDefinition!.baseImage!;
      var imageUrl = ImageUrl(baseImage);
      var ociPath = imageUrl.path;
      if (ociPath.contains('/')) {
        ociPath = ociPath.substring(ociPath.lastIndexOf('/')+1);
      }

      try {
        Log.info('pulling image: $baseImage');
        await skopeo.pullImageForBuild(buildContext, baseImage);
        Log.info('building app image');
        await umoci.unpack('$ociPath:${imageUrl.version}');
        project.copyArtifactsIntoImage(umoci);
        await umoci.repack('$ociPath:tiecd');
        List<String> options = project.getUmociOptions();

        // carry old config to new image
        var config = await skopeo.ociInspect('$ociPath:${imageUrl.version}');
        if (config.isNotNullNorEmpty) {
          var doc = jsonDecode(config);
          if (doc["config"] != null ) {
            var config = doc["config"];
            if (config["ExposedPorts"] != null) {
              Map<String,dynamic> ports = config["ExposedPorts"];
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
          options.add('--history.author=${app.build!.imageDefinition!.author}');
        }
        await umoci.config('$ociPath:tiecd', [
          ...options,
          '--config.label=tiecd.image.base=$baseImage',
          '--history.comment=TieCD Umoci Image Build',
          '--history.created_by=TieCD',

        ]);

        Log.info("pushing image to repo");
        await skopeo.pushImageBuild(buildContext, '$ociPath:tiecd',
            'registry.gitlab.com/x-images/keycloak:node');
      } catch (error) {
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
    } else {
      Log.info("skipping over app build, unknown project type");
    }
  }
}
