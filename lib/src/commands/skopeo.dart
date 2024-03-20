import 'dart:convert';
import 'dart:io';

import 'package:tiecd/src/api/provider.dart';
import 'package:tiecd/src/extensions.dart';

import '../api/dsl.dart';
import '../api/types.dart';
import '../log.dart';


// url could be different formats
// node:20-alpine
// bitnami/postgresql:latest
// registry.gitlab.com/dataaxiom/node:20-alpine
class ImageUrl {
  String host = '';
  String path = '';
  String version = '';

  ImageUrl(String url) {
    List<String> parts = url.split('/');
    if (parts.length > 1) {
      if (parts[0].contains('.')) {
        // we assume first part is hostname
        host = parts[0];
        initVersion(url.substring(host.length+1));
      } else {
        initVersion(url);
      }
    } else {
      initVersion(url);
    }
  }

  void initVersion(String image) {
    List<String> parts = image.split(':');
    if (parts.length == 2) {
      path = parts[0];
      version = parts[1];
    } else {
      path = image;
      version = 'latest';
    }
  }
}

class SkopeoCommand {
  final Config _config;

  String? srcRepo;
  String? srcUsername;
  String? srcPassword;
  String? srcToken;
  bool srcTlsVerify = true;
  String? destRepo;
  String? destUsername;
  String? destPassword;
  String? destToken;
  bool destTlsVerify = true;

  SkopeoCommand(this._config);

  Future<void> deployImage(String srcImage, String destImage) async {
    List<String> args = [];
    args.add('copy');
    var outputString = 'skopeo copy';
    if (srcRepo.isNotNullNorEmpty) {
      if (destRepo.isNotNullNorEmpty) {
        if (srcUsername.isNotNullNorEmpty && srcPassword.isNotNullNorEmpty) {
          args.add('--src-creds');
          args.add('$srcUsername:$srcPassword');
          outputString += ' --src-creds ****';
        } else if (srcUsername.isNotNullNorEmpty && srcToken.isNotNullNorEmpty) {
          args.add('--src-creds');
          args.add('$srcUsername:$srcToken');
          outputString += ' --src-creds ****';
        } else if (srcToken.isNotNullNorEmpty) {
          args.add('--src-creds');
          args.add('token:$srcToken');
          outputString += " --src-creds ****";
        }
        if (srcTlsVerify) {
          args.add('--src-tls-verify');
          outputString += ' --src-tls-verify';
        }

        if (destUsername.isNotNullNorEmpty && destPassword.isNotNullNorEmpty) {
          args.add('--dest-creds');
          args.add('$destUsername:$destPassword');
          outputString += ' --dest-creds ****';
        } else if (destUsername.isNotNullNorEmpty && destToken.isNotNullNorEmpty) {
          args.add('--dest-creds');
          args.add('$destUsername:$destToken');
          outputString += ' --dest-creds ****';
        } else if (destToken.isNotNullNorEmpty) {
          args.add('--dest-creds');
          args.add('token:$destToken');
          outputString += ' --dest-creds token:$destToken';
        }
        if (destTlsVerify) {
          args.add('--dest-tls-verify');
          outputString += ' --dest-tls-verify';
        }

        // strip srcRepo if the image name is in it already
        srcRepo = sanitizeRepo(srcRepo!);
        destRepo = sanitizeRepo(destRepo!);

        // strip duplicate parts (gitlab contains group/project name in repo)
        var projectName = srcImage.substring(0, srcImage.indexOf(":"));
        if (projectName.contains("/")) {
          projectName = projectName.substring(0, projectName.lastIndexOf("/"));
        }
        if (srcRepo!.endsWith(projectName)) {
          srcRepo =
              srcRepo!.substring(0, srcRepo!.lastIndexOf(projectName) - 1);
        }

        args.add('docker://$srcRepo/$srcImage');
        outputString += ' docker://$srcRepo/$srcImage';
        args.add('docker://$destRepo/$destImage');
        outputString += ' docker://$destRepo/$destImage';

        if (_config.traceCommands) {
          Log.info(outputString);
        }

        var process = await Process.start('skopeo', args, runInShell: true);
        process.stdout.transform(utf8.decoder).forEach((line) {stdout.write(line);});
        process.stderr.transform(utf8.decoder).forEach((line) {stdout.write(line);});
        if (await process.exitCode != 0) {
          throw TieError('copying image $srcImage to $destImage');
        }
      } else {
        throw TieError('destRepo can\'t be empty');
      }
    } else {
      throw TieError('srcRepo can\'t be empty');
    }
  }

  String sanitizeRepo(String url) {
    var value = url.replaceFirst('https://', '');
    value = value.replaceFirst('http://', '');
    if (value.endsWith('/')) {
      value = value.substring(0, value.length);
    }
    return value;
  }

  Future<String> imageSha(String srcImage) async {
    var sha = '';
    List<String> args = [];
    args.add('inspect');
    var outputString = 'skopeo inspect';
    if (srcRepo.isNotNullNorEmpty) {
      if (srcUsername.isNotNullNorEmpty && srcPassword.isNotNullNorEmpty) {
        args.add('--creds');
        args.add('$srcUsername:$srcPassword');
        outputString += ' --creds ****';
      } else if (srcUsername.isNotNullNorEmpty && srcToken.isNotNullNorEmpty) {
        args.add('--creds');
        args.add('$srcUsername:$srcToken');
        outputString += ' --creds ****';
      } else if (srcToken.isNotNullNorEmpty) {
        args.add('--creds');
        args.add('token:$srcToken');
        outputString += " --creds ****";
      }

      if (srcTlsVerify) {
        args.add('--tls-verify');
        outputString += ' --tls-verify';
      }

      args.add('--format');
      args.add('{{.Digest}}');
      outputString += ' --format {{.Digest}}';

      // strip srcRepo if the image name is in it already
      srcRepo = sanitizeRepo(srcRepo!);

      // strip duplicate parts (gitlab contains group/project name in repo)
      var projectName = srcImage.substring(0, srcImage.indexOf(':'));
      if (projectName.contains('/')) {
        projectName = projectName.substring(0, projectName.lastIndexOf('/'));
      }
      if (srcRepo!.endsWith(projectName)) {
        srcRepo = srcRepo!.substring(0, srcRepo!.lastIndexOf(projectName) - 1);
      }

      args.add('docker://$srcRepo/$srcImage');
      outputString += ' docker://$srcRepo/$srcImage';

      if (_config.traceCommands) {
        Log.info(outputString);
      }

      var process = await Process.start('skopeo', args, runInShell: true);
      if (await process.exitCode != 0) {
        process.stdout.transform(utf8.decoder).forEach((line) {stdout.write(line);});
        process.stderr.transform(utf8.decoder).forEach((line) {stdout.write(line);});
        throw TieError('skopeo inspect image $srcImage failed');
      } else {
        sha = await process.stdout.transform(utf8.decoder).join();
        sha = sha.replaceAll('\n', '');
      }
    } else {
      throw TieError('srcRepo can\'t be empty');
    }
    return sha;
  }

  // used to pull images for building  - saves locally as oci image
  Future<void> pullImageForBuild(TieContext tieContext, String image) async {
    try {

      List<String> args = ['copy',];
      var outputString = 'skopeo copy';

      // does image have repo port
      var imageUrl = ImageUrl(image);
      if (imageUrl.host.isNotNullNorEmpty) {
        // assume we have registry part so check if we have one setup for auth
        ImageRepository imageRepository;
        for (var repo in tieContext.repositories) {
          if (imageUrl.host == repo.url) {
            srcRepo = repo.url;
            srcUsername = repo.username;
            srcPassword = repo.password;
            srcToken = repo.token;
            if (repo.tlsVerify != null) {
              srcTlsVerify = repo.tlsVerify!;
            }

            if (srcUsername.isNotNullNorEmpty && srcPassword.isNotNullNorEmpty) {
              args.add('--src-creds');
              args.add('$srcUsername:$srcPassword');
              outputString += ' --src-creds ****';
            } else if (srcUsername.isNotNullNorEmpty && srcToken.isNotNullNorEmpty) {
              args.add('--src-creds');
              args.add('$srcUsername:$srcToken');
              outputString += ' --src-creds ****';
            } else if (srcToken.isNotNullNorEmpty) {
              args.add('--src-creds');
              args.add('token:$srcToken');
              outputString += ' --src-creds token:$srcToken';
            }
            if (srcTlsVerify) {
              args.add('--src-tls-verify');
              outputString += ' --src-tls-verify';
            }
          }
        }
      }
      args.add('docker://$image');
      outputString += ' docker://$image';
      var strippedPath = imageUrl.path;
      if (strippedPath.contains('/')) {
        strippedPath = strippedPath.substring(strippedPath.lastIndexOf('/')+1);
      }
      args.add('oci:$strippedPath:${imageUrl.version}');
      outputString += ' oci:$strippedPath:${imageUrl.version}';

      if (_config.traceCommands) {
        Log.info(outputString);
      }
      var process = await Process.start('skopeo', args, runInShell: true);
      process.stdout.transform(utf8.decoder).forEach((line) {stdout.write(line);});
      process.stderr.transform(utf8.decoder).forEach((line) {stdout.write(line);});
      if (await process.exitCode != 0) {
        throw TieError("copying image: $image");
      }
    } catch (error) {
      rethrow;
    }
  }

  Future<void> pushImageBuild(TieContext tieContext, String srcImage, String destImage) async {
    try {

      List<String> args = ['copy'];
      var outputString = 'skopeo copy';

      // does image have repo port
      var imageUrl = ImageUrl(destImage);
      if (imageUrl.host.isNotNullNorEmpty) {
        // assume we have registry part so check if we have one setup for auth
        ImageRepository imageRepository;
        for (var repo in tieContext.repositories) {
          if (imageUrl.host == repo.url) {
            destRepo = repo.url;
            destUsername = repo.username;
            destPassword = repo.password;
            destToken = repo.token;
            if (repo.tlsVerify != null) {
              destTlsVerify = repo.tlsVerify!;
            }

            if (destUsername.isNotNullNorEmpty && destPassword.isNotNullNorEmpty) {
              args.add('--dest-creds');
              args.add('$destUsername:$destPassword');
              outputString += ' --dest-creds ****';
            } else if (destUsername.isNotNullNorEmpty && destToken.isNotNullNorEmpty) {
              args.add('--dest-creds');
              args.add('$destUsername:$destToken');
              outputString += ' --dest-creds ****';
            } else if (destToken.isNotNullNorEmpty) {
              args.add('--dest-creds');
              args.add('token:$destToken');
              outputString += ' --dest-creds token:$destToken';
            }
            if (destTlsVerify) {
              args.add('--dest-tls-verify');
              outputString += ' --dest-tls-verify';
            }
          }
        }
      }

      args.add('oci:$srcImage');
      outputString += ' oci:$srcImage';
      args.add('docker://$destImage');
      outputString += ' docker://$destImage';

      if (_config.traceCommands) {
        Log.info(outputString);
      }
      var process = await Process.start('skopeo', args, runInShell: true);
      process.stdout.transform(utf8.decoder).forEach((line) {stdout.write(line);});
      process.stderr.transform(utf8.decoder).forEach((line) {stdout.write(line);});
      if (await process.exitCode != 0) {
        throw TieError("copying image: $srcImage");
      }
    } catch (error) {
      rethrow;
    }
  }

  Future<String> ociInspect(String srcImage) async {
    var output = '';
    List<String> args = [];
    args.add('inspect');
    args.add('--config');
    var outputString = 'skopeo inspect --config';

      args.add('oci:$srcImage');
      outputString += ' oci:$srcImage';

      if (_config.traceCommands) {
        Log.info(outputString);
      }

      var process = await Process.start('skopeo', args, runInShell: true);
      if (await process.exitCode != 0) {
        process.stdout.transform(utf8.decoder).forEach((line) {stdout.write(line);});
        process.stderr.transform(utf8.decoder).forEach((line) {stdout.write(line);});
        throw TieError('skopeo inspect image $srcImage failed');
      } else {
        output = await process.stdout.transform(utf8.decoder).join();
        output = output.replaceAll('\n', '');
      }

    return output;
  }

}
