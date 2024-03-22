#!/bin/bash
# fixes unpack file permissions
find $1 -type d ! -perm -200 |xargs chmod u+w

