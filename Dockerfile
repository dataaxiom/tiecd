FROM debian:bookworm-slim

LABEL org.opencontainers.image.description "A simplified CICD toolchain for kubernetes deployments."

ENV LANG=en_US.UTF-8
ENV DEBIAN_FRONTEND=noninteractive
ENV OC_VERSION "4.10.0-0.okd-2022-06-24-212905"
ENV HELM_VERSION "3.10.2"

ENV PATH="${PATH}:/opt/dataaxiom/bin"

WORKDIR /opt/dataaxiom

# download and extract the client tools
RUN apt-get update && \
    apt-get -yq --no-install-recommends install locales curl ca-certificates && \
    sed -i 's/^# *\(en_US.UTF-8\)/\1/' /etc/locale.gen && locale-gen && \
    locale -a && \
    mkdir -p /opt/dataaxiom/bin && \
    mkdir -p /opt/dataaxiom/3rdparty && \
    curl -L https://github.com/openshift/okd/releases/download/$OC_VERSION/openshift-client-linux-$OC_VERSION.tar.gz -o /tmp/oc.tar.gz && \
    mkdir /tmp/oc && \
    tar -xzvf /tmp/oc.tar.gz -C /tmp/oc && \
    mv /tmp/oc/README.md /opt/dataaxiom/3rdparty/README.oc.md && \
    mv /tmp/oc/oc /opt/dataaxiom/bin/ && \
    mv /tmp/oc/kubectl /opt/dataaxiom/bin/ && \
    rm -rf /tmp/oc* && \
    curl https://get.helm.sh/helm-v${HELM_VERSION}-linux-amd64.tar.gz -o /tmp/helm.tar.gz && \
    mkdir /tmp/helm && \
    tar --strip-components=1 -xzvf /tmp/helm.tar.gz -C /tmp/helm && \
    mv /tmp/helm/helm /opt/dataaxiom/bin/ && \
    mv /tmp/helm/LICENSE /opt/dataaxiom/3rdparty/LICENSE.helm && \
    mv /tmp/helm/README.md /opt/dataaxiom/3rdparty/README.helm.md && \
    rm -rf /tmp/helm* && \
    apt-get -yq install git gettext jq apache2-utils skopeo umoci && \
    curl https://packages.cloud.google.com/apt/doc/apt-key.gpg | gpg --dearmor -o /usr/share/keyrings/cloud.google.gpg && \
    echo "deb [signed-by=/usr/share/keyrings/cloud.google.gpg] https://packages.cloud.google.com/apt cloud-sdk main" | tee -a /etc/apt/sources.list.d/google-cloud-sdk.list && \
    apt-get update && \
    apt-get install -yq google-cloud-sdk-gke-gcloud-auth-plugin && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

COPY oss_licenses.json /opt/dataaxiom/3rdparty/oss_licenses.json
COPY LICENSE /opt/dataaxiom/LICENSE
COPY bin/tiecd /opt/dataaxiom/bin/tiecd
