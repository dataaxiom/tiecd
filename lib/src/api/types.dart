
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
  bool traceGenerated = false;
  bool traceCommands = false;
  bool traceTieFile = false;
  String secretLabels = 'password|secret|token|key|cert';
  Set<String> secretLabelSet = {};
  bool banner = true;
  bool createNamespaces = true;
  String scratchDir = ".tiecd";
}


class TieError implements Exception {
  String cause;
  TieError(this.cause);
}