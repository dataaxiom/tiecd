
class Config {
  bool verbose = false;
  String files = '';
  String filesCommitPrefix = 'file|files';
  String apps = '';
  String appsCommitPrefix = 'app|apps|run|update';
  String baseDir = '';
  String filePrefix = "tie";
  bool appNamesRequired = false;
  bool ignoreErrors = false;
  bool traceArtifacts = false;
  bool traceCommands = true;
  bool banner = true;
  bool createNamespaces = true;
  String scratchDir = ".tiecd";
}


class TieError implements Exception {
  String cause;
  TieError(this.cause);
}