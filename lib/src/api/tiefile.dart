import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:json_annotation/json_annotation.dart';
import 'package:tiecd/src/api/types.dart';
import 'package:tiecd/src/extensions.dart';

part 'tiefile.g.dart';

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

@JsonSerializable()
class ImageRegistry {
  String? host;
  String? username;
  String? password;
  String? token;
  bool? tlsVerify;

  ImageRegistry();
  factory ImageRegistry.fromJson(Map json) => _$ImageRegistryFromJson(json);
  Map<String, dynamic> toJson() => _$ImageRegistryToJson(this);
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
class Environment {
  String? name;
  String? label;
  String? apiType;  // currently only 'kubernetes
  String? apiProvider; // refined target provider, currently gke,eks

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

  // gke config
  String? serviceAccountName;
  String? projectId;
  String? zone;

  // aws  config
  String? region;
  String? accessKey;
  String? secretAccessKey;

  String? namespace;
  ImageRegistry? registry;

  Environment();
  factory Environment.fromJson(Map json) => _$EnvironmentFromJson(json);
  Map<String, dynamic> toJson() => _$EnvironmentToJson(this);

  // used for namespace/environment wide shared resources
  // key is namespace or environment name
  @JsonKey(includeFromJson: false, includeToJson: false)
  Map<String,Set<String>> deployedArtifacts = {};

  // calculate a signature of the instance
  String signature() {
    StringBuffer buffer = StringBuffer();
    var payload = jsonEncode(toJson());
    if (payload.isNotNullNorEmpty) {
      buffer.write(payload);
    }
    if (apiClientKeyFile.isNotNullNorEmpty) {
      if (!File(apiClientKeyFile!).existsSync()) {
        throw TieError(
            "api config file: $apiClientKeyFile does not exist");
      } else {
        buffer.write(File(apiClientKeyFile!).readAsStringSync());
      }
    }
    if (apiConfigFile.isNotNullNorEmpty) {
      if (!File(apiConfigFile!).existsSync()) {
        throw TieError(
            "api config file: $apiConfigFile does not exist");
      } else {
        buffer.write(File(apiConfigFile!).readAsStringSync());
      }
    }
    var bytes = utf8.encode(buffer.toString());
    var digest = sha256.convert(bytes);
    return digest.toString();
  }

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
    clone.region = region;
    clone.accessKey = accessKey;
    clone.secretAccessKey = secretAccessKey;
    clone.namespace = namespace;
    clone.registry = registry; // not a deep copy
    return clone;
  }
}

enum Action { install, uninstall }

@JsonSerializable()
class Image {
  String? tag;
  ImageType? type;

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
  String? args;
  String? namespace;

  HelmChart();
  factory HelmChart.fromJson(Map json) => _$HelmChartFromJson(json);
  Map<String, dynamic> toJson() => _$HelmChartToJson(this);
}

@JsonSerializable()
class Ytt {
  String? args;
  List<String>? files;

  Ytt();
  factory Ytt.fromJson(Map json) => _$YttFromJson(json);
  Map<String, dynamic> toJson() => _$YttToJson(this);
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
class MountFile {
  String? file;
  String? mount;

  MountFile();
  factory MountFile.fromJson(Map json) => _$MountFileFromJson(json);
  Map<String, dynamic> toJson() => _$MountFileToJson(this);
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

enum BuildType { maven, gradle, npm, yarn, pnpm, flutter }
enum ImageType { plain, springboot, jetty, karaf, tomcat, node, nextjs, nginx }

@JsonSerializable()
class ImageDefinition {
  String? from;
  String? author;
  List<String>? copy;
  List<String>? expose; //ports
  List<String>? env;
  List<String>? label;
  String? workdir;
  List<String>? cmd;

  ImageDefinition();
  factory ImageDefinition.fromJson(Map json) => _$ImageDefinitionFromJson(json);
  Map<String, dynamic> toJson() => _$ImageDefinitionToJson(this);
}


@JsonSerializable()
class Build {
  BuildType? type;
  List<Coordinate>? artifacts;
  List<String>? beforeScripts;
  List<String>? scripts;
  List<String>? afterScripts;
  // image setup
  ImageDefinition? imageDefinition;

  Build();
  factory Build.fromJson(Map json) => _$BuildFromJson(json);
  Map<String, dynamic> toJson() => _$BuildToJson(this);
}

@JsonSerializable()
class Deploy {
  Action? action;
  DeploymentMode? deploymentMode;
  List<MountFile>? mountFiles;
  List<String>? manifests; // file paths to file manifests
  Ytt? ytt;
  Map<String, String>? env; // environment variables available during deployment time
  List<String>? envPropertyFiles;

  List<String>? volumes;
  List<Secret>? secrets;
  HelmChart? helmChart;
  // apps to run after
  List<String>? postApps;
  List<String>? errorApps;

  // script to run
  List<String>? beforeScripts;
  List<String>? scripts;
  List<String>? afterScripts;
  List<String>? errorScripts;

  bool? generateManifests;
  String? namespace;
  String? hostname;

  Deploy();
  factory Deploy.fromJson(Map json) => _$DeployFromJson(json);
  Map<String, dynamic> toJson() => _$DeployToJson(this);
}

@JsonSerializable(createToJson: true)
class App {
  String? name;
  String? label;
  bool? autoRun;
  List<String>? includes;
  String? dependsOn;
  Image? image;
  // environment variables applied during tiecd runtime execution
  Map<String,String>? tiecdEnv;
  List<String>? tiecdEnvPropertyFiles;
  String? comment;

  Build? build;
  Deploy? deploy;

  App();
  factory App.fromJson(Map json) => _$TieAppFromJson(json);
  Map<String, dynamic> toJson() => _$AppToJson(this);
}


@JsonSerializable()
class Tie {
  String? version;
  List<String>? includes;
  Proxy? proxy;
  List<ImageRegistry>? registries;
  List<Environment>? environments;
  List<App>? apps;

  Tie();
  factory Tie.fromJson(Map json) => _$TieFromJson(json);
  Map<String, dynamic> toJson() => _$TieToJson(this);
}


// custom app override to support nullable image only
// manually update when app definition changes
// supports image tag having no values

App _$TieAppFromJson(Map json) => $checkedCreate(
  'App',
  json,
      ($checkedConvert) {
    final val = App();
    $checkedConvert('name', (v) => val.name = v as String?);
    $checkedConvert('label', (v) => val.label = v as String?);
    $checkedConvert('autoRun', (v) => val.autoRun = v as bool?);
    $checkedConvert(
        'includes',
            (v) => val.includes =
            (v as List<dynamic>?)?.map((e) => e as String).toList());
    $checkedConvert('dependsOn', (v) => val.dependsOn = v as String?);

    // tiecd
    if (json.containsKey("image")) {
      $checkedConvert('image',
              (v) =>
          val.image = v == null ? Image() : Image.fromJson(v as Map));
    }
    $checkedConvert(
        'tiecdEnv',
            (v) => val.tiecdEnv = (v as Map?)?.map(
              (k, e) => MapEntry(k as String, e as String),
        ));
    $checkedConvert(
        'tiecdEnvPropertyFiles',
            (v) => val.tiecdEnvPropertyFiles =
            (v as List<dynamic>?)?.map((e) => e as String).toList());
    $checkedConvert('comment', (v) => val.comment = v as String?);
    $checkedConvert('build',
            (v) => val.build = v == null ? null : Build.fromJson(v as Map));
    $checkedConvert('deploy',
            (v) => val.deploy = v == null ? null : Deploy.fromJson(v as Map));
    return val;
  },
);
