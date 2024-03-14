import 'dart:convert';
import 'dart:io';

import '../api/types.dart';
import '../log.dart';

class SkopeoCommand {
  Config _config;

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

  Future<void> pushImage(String srcImage, String destImage) async {
    List<String> args = [];
    args.add('copy');
    var outputString = 'skopeo copy';
    if (srcRepo != null && srcRepo != '') {
      if (destRepo != null && destRepo != '') {
        if (srcUsername != null && srcPassword != null) {
          args.add('--src-creds');
          args.add('$srcUsername:$srcPassword');
          outputString += ' --src-creds ****';
        } else if (srcUsername != null && srcToken != null) {
          args.add('--src-creds');
          args.add('$srcUsername:$srcToken');
          outputString += ' --src-creds ****';
        } else if (srcToken != null) {
          args.add('--src-creds');
          args.add('token:$srcToken');
          outputString += " --src-creds ****";
        }
        if (srcTlsVerify) {
          args.add('--src-tls-verify');
          outputString += ' --src-tls-verify';
        }

        if (destUsername != null && destPassword != null) {
          args.add('--dest-creds');
          args.add('$destUsername:$destPassword');
          outputString += ' --dest-creds ****';
        } else if (destUsername != null && destToken != null) {
          args.add('--dest-creds');
          args.add('$destUsername:$destToken');
          outputString += ' --dest-creds ****';
        } else if (destToken != null) {
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
        process.stdout.transform(utf8.decoder).forEach(print);
        process.stderr.transform(utf8.decoder).forEach(print);
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
    if (srcRepo != null && srcRepo != "") {

      if (srcUsername != null && srcPassword != null) {
        args.add('--creds');
        args.add('$srcUsername:$srcPassword');
        outputString += ' --creds ****';
      } else if (srcUsername != null && srcToken != null) {
        args.add('--creds');
        args.add('$srcUsername:$srcToken');
        outputString += ' --creds ****';
      } else if (srcToken != null) {
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
        process.stdout.transform(utf8.decoder).forEach(print);
        process.stderr.transform(utf8.decoder).forEach(print);
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
}
