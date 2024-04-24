
// image tag could be different formats
// node:20-alpine
// bitnami/postgresql:latest
// registry.gitlab.com/dataaxiom/node:20-alpine
import 'package:tiecd/src/extensions.dart';

class ImageTag {
  String? host;
  String? repository;
  String name = '';
  String tag = '';
  bool isSha = false;

  ImageTag(String imageTag) {
    List<String> parts = imageTag.split('/');
    if (parts.length > 1) {
      if (parts[0].contains('.')) {
        // we assume first part is hostname
        host = parts[0];
        initVersion(imageTag.substring(host!.length + 1));
      } else {
        initVersion(imageTag);
      }
    } else {
      initVersion(imageTag);
    }
    // set to default
    if (host.isNullOrEmpty) {
      host = 'registry-1.docker.io';
    }
  }

  void initVersion(String imageTag) {
    List<String> parts = [];
    if (imageTag.contains('@')) {
      parts = imageTag.split('@');
      isSha = true;
    } else {
      parts = imageTag.split(':');
    }
    if (parts.length == 2) {
      if (parts[0].contains('/')) {
        repository = parts[0].substring(0, parts[0].lastIndexOf('/'));
        name = parts[0].substring(parts[0].lastIndexOf('/') + 1);
      } else {
        name = parts[0];
      }
      tag = parts[1];
    } else {
      if (imageTag.contains('/')) {
        repository = imageTag.substring(0, imageTag.lastIndexOf('/'));
        name = imageTag.substring(imageTag.lastIndexOf('/') + 1);
      } else {
        name = imageTag;
      }
      tag = 'latest';
    }
  }

  String get path {
    if (repository.isNotNullNorEmpty) {
      return '$repository/$name';
    } else {
      return name;
    }
  }
}