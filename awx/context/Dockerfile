ARG EE_BASE_IMAGE="quay.io/ansible/awx-ee:latest"
ARG PYCMD="/usr/bin/python3"
ARG PKGMGR_PRESERVE_CACHE=""
ARG ANSIBLE_GALAXY_CLI_COLLECTION_OPTS=""
ARG ANSIBLE_GALAXY_CLI_ROLE_OPTS=""
ARG PKGMGR="/usr/bin/dnf"

# Base build stage
FROM $EE_BASE_IMAGE as base
USER root
ENV PIP_BREAK_SYSTEM_PACKAGES=1
ARG EE_BASE_IMAGE
ARG PYCMD
ARG PKGMGR_PRESERVE_CACHE
ARG ANSIBLE_GALAXY_CLI_COLLECTION_OPTS
ARG ANSIBLE_GALAXY_CLI_ROLE_OPTS
ARG PKGMGR

COPY _build/scripts/ /output/scripts/
COPY _build/scripts/entrypoint /opt/builder/bin/entrypoint
RUN /output/scripts/pip_install $PYCMD

# Galaxy build stage
FROM base as galaxy
ARG EE_BASE_IMAGE
ARG PYCMD
ARG PKGMGR_PRESERVE_CACHE
ARG ANSIBLE_GALAXY_CLI_COLLECTION_OPTS
ARG ANSIBLE_GALAXY_CLI_ROLE_OPTS
ARG PKGMGR

RUN /output/scripts/check_galaxy
COPY _build /build
WORKDIR /build

RUN mkdir -p /usr/share/ansible
RUN ansible-galaxy role install $ANSIBLE_GALAXY_CLI_ROLE_OPTS -r requirements.yml --roles-path "/usr/share/ansible/roles"
RUN ANSIBLE_GALAXY_DISABLE_GPG_VERIFY=1 ansible-galaxy collection install $ANSIBLE_GALAXY_CLI_COLLECTION_OPTS -r requirements.yml --collections-path "/usr/share/ansible/collections"

# Builder build stage
FROM base as builder
ENV PIP_BREAK_SYSTEM_PACKAGES=1
WORKDIR /build
ARG EE_BASE_IMAGE
ARG PYCMD
ARG PKGMGR_PRESERVE_CACHE
ARG ANSIBLE_GALAXY_CLI_COLLECTION_OPTS
ARG ANSIBLE_GALAXY_CLI_ROLE_OPTS
ARG PKGMGR

RUN $PYCMD -m pip install --no-cache-dir bindep pyyaml packaging

COPY --from=galaxy /usr/share/ansible /usr/share/ansible

COPY _build/requirements.txt requirements.txt
RUN $PYCMD /output/scripts/introspect.py introspect --user-pip=requirements.txt --write-bindep=/tmp/src/bindep.txt --write-pip=/tmp/src/requirements.txt
RUN /output/scripts/assemble

# Final build stage
FROM base as final
ENV PIP_BREAK_SYSTEM_PACKAGES=1
ARG EE_BASE_IMAGE
ARG PYCMD
ARG PKGMGR_PRESERVE_CACHE
ARG ANSIBLE_GALAXY_CLI_COLLECTION_OPTS
ARG ANSIBLE_GALAXY_CLI_ROLE_OPTS
ARG PKGMGR

RUN /bin/sh -lc 'set -eux; if command -v microdnf >/dev/null 2>&1; then microdnf install -y gcc make python3-devel openssl-devel libffi-devel libxml2-devel libcurl-devel && microdnf clean all; elif command -v dnf >/dev/null 2>&1; then dnf install -y gcc make python3-devel openssl-devel libffi-devel libxml2-devel libcurl-devel && dnf clean all; elif command -v yum >/dev/null 2>&1; then yum install -y gcc make python3-devel openssl-devel libffi-devel libxml2-devel libcurl-devel && yum clean all; elif command -v apt-get >/dev/null 2>&1; then apt-get update && apt-get install -y gcc make python3-dev libssl-dev libffi-dev libxml2-dev libcurl4-openssl-dev && rm -rf /var/lib/apt/lists/*; else echo "no package manager found" && exit 1; fi'

COPY --from=galaxy /usr/share/ansible /usr/share/ansible

COPY --from=builder /output/ /output/
RUN /output/scripts/install-from-bindep && rm -rf /output/wheels
RUN chmod ug+rw /etc/passwd
RUN mkdir -p /runner && chgrp 0 /runner && chmod -R ug+rwx /runner
WORKDIR /runner
RUN $PYCMD -m pip install --no-cache-dir 'dumb-init==1.2.5'
RUN /bin/sh -lc 'set -eux; python3 -m ensurepip --upgrade || true; python3 -m pip install --no-cache-dir --upgrade pip; python3 -m pip install --no-cache-dir paramiko ansible-pylibssh; ansible-galaxy collection install vyos.vyos'
RUN rm -rf /output
LABEL ansible-execution-environment=true
USER 1000
ENTRYPOINT ["/opt/builder/bin/entrypoint", "dumb-init"]
CMD ["bash"]
