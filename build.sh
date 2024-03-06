#!/bin/bash

set -e

dart run build_runner build
dart compile exe bin/tiecd.dart -o bin/tiecd
