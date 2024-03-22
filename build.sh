#!/bin/bash

set -e

dart pub get
dart pub run flutter_oss_licenses:generate.dart -o oss_licenses.json --json
dart run build_runner build
dart compile exe bin/tiecd.dart -o bin/tiecd
mkdir -p images/modules/base/build
cp bin/tiecd images/modules/base/build
cp bin/umoci-perm.sh images/modules/base/build
cp oss_licenses.json images/modules/base/build
cp LICENSE images/modules/base/build
