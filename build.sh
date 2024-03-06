#!/bin/bash

set -e

dart pub get
dart pub run flutter_oss_licenses:generate.dart -o oss_licenses.json --json
dart run build_runner build
dart compile exe bin/tiecd.dart -o bin/tiecd
