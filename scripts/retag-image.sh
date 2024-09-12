#!/bin/bash
set -e

# currently retagging okd

while read tag; do
  # tag okd image openshift also
  if [ "$1" == "okd" ]; then
     newtag=$(echo "$tag" | sed -r 's/okd/openshift/g')
     docker pull $tag
     docker tag $tag $newtag
     echo "docker push $newtag"
     docker push $newtag
  fi
done <tags.txt
