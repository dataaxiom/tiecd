#!/bin/bash

# install coverage
# dart pub global activate coverage

dart pub global run coverage:test_with_coverage --function-coverage --branch-coverage

genhtml coverage/lcov.info -o coverage/html
# Open the report
open coverage/html/index.html
