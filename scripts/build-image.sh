#!/bin/bash
set -e

# prime resources into base module
mkdir images/modules/base/build
cp bin/tiecd images/modules/base/build/.
cp LICENSE images/modules/base/build/.
cp oss_licenses.json images/modules/base/build/.

while read tag; do
  if [ "$1" == "full" ]; then
    tagargs+=( --tag="$tag" )
  else
    tagargs+=( --tag="$tag-$1" )
  fi
done <tags.txt

cekit --descriptor images/$1.yaml build docker "${tagargs[@]}"

while read tag; do
  if [ "$1" == "full" ]; then
    echo "docker push $tag"
    docker push $tag
  else
    echo "docker push $tag-$1"
    docker push $tag-$1

    # tag okd image openshift also
    if [ "$1" == "okd" ]; then
       docker tag $tag-$1 $tag-openshift
       echo "docker push $tag-openshift
       docker push $tag 
    fi
  fi
done <tags.txt

