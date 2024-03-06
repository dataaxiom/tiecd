import 'dart:convert';
import 'dart:io';

import 'package:tiecd/src/extensions.dart';

import '../api/tiefile.dart';
import '../api/types.dart';
import '../log.dart';
import '../util.dart';

class SkopeoCommand {
  final Config _config;

  String? sourceUsername;
  String? sourcePassword;
  String? sourceToken;
  bool? sourceTlsVerify;
  String? destinationUsername;
  String? destinationPassword;
  String? destinationToken;
  bool? destinationTlsVerify;

  SkopeoCommand(this._config);

  void reset() {
    sourceUsername = null;
    sourcePassword = null;
    sourceToken = null;
    sourceTlsVerify = null;
    destinationUsername = null;
    destinationPassword = null;
    destinationToken = null;
    destinationTlsVerify = null;
  }

  void initSourceRepo(List<ImageRepository>? imageRepositories, String image) {
    // check if there is a repository matching the host - setup the auth
    if (imageRepositories != null) {
      ImageRepository? imageRepository;
      if (image.isNotNullNorEmpty) {
        ImagePath imagePath = ImagePath(image);
        for (var registry in imageRepositories) {
          if (imagePath.endpoint == registry.endpoint) {
            imageRepository = registry;
            break;
          }
        }
      }
      if (imageRepository != null) {
        if (imageRepository.username.isNotNullNorEmpty) {
          sourceUsername = imageRepository.username!;
        }
        if (imageRepository.password != null) {
          sourcePassword = imageRepository.password!;
        } else if (imageRepository.token.isNotNullNorEmpty) {
          sourceToken = imageRepository.token!;
        }
        if (imageRepository.tlsVerify != null) {
          sourceTlsVerify = imageRepository.tlsVerify!;
        }
      }
    }
  }

  void initTargetRepo(List<ImageRepository>? imageRepositories, String image) {
    if (imageRepositories != null) {
      ImageRepository? imageRepository;
      if (image.isNotNullNorEmpty) {
        ImagePath imagePath = ImagePath(image);
        for (var registry in imageRepositories) {
          if (imagePath.endpoint == registry.endpoint) {
            imageRepository = registry;
            break;
          }
        }
      }
      if (imageRepository != null) {
        setTargetRepo(imageRepository);
      }
    }
  }

  void setTargetRepo(ImageRepository? imageRepository) {
    if (imageRepository != null) {
      if (imageRepository.username.isNotNullNorEmpty) {
        destinationUsername = imageRepository.username!;
      }
      if (imageRepository.password.isNotNullNorEmpty) {
        destinationPassword = imageRepository.password!;
      }
      if (imageRepository.token.isNotNullNorEmpty) {
        destinationToken = imageRepository.token!;
      }
      if (imageRepository.tlsVerify != null) {
        destinationTlsVerify = imageRepository.tlsVerify!;
      }
    }
  }

  Future<void> deployImage(String sourceImage, String destinationImage) async {
    List<String> args = [];
    args.add('copy');
    var outputString = 'skopeo copy';

    if (sourceUsername.isNotNullNorEmpty && sourcePassword.isNotNullNorEmpty) {
      args.add('--src-creds');
      args.add('$sourceUsername:$sourcePassword');
      outputString += ' --src-creds ****';
    } else if (sourceUsername.isNotNullNorEmpty &&
        sourceToken.isNotNullNorEmpty) {
      args.add('--src-creds');
      args.add('$sourceUsername:$sourceToken');
      outputString += ' --src-creds ****';
    } else if (sourceToken.isNotNullNorEmpty) {
      args.add('--src-creds');
      args.add('token:$sourceToken');
      outputString += " --src-creds ****";
    }
    if (sourceTlsVerify != null && sourceTlsVerify!) {
      args.add('--src-tls-verify');
      outputString += ' --src-tls-verify';
    }

    if (destinationUsername.isNotNullNorEmpty &&
        destinationPassword.isNotNullNorEmpty) {
      args.add('--dest-creds');
      args.add('$destinationUsername:$destinationPassword');
      outputString += ' --dest-creds ****';
    } else if (destinationUsername.isNotNullNorEmpty &&
        destinationToken.isNotNullNorEmpty) {
      args.add('--dest-creds');
      args.add('$destinationUsername:$destinationToken');
      outputString += ' --dest-creds ****';
    } else if (destinationToken.isNotNullNorEmpty) {
      args.add('--dest-creds');
      args.add('token:$destinationToken');
      outputString += ' --dest-creds token:$destinationToken';
    }
    if (destinationTlsVerify != null && destinationTlsVerify == true) {
      args.add('--dest-tls-verify');
      outputString += ' --dest-tls-verify';
    }

    args.add('docker://$sourceImage');
    outputString += ' docker://$sourceImage';
    args.add('docker://$destinationImage');
    outputString += ' docker://$destinationImage';

    if (_config.traceCommands) {
      Log.info(outputString);
    }

    var process = await Process.start('skopeo', args, runInShell: true);
    process.stdout.transform(utf8.decoder).forEach((line) {
      stdout.write(line);
    });
    process.stderr.transform(utf8.decoder).forEach((line) {
      stdout.write(line);
    });
    if (await process.exitCode != 0) {
      throw TieError('copying image $sourceImage to $destinationImage');
    }
  }

  Future<String> imageSha(String sourceImage) async {
    var sha = '';
    List<String> args = [];
    args.add('inspect');
    var outputString = 'skopeo inspect';

    if (sourceUsername.isNotNullNorEmpty && sourcePassword.isNotNullNorEmpty) {
      args.add('--creds');
      args.add('$sourceUsername:$sourcePassword');
      outputString += ' --creds ****';
    } else if (sourceUsername.isNotNullNorEmpty &&
        sourceToken.isNotNullNorEmpty) {
      args.add('--creds');
      args.add('$sourceUsername:$sourceToken');
      outputString += ' --creds ****';
    } else if (sourceToken.isNotNullNorEmpty) {
      args.add('--creds');
      args.add('token:$sourceToken');
      outputString += " --creds ****";
    }

    if (sourceTlsVerify != null && sourceTlsVerify!) {
      args.add('--tls-verify');
      outputString += ' --tls-verify';
    }

    args.add('--format');
    args.add('{{.Digest}}');
    outputString += ' --format {{.Digest}}';

    args.add('docker://$sourceImage');
    outputString += ' docker://$sourceImage';

    if (_config.traceCommands) {
      Log.info(outputString);
    }

    var process = await Process.start('skopeo', args, runInShell: true);
    if (await process.exitCode != 0) {
      process.stdout.transform(utf8.decoder).forEach((line) {
        stdout.write(line);
      });
      process.stderr.transform(utf8.decoder).forEach((line) {
        stdout.write(line);
      });
      throw TieError('skopeo inspect image $sourceImage failed');
    } else {
      sha = await process.stdout.transform(utf8.decoder).join();
      sha = sha.replaceAll('\n', '');
    }

    return sha;
  }

  // used to pull images for building  - saves locally as oci image
  Future<void> pullImageForBuild(String sourceImage) async {
    try {
      List<String> args = [
        'copy',
      ];
      var outputString = 'skopeo copy';
      var imageUrl = ImagePath(sourceImage);
      if (sourceUsername.isNotNullNorEmpty &&
          sourcePassword.isNotNullNorEmpty) {
        args.add('--src-creds');
        args.add('$sourceUsername:$sourcePassword');
        outputString += ' --src-creds ****';
      } else if (sourceUsername.isNotNullNorEmpty &&
          sourceToken.isNotNullNorEmpty) {
        args.add('--src-creds');
        args.add('$sourceUsername:$sourceToken');
        outputString += ' --src-creds ****';
      } else if (sourceToken.isNotNullNorEmpty) {
        args.add('--src-creds');
        args.add('token:$sourceToken');
        outputString += ' --src-creds token:$sourceToken';
      }
      if (sourceTlsVerify != null && sourceTlsVerify!) {
        args.add('--src-tls-verify');
        outputString += ' --src-tls-verify';
      }
      args.add('docker://$sourceImage');
      outputString += ' docker://$sourceImage';
      // just use last part of multi path for oci image name
      var strippedPath = imageUrl.path;
      if (strippedPath.contains('/')) {
        strippedPath =
            strippedPath.substring(strippedPath.lastIndexOf('/') + 1);
      }
      args.add('oci:$strippedPath:${imageUrl.version}');
      outputString += ' oci:$strippedPath:${imageUrl.version}';

      if (_config.traceCommands) {
        Log.info(outputString);
      }
      var process = await Process.start('skopeo', args, runInShell: true);
      process.stdout.transform(utf8.decoder).forEach((line) {
        stdout.write(line);
      });
      process.stderr.transform(utf8.decoder).forEach((line) {
        stdout.write(line);
      });
      if (await process.exitCode != 0) {
        throw TieError("copying image: $sourceImage");
      }
    } catch (error) {
      rethrow;
    }
  }

  Future<void> pushImageBuild(TieContext tieContext, String sourceImage,
      String destinationImage) async {
    try {
      List<String> args = ['copy'];
      var outputString = 'skopeo copy';
      // does image have repo port

      if (destinationUsername.isNotNullNorEmpty &&
          destinationPassword.isNotNullNorEmpty) {
        args.add('--dest-creds');
        args.add('$destinationUsername:$destinationPassword');
        outputString += ' --dest-creds ****';
      } else if (destinationUsername.isNotNullNorEmpty &&
          destinationToken.isNotNullNorEmpty) {
        args.add('--dest-creds');
        args.add('$destinationUsername:$destinationToken');
        outputString += ' --dest-creds ****';
      } else if (destinationToken.isNotNullNorEmpty) {
        args.add('--dest-creds');
        args.add('token:$destinationToken');
        outputString += ' --dest-creds token:$destinationToken';
      }
      if (destinationTlsVerify != null && sourceTlsVerify!) {
        args.add('--dest-tls-verify');
        outputString += ' --dest-tls-verify';
      }

      String image = destinationImage;
      ImagePath imagePath = ImagePath(destinationImage);
      if (imagePath.version == '') {
        image = '$destinationImage:latest';
      }
      args.add('oci:$sourceImage');
      outputString += ' oci:$sourceImage';
      args.add('docker://$image');
      outputString += ' docker://$image';

      if (_config.traceCommands) {
        Log.info(outputString);
      }
      var process = await Process.start('skopeo', args, runInShell: true);
      process.stdout.transform(utf8.decoder).forEach((line) {
        stdout.write(line);
      });
      process.stderr.transform(utf8.decoder).forEach((line) {
        stdout.write(line);
      });
      if (await process.exitCode != 0) {
        throw TieError("copying image: $sourceImage");
      }
    } catch (error) {
      rethrow;
    }
  }

  Future<String> ociInspect(String sourceImage) async {
    var output = '';
    List<String> args = [];
    args.add('inspect');
    args.add('--config');
    var outputString = 'skopeo inspect --config';

    args.add('oci:$sourceImage');
    outputString += ' oci:$sourceImage';

    if (_config.traceCommands) {
      Log.info(outputString);
    }

    var process = await Process.start('skopeo', args, runInShell: true);
    if (await process.exitCode != 0) {
      process.stdout.transform(utf8.decoder).forEach((line) {
        stdout.write(line);
      });
      process.stderr.transform(utf8.decoder).forEach((line) {
        stdout.write(line);
      });
      throw TieError('skopeo inspect image $sourceImage failed');
    } else {
      output = await process.stdout.transform(utf8.decoder).join();
      output = output.replaceAll('\n', '');
    }

    return output;
  }
}
