import 'dart:convert';
import 'dart:io';

import 'package:tiecd/src/extensions.dart';

import 'api/types.dart';
import 'log.dart';

String varExpandByLine(String value, String fileExtension) {
  return varExpandByLineWithProperties(value, fileExtension, null);
}

Map<String, String> envVars = Platform.environment;

String varExpandByLineWithProperties(
    String value, String fileExtension, Map<String, String>? properties) {
  var regexp = RegExp(
      r'\${([A-Za-z0-9_]+)(?::([^}]*))?}|"\${([A-Za-z0-9_]+)(?::([^}]*))?}"|{{([A-Za-z0-9_]+)(?::([^}]*))?}}|"{{([A-Za-z0-9_]+)(?::([^}]*))?}}"');
  final newString = value.replaceAllMapped(regexp, (Match match) {
    var isQuoted = false;
    var isMultiLine = false;
    var dollarBraceFormat = false;
    var doubleBraceFormat = false;
    String varname = '';
    String? defaultValue;
    if (match.group(1) != null) {
      varname = match.group(1)!;
      defaultValue = match.group(2);
      dollarBraceFormat = true;
    } else if (match.group(3) != null) {
      varname = match.group(3)!;
      defaultValue = match.group(4);
      dollarBraceFormat = true;
      isQuoted = true;
    } else if (match.group(5) != null) {
      varname = match.group(5)!;
      defaultValue = match.group(6);
      doubleBraceFormat = true;
    } else if (match.group(7) != null) {
      varname = match.group(7)!;
      defaultValue = match.group(8);
      doubleBraceFormat = true;
      isQuoted = true;
    }

    String? expanded;
    if (properties != null && properties.containsKey(varname)) {
      expanded = properties[varname];
    }

    // check environment variable is in process environment
    expanded ??= envVars[varname];

    // process multiline support if necessary
    if (expanded != null && expanded.contains('\n')) {
      isMultiLine = true;
      if (fileExtension == "yml" || fileExtension == "yaml") {
        // todo - need to use document indentation size
        var indent = value.indexOf(value.trim()) + 2;
        // indent more if array and first element
        if (value.startsWith("- ")) {
          indent += 2;
        }
        var newValue = '|+\n';
        var lines = expanded.split('\n');
        for (var line in lines) {
          newValue += '${' ' * indent}$line\n';
        }
        expanded = newValue;
      } // todo support xml
    }

    if (expanded == null && defaultValue != null) {
      expanded = defaultValue;
    }

    if (expanded == null) {
      // we haven't found a value, return the original value
      if (dollarBraceFormat) {
        return '\${$varname}';
      } else if (doubleBraceFormat) {
        return '{{$varname}}';
      } else {
        //shouldn't be here
        return varname;
      }
    } else {
      // restore quotes if necessary
      if (isQuoted && !isMultiLine) {
        expanded = '"$expanded"';
      }
    }

    return expanded;
  });

  return newString;
}

String? findNamespace(DeployContext deployContext) {
  var namespace = deployContext.app.deploy!.namespace;
  namespace ??= deployContext.environment.namespace;
  return namespace;
}

String expandFileByContents(String value, String fileExtension) {
  return expandFileByContentsWithProperties(value, fileExtension, null);
}

String expandFileByName(String filename, Map<String, String>? properties) {
  var builder = '';
  var value = File(filename).readAsStringSync();
  var extension = '';
  if (filename.contains('.')) {
    extension = filename.substring(filename.lastIndexOf('.') + 1);
  }
  builder = expandFileByContentsWithProperties(value, extension, properties);
  return builder.toString();
}

String expandFileByContentsWithProperties(
    String value, String fileExtension, Map<String, String>? properties) {
  var builder = '';
  LineSplitter splitter = LineSplitter();
  List<String> lines = splitter.convert(value);
  for (var line in lines) {
    builder +=
        '${varExpandByLineWithProperties(line, fileExtension, properties)}\n';
  }
  return builder;
}

String expandFileByNameWithProperties(
    String filename, Map<String, String>? properties) {
  var builder = '';
  var value = File(filename).readAsStringSync();
  var extension = '';
  if (filename.contains('.')) {
    extension = filename.substring(filename.lastIndexOf('.') + 1);
  }
  builder = expandFileByContentsWithProperties(value, extension, properties);
  return builder;
}

List<String> split(String string, String separator, {int max = 0}) {
  List<String> result = [];

  if (separator.isEmpty) {
    result.add(string);
    return result;
  }

  while (true) {
    var index = string.indexOf(separator, 0);
    if (index == -1 || (max > 0 && result.length >= max)) {
      result.add(string);
      break;
    }

    result.add(string.substring(0, index));
    string = string.substring(index + separator.length);
  }

  return result;
}

bool isPassword(Config config, String value) {
  bool isSecret = false;
  for (var label in config.secretLabelSet) {
    if (value.toLowerCase().contains(label) &&
        !(value.startsWith('\${') && value.endsWith('}'))) {
      isSecret = true;
      break;
    }
  }
  return isSecret;
}

void sanitizeString(
    Config config, String key, String value, Map<String, dynamic> json) {
  bool isSecret = false;
  for (var label in config.secretLabelSet) {
    if ((key == 'apiConfig' || key == 'apiClientCA') &&
        !(value.startsWith('\${') && value.endsWith('}'))) {
      isSecret = true;
      break;
    }
    if (key.toLowerCase().contains(label) &&
        !(value.startsWith('\${') && value.endsWith('}')) &&
        !key.startsWith('TIECD_')) {
      isSecret = true;
      break;
    }
  }
  if (isSecret) {
    json[key] = '(removed)';
  }
}

// walk down the doc and hash any secret values
void sanitizeDoc(Config config, Map<String, dynamic> json) {
  json.forEach((key, value) {
    if (value is Map) {
      sanitizeDoc(config, value as Map<String, dynamic>);
    } else if (value is Iterable) {
      for (var item in value) {
        if (item is String) {
          sanitizeString(config, key, item, json);
        } else if (item is Map) {
          sanitizeDoc(config, item as Map<String, dynamic>);
        } // list?
      }
    } else if (value is String) {
      sanitizeString(config, key, value, json);
    }
  });
}

Future<void> runScript(TieContext tieContext, String script,
    {Map<String, String>? environment}) async {
  if (script.isNullOrEmpty) {
    throw TieError('script can not be empty in app: ${tieContext.app.name}');
  }
  Log.info('running local command: $script');
  var env = Map.of(tieContext.getEnv());
  env.remove('TIECD_APPS');
  env.remove('TIECD_FILES');
  if (environment != null) {
    environment.forEach((key, value) => env[key] = value);
  }
  env['PATH'] = '${env['PATH']}:.'; // linux specific
  var process = await Process.start('/bin/sh', ['-c', script],
      environment: env, workingDirectory: tieContext.config.baseDir);
  process.stdout.transform(utf8.decoder).forEach((line) {
    stdout.write(line);
  });
  process.stderr.transform(utf8.decoder).forEach((line) {
    stdout.write(line);
  });
  if (await process.exitCode != 0) {
    throw TieError('running command: $script');
  }
}

// url could be different formats
// node:20-alpine
// bitnami/postgresql:latest
// registry.gitlab.com/dataaxiom/node:20-alpine
class ImagePath {
  String endpoint = '';
  String path = '';
  String name = '';
  String version = '';
  bool isSha = false;

  ImagePath(String url) {
    List<String> parts = url.split('/');
    if (parts.length > 1) {
      if (parts[0].contains('.')) {
        // we assume first part is hostname
        endpoint = parts[0];
        initVersion(url.substring(endpoint.length + 1));
      } else {
        initVersion(url);
      }
    } else {
      initVersion(url);
    }
  }

  void initVersion(String image) {
    List<String> parts = [];
    if (image.contains('@')) {
      parts = image.split('@');
      isSha = true;
    } else {
      parts = image.split(':');
    }
    if (parts.length == 2) {
      path = parts[0];
      version = parts[1];
    } else {
      path = image;
      version = 'latest';
    }
    if (path.contains('/')) {
      name = path.substring(path.lastIndexOf('/') + 1);
    } else {
      name = path;
    }
  }
}

// Get the home directory or null if unknown.
String? homeDirectory() {
  if (Platform.isMacOS) {
    return envVars['HOME'];
  } else if (Platform.isLinux) {
    return envVars['HOME'];
  } else if (Platform.isWindows) {
    return envVars['UserProfile'];
  } else {
    return null;
  }
}
