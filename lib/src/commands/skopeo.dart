import 'dart:convert';
import 'dart:io';

import '../extensions.dart';
import '../api/tiefile.dart';
import '../api/types.dart';
import '../log.dart';
import '../util/image_tag.dart';

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

  void initSourceRepo(List<ImageRegistry>? imageRegistries, String srcImage) {
    // check if there is a repository matching the host - setup the auth
    if (imageRegistries != null) {
      ImageRegistry? imageRegistry;
      if (srcImage.isNotNullNorEmpty) {
        ImageTag imageTag = ImageTag(srcImage);
        for (var registry in imageRegistries) {
          if (imageTag.host == registry.host) {
            imageRegistry = registry;
            break;
          }
        }
      }
      if (imageRegistry != null) {
        if (imageRegistry.username.isNotNullNorEmpty) {
          sourceUsername = imageRegistry.username!;
        }
        if (imageRegistry.password != null) {
          sourcePassword = imageRegistry.password!;
        } else if (imageRegistry.token.isNotNullNorEmpty) {
          sourceToken = imageRegistry.token!;
        }
        if (imageRegistry.tlsVerify != null) {
          sourceTlsVerify = imageRegistry.tlsVerify!;
        }
      }
    }
  }

  void initTargetRepo(List<ImageRegistry>? imageRegistries, String targetImage) {
    if (imageRegistries != null) {
      ImageRegistry? imageRegistry;
      if (targetImage.isNotNullNorEmpty) {
        ImageTag imageTag = ImageTag(targetImage);
        for (var registry in imageRegistries) {
          if (imageTag.host == registry.host) {
            imageRegistry = registry;
            break;
          }
        }
      }
      if (imageRegistry != null) {
        setTargetRepo(imageRegistry);
      }
    }
  }

  void setTargetRepo(ImageRegistry? imageRegistry) {
    if (imageRegistry != null) {
      if (imageRegistry.username.isNotNullNorEmpty) {
        destinationUsername = imageRegistry.username!;
      }
      if (imageRegistry.password.isNotNullNorEmpty) {
        destinationPassword = imageRegistry.password!;
      }
      if (imageRegistry.token.isNotNullNorEmpty) {
        destinationToken = imageRegistry.token!;
      }
      if (imageRegistry.tlsVerify != null) {
        destinationTlsVerify = imageRegistry.tlsVerify!;
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
      var imageTag = ImageTag(sourceImage);
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
      args.add('oci:${imageTag.name}:${imageTag.tag}');
      outputString += ' oci:${imageTag.name}:${imageTag.tag}';

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
      ImageTag imageTag = ImageTag(destinationImage);
      if (imageTag.tag == '') {
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
