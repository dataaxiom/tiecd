#!/bin/bash
set -e

# prime resources into base module
mkdir images/modules/base/build

# extract amd64 build
tar --strip-components=1 -xvf tiecd-amd64.tgz
cp bin/tiecd images/modules/base/build/tiecd
cp oss_licenses.json images/modules/base/build/.

cp scripts/umoci-perm.sh images/modules/base/build/.
cp LICENSE images/modules/base/build/.

while read tag; do
  tagargs+=( --tag="$tag" )
done <tags.txt

# need to fix via overrides?
#while read label; do
#  args+=( --label="$label" )
#done <labels.txt

cekit --descriptor images/$1.yaml build docker "${tagargs[@]}"

while read tag; do
  echo "docker push $tag"
  docker push $tag
done <tags.txt
