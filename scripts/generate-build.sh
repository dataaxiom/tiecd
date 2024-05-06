#!/bin/bash
set -e

# prime resources into base module
mkdir images/modules/base/build

# extract amd64 build
tar --strip-components=1 -xvf tiecd-amd64.tgz
cp bin/tiecd images/modules/base/build/tiecd
cp oss_licenses.json images/modules/base/build/.

# copy artifacts into build
cp scripts/umoci-perm.sh images/modules/base/build/.
cp LICENSE images/modules/base/build/.

# just use cekit to build dockerfile then use buildx to build multi arch image
cekit --descriptor images/$1.yaml build --dry-run docker
cp scripts/tiecd-fix.txt target/image

# extract arm64 build
tar --strip-components=1 -xvf tiecd-arm64.tgz
cp bin/tiecd target/image/tiecd.arm64

cd target/image
sed -i  '/FROM /r tiecd-fix.txt' Dockerfile 
sed -i '/FROM /s/$/ as big_image/' Dockerfile
echo "" >> Dockerfile
echo "FROM scratch" >> Dockerfile
echo "COPY --from=big_image / /" >> Dockerfile
