import 'package:json_annotation/json_annotation.dart';

part 'dsl.g.dart';

@JsonSerializable()
class Proxy {
  String? host;
  int? port;
  String? username;
  String? password;

  Proxy();
  factory Proxy.fromJson(Map json) => _$ProxyFromJson(json);
  Map<String, dynamic> toJson() => _$ProxyToJson(this);
}

enum ImageMode { push, pull }

@JsonSerializable()
class ImageRepository {
  String? name;
  String? url;
  String? username;
  String? password;
  String? token;
  bool? tlsVerify;
  ImageMode? mode;

  ImageRepository();
  factory ImageRepository.fromJson(Map json) => _$ImageRepositoryFromJson(json);
  Map<String, dynamic> toJson() => _$ImageRepositoryToJson(this);
}

@JsonSerializable()
class MavenRepository {
  String? name;
  String? url;
  String? username;
  String? password;

  MavenRepository();
  factory MavenRepository.fromJson(Map json) => _$MavenRepositoryFromJson(json);
  Map<String, dynamic> toJson() => _$MavenRepositoryToJson(this);
}

@JsonSerializable()
class Repositories {
  List<ImageRepository>? image;
  List<MavenRepository>? maven;

  Repositories();
  factory Repositories.fromJson(Map json) => _$RepositoriesFromJson(json);
  Map<String, dynamic> toJson() => _$RepositoriesToJson(this);
}

@JsonSerializable()
class Environment {
  String? name;
  String? label;
  String? apiType;  // currently only 'kubernetes
  String? apiProvider; // refined target provider, currently gke

  // direct connectivity options
  String? apiUrl;
  bool? apiTlsVerify;
  String? apiToken;
  String? apiClientKey;
  String? apiClientKeyFile;

  String? apiClientCert; // not for direct use currently
  //String? apiClientCertFile;
  String? apiClientCA; // not for direct use currently
  //String? apiClientCAFile;

  // full config file such as a kube_config file
  String? apiConfig;  // direct contents
  String? apiConfigFile;  // file containing config file

  // public cloud config
  String? serviceAccountName;
  String? projectId;
  String? zone;

  String? namespace;
  ImageRepository? repository;

  Environment();
  factory Environment.fromJson(Map json) => _$EnvironmentFromJson(json);
  Map<String, dynamic> toJson() => _$EnvironmentToJson(this);

  // basic clone to allow expansion to work with login/logff
  Environment clone() {
    Environment clone = Environment();
    clone.name = name;
    clone.label = label;
    clone.apiType = apiType;
    clone.apiProvider = apiProvider;
    clone.apiUrl = apiUrl;
    clone.apiTlsVerify = apiTlsVerify;
    clone.apiToken = apiToken;
    clone.apiClientKey = apiClientKey;
    clone.apiClientKeyFile = apiClientKeyFile;
    clone.apiClientCert = apiClientCert;
    //String? apiClientCertFile;
    clone.apiClientCA = apiClientCA;
    //String? apiClientCAFile;
    clone.apiConfig = apiConfig;
    clone.apiConfigFile = apiConfigFile;
    clone.serviceAccountName = serviceAccountName;
    clone.projectId = projectId;
    clone.zone = zone;
    clone.namespace = namespace;
    clone.repository = repository; // not a deep copy
    return clone;
  }
}

enum Action { install, uninstall }

@JsonSerializable()
class Image {
  String? name;
  String? version;
  String? type;
  String? baseVersion;
  String? registry;
  ImageMode? imageMode;

  Image();
  factory Image.fromJson(Map json) => _$ImageFromJson(json);
  Map<String, dynamic> toJson() => _$ImageToJson(this);
}

@JsonSerializable()
class HelmChart {
  String? name;
  String? url;
  String? chart;
  String? version;
  List<String>? values;
  List<String>? sets;
  List<String>? args;
  String? namespace;
  List<String>? flags;

  HelmChart();
  factory HelmChart.fromJson(Map json) => _$HelmChartFromJson(json);
  Map<String, dynamic> toJson() => _$HelmChartToJson(this);
}

@JsonSerializable()
class Coordinate {
  String? groupId;
  String? artifactId;
  String? version;
  String? path;

  Coordinate();
  factory Coordinate.fromJson(Map json) => _$CoordinateFromJson(json);
  Map<String, dynamic> toJson() => _$CoordinateToJson(this);
}

enum DeploymentMode { single, multi }

@JsonSerializable()
class Facet {
  String? name;
  Map<String, String>? env;

  Facet();
  factory Facet.fromJson(Map json) => _$FacetFromJson(json);
  Map<String, dynamic> toJson() => _$FacetToJson(this);
}

@JsonSerializable()
class MountFile {
  String? file;
  String? mount;

  MountFile();
  factory MountFile.fromJson(Map json) => _$MountFileFromJson(json);
  Map<String, dynamic> toJson() => _$MountFileToJson(this);
}

@JsonSerializable()
class HttpGet {
  String? host;
  String? scheme;
  String? path;
  String? httpHeaders;
  String? port;

  HttpGet();
  factory HttpGet.fromJson(Map json) => _$HttpGetFromJson(json);
  Map<String, dynamic> toJson() => _$HttpGetToJson(this);
}

@JsonSerializable()
class Probe {
  String? initialDelay;
  String? period;
  String? timeout;
  String? successThreshold;
  String? failureThreshold;
  HttpGet? httpGet;

  Probe();
  factory Probe.fromJson(Map json) => _$ProbeFromJson(json);
  Map<String, dynamic> toJson() => _$ProbeToJson(this);
}

enum TerminationType {  edge, passthrough, reencrypt }

@JsonSerializable()
class Route {
  String? name;
  String? host;
  TerminationType? termination;
  String? key;
  String? certificate;
  String? caCertificate;
  String? path;

  Route();
  factory Route.fromJson(Map json) => _$RouteFromJson(json);
  Map<String, dynamic> toJson() => _$RouteToJson(this);
}

@JsonSerializable()
class Resources {
  String? cpu;
  String? memory;

  Resources();
  factory Resources.fromJson(Map json) => _$ResourcesFromJson(json);
  Map<String, dynamic> toJson() => _$ResourcesToJson(this);
}

@JsonSerializable()
class Secret {
  String? file;

  Secret();
  factory Secret.fromJson(Map json) => _$SecretFromJson(json);
  Map<String, dynamic> toJson() => _$SecretToJson(this);
}

@JsonSerializable()
class Volume {
  String? name;
  String? size;
  String? mount;
  String? storageClass;
  DeploymentMode? type;

  Volume();
  factory Volume.fromJson(Map json) => _$VolumeFromJson(json);
  Map<String, dynamic> toJson() => _$VolumeToJson(this);
}

@JsonSerializable()
class Command {
  String? path;
  List<String>? args;

  Command();
  factory Command.fromJson(Map json) => _$CommandFromJson(json);
  Map<String, dynamic> toJson() => _$CommandToJson(this);
}

@JsonSerializable()
class Spec {
  String? name;
  String? replicas;
  Probe? startupProbe;
  Probe? readinessProbe;
  Probe? livenessProbe;
  //protected Service service;
  List<Route>? routes;
  Resources? limits;
  Resources? requests;
  List<Secret>? secrets;

  Spec();
  factory Spec.fromJson(Map json) => _$SpecFromJson(json);
  Map<String, dynamic> toJson() => _$SpecToJson(this);
}

@JsonSerializable()
class App {
  String? name;
  String? label;
  bool? autoRun;
  Action? action;
  List<String>? includes;
  String? dependsOn;
  String? namespace;
  List<Image>? images;
  List<Coordinate>? artifacts;

  DeploymentMode? deploymentMode;
  List<Facet>? facets;
  List<MountFile>? mountFiles;
  List<String>? templateFiles;
  // environment variables available during deployment time
  Map<String, String>? deployEnv;
  List<String>? deployEnvPropertyFiles;
  // environment variables applied during deployment time and runtime (if applicable)
  Map<String,String>? env;
  List<String>? envPropertyFiles;
  List<String>? volumes;
  List<HelmChart>? helmCharts;
  // apps to run after
  List<String>? postApps;
  List<String>? errorApps;

  // script to run pre/post
  List<Command>? preCommands;
  List<Command>? preDeployCommands;
  List<Command>? postCommands;
  List<Command>? errorCommands;
  String? comment;

  App();
  factory App.fromJson(Map json) => _$AppFromJson(json);
  Map<String, dynamic> toJson() => _$AppToJson(this);
}


@JsonSerializable()
class Tie {
  String? version;
  List<String>? includes;
  Proxy? proxy;
  Repositories? repositories;
  List<Environment>? environments;
  List<App>? apps;

  Tie();
  factory Tie.fromJson(Map json) => _$TieFromJson(json);
  Map<String, dynamic> toJson() => _$TieToJson(this);
}
