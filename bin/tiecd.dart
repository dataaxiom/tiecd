import 'dart:io';

import 'package:args/args.dart';
import 'package:args/command_runner.dart';
import 'package:tiecd/src/api/types.dart';
import 'package:tiecd/src/impl/deploy.dart';
import 'package:tiecd/src/log.dart';

Map<String, String> envVars = Platform.environment;

String setupStringValue(String? newValue, String? envName) {
  return setupStringValueWithDefault('',newValue,envName);
}
String setupStringValueWithDefault(String? defaultValue, String? newValue, String? envName) {
  if (newValue != null) {
    if (newValue.startsWith('=')) {
      newValue = newValue.substring(1);
    }
  }
  if (envName != null) {
    if (envVars[envName] != null) {
      return envVars[envName]!;
    } else if (envVars['INPUT_$envName'] != null) {
      // github actions
      return envVars['INPUT_$envName']!;
    }
  }
  if (newValue != null) {
    return newValue;
  } else if (defaultValue != null) {
    return defaultValue;
  } else {
    return '';
  }
}

bool setupBoolValue(bool value, String? envName) {
  bool? envResult;
  if (envName != null) {
    if (envVars[envName] != null) {
      envResult = bool.tryParse(envVars[envName]!, caseSensitive: false);
    } else if (envVars['INPUT_$envName'] != null) {
      // github actions
      envResult =
          bool.tryParse(envVars['INPUT_$envName']!, caseSensitive: false);
    }
  }
  if (envResult != null) {
    return envResult;
  } else {
    return value;
  }
}

Future<void> processGitLog(Config config) async {
  // is this a git repository?
  if (File('.git/config').existsSync()) {

    // set safe directory to workspace for github runners
    if (envVars['GITHUB_WORKSPACE'] != null) {
      var result = await Process.run('ls', ['config','--global','safe.directory',envVars['GITHUB_WORKSPACE']!]);
    }

    // check the the HEAD commit message for steps/files overrides
    var buffer = await Process.run('git', ['log','-1','--pretty=%B']);
    var lines = buffer.stdout.split('/\r?\n/');

    // process files
    if (config.files == '') {

      var files = config.filesCommitPrefix.split('|');
      var regex = '';
      for (var file in files) {
        regex += '$file=|';
      }
      regex = regex.substring(0, regex.length - 1);
      RegExp separator = RegExp(regex);

      for (var line in lines) {
        var parts = line.replaceAll('\n','').split(separator);
        if (parts.length == 2) {
          if (parts[1].contains(' ')) {
            config.files = parts[1].substring(0,parts[1].indexOf(' ')).replaceAll('\n','');
          } else {
            config.files = parts[1].replaceAll('\n','');
          }
          break; // ignore other lines
        } else if (parts.length > 2) {
          print('more then one files= option is specified in commit message');
          exit(1);
        }
      }
    }

    // process app
    if (config.apps == '') {

      var steps = config.appsCommitPrefix.split('|');
      var regex = '';
      for (var step in steps) {
        regex += '$step=|';
      }
      regex = regex.substring(0, regex.length - 1);
      RegExp separator = RegExp(regex);

      for (var line in lines) {
         var parts = line.split(separator);
        if (parts.length == 2) {
          // only take value up to first space
          if (parts[1].contains(' ')) {
              config.apps = parts[1].substring(0,parts[1].indexOf(' ')).replaceAll('\n','');
          } else {
            config.apps = parts[1].replaceAll('\n','');
          }
          break; // ignore other lines
        } else if (parts.length > 2) {
          print('more then one apps= option is specified in commit message');
          exit(1);
        }
      }
    }
  }
}

void showHeader(Config config) {
  if (config.banner) {
    print(' ');
    print('  ████████╗ ██╗ ███████╗  ██████╗ ██████╗ ');
    print('  ╚══██╔══╝ ╚═╝ ██╔════╝ ██╔════╝ ██╔══██╗');
    print('     ██║    ██╗ █████╗   ██║      ██║  ██║');
    print('     ██║    ██║ ██╔══╝   ██║      ██║  ██║');
    print('     ██║    ██║ ███████╗ ╚██████╗ ██████╔╝');
    print('     ╚═╝    ╚═╝ ╚══════╝  ╚═════╝ ╚═════╝ ');
    print(' ');
    print('      https://dataaxiom.com/tiecd');
    print(' ');
  }
  if (config.verbose) {
    print('[TIECD] --- Runtime Configuration ---');
    print('[TIECD] files:\t\t\t${config.files}');
    print('[TIECD] files-commit-prefix:\t${config.filesCommitPrefix}');
    print('[TIECD] apps:\t\t\t${config.apps}');
    print('[TIECD] apps-commit-prefix:\t${config.appsCommitPrefix}');
    print('[TIECD] base-dir: \t\t${config.baseDir}');
    print('[TIECD] file-prefix:\t\t${config.filePrefix}');
    print('[TIECD] app-names-required:\t${config.appNamesRequired}');
    print('[TIECD] ignore-errors:\t\t${config.ignoreErrors}');
    print('[TIECD] verbose:\t\t${config.verbose}');
    print('[TIECD] trace-artifacts:\t${config.traceArtifacts}');
    print('[TIECD] trace-commands:\t\t${config.traceCommands}');
    print('[TIECD] banner:\t\t\t${config.banner}');
    print('[TIECD] ---');
  }
}

Future<Config> buildConfig(final ArgResults argResults) async {

  Config config = Config();

  // process args then override with environment variable values
  config.filesCommitPrefix = setupStringValue(
      argResults['files-commit-prefix'], 'TIECD_FILES_COMMIT_PREFIX');
  config.appsCommitPrefix = setupStringValue(
      argResults['apps-commit-prefix'], 'TIECD_APPS_COMMIT_PREFIX');

  // process git log
  await processGitLog(config);

  // now process reset of the configuration with higher precedence
  config.files = setupStringValueWithDefault(config.files,argResults['files'], 'TIECD_FILES');
  config.apps = setupStringValueWithDefault(config.apps, argResults['apps'], 'TIECD_APPS');
  config.baseDir = setupStringValue(argResults['base-dir'], 'TIECD_BASEDIR');
  config.filePrefix =
      setupStringValue(argResults['file-prefix'], 'TIECD_FILE_PREFIX');
  config.appNamesRequired = setupBoolValue(
      argResults['app-names-required'], 'TIECD_APP_NAMES_REQUIRED');
  config.ignoreErrors =
      setupBoolValue(argResults['ignore-errors'], 'TIECD_IGNORE_ERRORS');
  config.verbose = setupBoolValue(argResults['verbose'], 'TIECD_VERBOSE');
  config.traceArtifacts =
      setupBoolValue(argResults['trace-artifacts'], 'TIECD_TRACE_ARTIFACTS');
  config.traceCommands =
      setupBoolValue(argResults['trace-commands'], 'TIECD_TRACE_COMMANDS');
  config.banner =
      setupBoolValue(argResults['banner'], 'TIECD_BANNER');

  showHeader(config);

  // additional option checking
  if (config.appNamesRequired && config.apps == '') {
    print('apps names required option is set but no app names have been set');
    exit(1);
  }
  if (config.apps == 'all') {
    config.apps = '';
  }

  return config;
}


class DeployCommand extends Command {
  @override
  final name = 'deploy';
  @override
  final description = 'Run deployment process on current directory';

  // [run] may also return a Future.
  @override
  Future<void> run() async {
    var config = await buildConfig(globalResults!);
    try {
      Deploy deploy = Deploy(config);
      await deploy.run();
    } on TieError catch (error) {
      Log.error(error.cause);
      exit(1);
    }
  }
}

class BuildCommand extends Command {
  @override
  final String name = 'build';
  @override
  final String description = 'Auto build a container image';

  @override
  Future<void> run() async {
    // [argResults] is set before [run()] is called and contains the flags/options
    // passed to this command.
    print(argResults!['all']);
    //todo
  }
}

Future<void> main(List<String> arguments) async {
  var runner =
      CommandRunner('tiecd', 'A simplified CICD toolchain for kubernetes deployments.');

  runner.argParser.addOption('files',
      abbr: 'f', help: 'specific files to run, [env: TIECD_FILES]');
  runner.argParser.addOption('files-commit-prefix',
      abbr: 'i',
      defaultsTo: 'file|files',
      help:
          'label used to select which files to process, i.e. files=... [env: TIECD_FILES_COMMIT_PREFIX]');
  runner.argParser.addOption('apps',
      abbr: 'a', help: 'override which apps to run [env: TIECD_APPS]');
  runner.argParser.addOption('apps-commit-prefix',
      abbr: 'c',
      defaultsTo: 'app|apps|run|update',
      help:
          'label used to select which apps to process, i.e. apps=... [env: TIECD_APPS_COMMIT_PREFIX]');
  runner.argParser.addOption('base-dir',
      abbr: 'b',
      help:
          'directory containing tie.yml and deployment files [env: TIECD_BASEDIR]');
  runner.argParser.addOption('file-prefix',
      abbr: 'p',
      defaultsTo: 'tie',
      help:
          'file prefix for tie.yml files, defaults to tie [env: TIECD_FILE_PREFIX]');
  runner.argParser.addFlag('app-names-required',
      abbr: 'r',
      defaultsTo: false,
      help:
          'only execute the app names that are passed at runtime [env: TIECD_APP_NAMES_REQUIRED]');
  runner.argParser.addFlag('ignore-errors',
      abbr: 'g',
      defaultsTo: false,
      help:
          'ignore errors keep processing other apps [env: TIECD_IGNORE_ERRORS]');
  runner.argParser.addFlag('verbose',
      abbr: 'v', defaultsTo: false, help: 'increase informational logging');
  runner.argParser.addFlag('trace-artifacts',
      abbr: 's',
      defaultsTo: false,
      help:
          'output generated and expanded artifacts [env: TIECD_TRACE_ARTIFACTS]');
  runner.argParser.addFlag('trace-commands',
      abbr: 'm',
      defaultsTo: false,
      help:
          'output generated and expanded artifacts [env: TIECD_TRACE_COMMANDS]');
  runner.argParser.addFlag('banner',
      abbr: 'n',
      defaultsTo: true,
      help:
      'show TIECD banner header during execution [env: TIECD_BANNER]');


  runner
    ..addCommand(DeployCommand())
    ..addCommand(BuildCommand())
    ..run(arguments).catchError((error) {
      if (error is! UsageException) throw error;
      print(error);
      exit(64); // Exit code 64 indicates a usage error.
    });
}
