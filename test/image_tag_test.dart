
import 'package:test/test.dart';
import 'package:tiecd/src/util/image_tag.dart';

void main() {
  group('ImageTag ', ()
  {
    test('docker public image', () {
      ImageTag tag = ImageTag('node:20-alpine');
      expect(tag.name, 'node');
      expect(tag.tag, '20-alpine');
      expect(tag.host, 'registry-1.docker.io');
      expect(tag.repository, null);
      expect(tag.isSha, false);
      expect(tag.path, 'node');
    });
    test('docker public image latest', () {
      ImageTag tag = ImageTag('node');
      expect(tag.name, 'node');
      expect(tag.tag, 'latest');
      expect(tag.host, 'registry-1.docker.io');
      expect(tag.repository, null);
      expect(tag.isSha, false);
      expect(tag.path, 'node');
    });
    test('docker public image sha', () {
      ImageTag tag = ImageTag('node@sha256:7b8ee0e573f8a5f58f2f89410136d3c5a655ab6bc7cb1cc8d8fdd461d57481de');
      expect(tag.name, 'node');
      expect(tag.tag, 'sha256:7b8ee0e573f8a5f58f2f89410136d3c5a655ab6bc7cb1cc8d8fdd461d57481de');
      expect(tag.host, 'registry-1.docker.io');
      expect(tag.repository, null);
      expect(tag.isSha, true);
      expect(tag.path,'node');
    });
    test('docker public image with repository', () {
      ImageTag tag = ImageTag('bitnami/postgresql:latest');
      expect(tag.name, 'postgresql');
      expect(tag.tag, 'latest');
      expect(tag.host, 'registry-1.docker.io');
      expect(tag.repository, 'bitnami');
      expect(tag.isSha, false);
      expect(tag.path,'bitnami/postgresql');
    });
    test('custom image with repository', () {
      ImageTag tag = ImageTag('registry.gitlab.com/dataaxiom/node:20-alpine');
      expect(tag.name, 'node');
      expect(tag.tag, '20-alpine');
      expect(tag.host, 'registry.gitlab.com');
      expect(tag.repository, 'dataaxiom');
      expect(tag.isSha, false);
      expect(tag.path,'dataaxiom/node');
    });
    test('custom image with repository and sha', () {
      ImageTag tag = ImageTag('registry.gitlab.com/dataaxiom/node@sha256:7b8ee0e573f8a5f58f2f89410136d3c5a655ab6bc7cb1cc8d8fdd461d57481de');
      expect(tag.name, 'node');
      expect(tag.tag, 'sha256:7b8ee0e573f8a5f58f2f89410136d3c5a655ab6bc7cb1cc8d8fdd461d57481de');
      expect(tag.host, 'registry.gitlab.com');
      expect(tag.repository, 'dataaxiom');
      expect(tag.isSha, true);
      expect(tag.path,'dataaxiom/node');
    });
    test('custom image with repository and port', () {
      ImageTag tag = ImageTag('registry.gitlab.com:9080/dataaxiom/node:20-alpine');
      expect(tag.name, 'node');
      expect(tag.tag, '20-alpine');
      expect(tag.host, 'registry.gitlab.com:9080');
      expect(tag.repository, 'dataaxiom');
      expect(tag.isSha, false);
      expect(tag.path,'dataaxiom/node');
    });
  });
}
