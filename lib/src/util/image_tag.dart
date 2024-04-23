
// image tag could be different formats
// node:20-alpine
// bitnami/postgresql:latest
// registry.gitlab.com/dataaxiom/node:20-alpine
import 'package:tiecd/src/extensions.dart';

class ImageTag {
  String? host;
  String repository = '';
  String name = '';
  String tag = '';
  bool isSha = false;

  ImageTag(String iamgeTag) {
    List<String> parts = iamgeTag.split('/');
    if (parts.length > 1) {
      if (parts[0].contains('.')) {
        // we assume first part is hostname
        host = parts[0];
        initVersion(iamgeTag.substring(host!.length + 1));
      } else {
        initVersion(iamgeTag);
      }
    } else {
      initVersion(iamgeTag);
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
      repository = parts[0];
      tag = parts[1];
    } else {
      repository = imageTag;
      tag = 'latest';
    }
    if (repository.contains('/')) {
      name = repository.substring(repository.lastIndexOf('/') + 1);
    } else {
      name = repository;
    }
  }

  String get path {
    if (repository.isNotNullNorEmpty) {
      return '$repository/$name';
    } else {
      return '';
    }
  }
}