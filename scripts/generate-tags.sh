#!/bin/bash

while read tag; do
  tags+=(" $tag-$1")
done <tags.txt

echo -n ${tags[@]}
