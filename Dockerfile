ARG           FROM_REGISTRY=ghcr.io/dubo-dubon-duponey

ARG           FROM_IMAGE_BUILDER=base:builder-bullseye-2021-07-01@sha256:f1c46316c38cc1ca54fd53b54b73797b35ba65ee727beea1a5ed08d0ad7e8ccf
ARG           FROM_IMAGE_RUNTIME=base:runtime-bullseye-2021-07-01@sha256:9f5b20d392e1a1082799b3befddca68cee2636c72c502aa7652d160896f85b36
ARG           FROM_IMAGE_TOOLS=tools:linux-bullseye-2021-07-01@sha256:f1e25694fe933c7970773cb323975bb5c995fa91d0c1a148f4f1c131cbc5872c

FROM          $FROM_REGISTRY/$FROM_IMAGE_TOOLS                                                                          AS builder-tools

#######################
# Rudder transformer
#######################
FROM          --platform=$BUILDPLATFORM $FROM_REGISTRY/$FROM_IMAGE_BUILDER                                              AS builder-main-transformer

# XXX node-gyp is bollocks
ENV           USER=root
RUN           mkdir -p /tmp/.npm-global
ENV           PATH=/tmp/.npm-global/bin:$PATH
ENV           NPM_CONFIG_PREFIX=/tmp/.npm-global

# Nov, 16, 2020
ENV           GIT_REPO=github.com/rudderlabs/rudder-transformer
ENV           GIT_VERSION=2203066
ENV           GIT_COMMIT=220306626877ce3c69bab7d10ae32ce76fd90ff4

WORKDIR       $GOPATH/src/$GIT_REPO
RUN           git clone --recurse-submodules git://"$GIT_REPO" . && git checkout "$GIT_COMMIT"
RUN           npm install --production
RUN           mkdir -p /dist/boot/bin
RUN           mv "$GOPATH/src/$GIT_REPO" /dist/boot/bin/

#######################
# Builder assemble
#######################
FROM          --platform=$BUILDPLATFORM $FROM_REGISTRY/$FROM_IMAGE_BUILDER                                              AS builder-assembly-transformer

COPY          --from=builder-main-transformer /dist/boot/bin /dist/boot/bin

COPY          --from=builder-tools  /boot/bin/goello-server  /dist/boot/bin
COPY          --from=builder-tools  /boot/bin/caddy          /dist/boot/bin
COPY          --from=builder-tools  /boot/bin/http-health    /dist/boot/bin

RUN           chmod 555 /dist/boot/bin/*; \
              epoch="$(date --date "$BUILD_CREATED" +%s)"; \
              find /dist/boot -newermt "@$epoch" -exec touch --no-dereference --date="@$epoch" '{}' +;

FROM          $FROM_REGISTRY/$FROM_IMAGE_RUNTIME                                                                        AS transformer

USER          root

RUN           --mount=type=secret,uid=100,id=CA \
              --mount=type=secret,uid=100,id=CERTIFICATE \
              --mount=type=secret,uid=100,id=KEY \
              --mount=type=secret,uid=100,id=GPG.gpg \
              --mount=type=secret,id=NETRC \
              --mount=type=secret,id=APT_SOURCES \
              --mount=type=secret,id=APT_CONFIG \
              apt-get update -qq          && \
              apt-get install -qq --no-install-recommends \
                nodejs=12.21.0~dfsg-4 && \
              apt-get -qq autoremove      && \
              apt-get -qq clean           && \
              rm -rf /var/lib/apt/lists/* && \
              rm -rf /tmp/*               && \
              rm -rf /var/tmp/*

USER          dubo-dubon-duponey

COPY          --from=builder-assembly-transformer --chown=$BUILD_UID:root /dist /

EXPOSE        4000

VOLUME        /data

# mDNS
ENV           MDNS_NAME="Rudder Transformer mDNS display name"
ENV           MDNS_HOST="rudder-transformer"
ENV           MDNS_TYPE=_http._tcp

# XXX incomplete - miss domain et al
# Control wether tls is going to be "internal" (eg: self-signed), or alternatively an email address to enable letsencrypt
ENV           TLS="internal"
# Either require_and_verify or verify_if_given
ENV           MTLS_MODE="verify_if_given"

# Realm in case access is authenticated
ENV           REALM="My Precious Realm"
# Provide username and password here (call the container with the "hash" command to generate a properly encrypted password, otherwise, a random one will be generated)
ENV           USERNAME=""
ENV           PASSWORD=""

# Log level and port
ENV           LOG_LEVEL=warn
ENV           PORT=4443

ENV           HEALTHCHECK_URL=http://127.0.0.1:10000/

HEALTHCHECK   --interval=120s --timeout=30s --start-period=10s --retries=1 CMD http-health || exit 1

# ENTRYPOINT    ["node", "./rudder-transformer/index.js"]
