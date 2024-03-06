#!/bin/bash
set -e

# prime resources into base module
mkdir images/modules/base/build

cp bin/tiecd images/modules/base/build/.
cp tiecd.arm64 images/modules/base/build/.
cp bin/umoci-perm.sh images/modules/base/build/.
cp LICENSE images/modules/base/build/.
cp oss_licenses.json images/modules/base/build/.

while read tag; do
  tagargs+=( --tag="$tag-$1" )
done <tags.txt

# need to fix via overrides?
#while read label; do
#  args+=( --label="$label" )
#done <labels.txt

cekit --descriptor images/$1.yaml build docker "${tagargs[@]}"

while read tag; do
  echo "docker push $tag-$1"
  docker push $tag-$1

  # tag okd image openshift also
  if [ "$1" == "okd" ]; then
     docker tag $tag-$1 $tag-openshift
     echo "docker push $tag-openshift"
     docker push $tag-openshift
  fi
done <tags.txt
