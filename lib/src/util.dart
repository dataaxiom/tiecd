import 'dart:convert';
import 'dart:io';

import 'api/provider.dart';
import 'api/types.dart';

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

String findNamespace(TieContext tieContext) {
  var namespace = tieContext.app.deploy!.namespace;
  namespace ??= tieContext.environment.namespace;
  namespace ??= 'default';
  return namespace;
}

String expandFileByContents(String value, String fileExtension) {
  return expandFileByContentsWithProperties(value, fileExtension, null);
}

String expandFileByName(String filename) {
  var builder = '';
  var value = File(filename).readAsStringSync();
  var extension = '';
  if (filename.contains('.')) {
    extension = filename.substring(filename.lastIndexOf('.') + 1);
  }
  builder = expandFileByContentsWithProperties(value, extension, null);
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

bool isPassword(String value) {
  var lower = value.toLowerCase();
  if (lower.contains('pass') ||
      lower.contains('secret') ||
      lower.contains('pwd') ||
      lower.contains('token') ||
      lower.contains('enc(')) {
    return true;
  } else {
    return false;
  }
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

void sanitizeString(Config config, String key, String value, Map<String, dynamic> json) {
  bool isSecret = false;
  for (var label in config.secretLabelSet) {
    if ((key == 'apiConfig' || key == 'apiClientCA') &&
        !(value.startsWith('\${') && value.endsWith('}'))) {
      isSecret = true;
      break;
    }
    if (key.toLowerCase().contains(label) &&
        !(value.startsWith('\${') && value.endsWith('}'))) {
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
          sanitizeString(config,key,item,json);
        } else if (item is Map) {
          sanitizeDoc(config, item as Map<String, dynamic>);
        } // list?
      }
    } else if (value is String) {
      sanitizeString(config,key,value,json);
    }
  });
}
