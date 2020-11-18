ARG           BUILDER_BASE=dubodubonduponey/base:builder
ARG           RUNTIME_BASE=dubodubonduponey/base:runtime

#######################
# Extra builder for healthchecker
#######################
# hadolint ignore=DL3006,DL3029
FROM          --platform=$BUILDPLATFORM $BUILDER_BASE                                                                   AS builder-healthcheck

ARG           GIT_REPO=github.com/dubo-dubon-duponey/healthcheckers
ARG           GIT_VERSION=51ebf8ca3d255e0c846307bf72740f731e6210c3

WORKDIR       $GOPATH/src/$GIT_REPO
RUN           git clone git://$GIT_REPO .
RUN           git checkout $GIT_VERSION
# hadolint ignore=DL4006
RUN           env GOOS=linux GOARCH="$(printf "%s" "$TARGETPLATFORM" | sed -E 's/^[^/]+\/([^/]+).*/\1/')" go build -v -ldflags "-s -w" \
                -o /dist/boot/bin/http-health ./cmd/http

#######################
# Goello
#######################
# hadolint ignore=DL3006,DL3029
FROM          --platform=$BUILDPLATFORM $BUILDER_BASE                                                                   AS builder-goello

ARG           GIT_REPO=github.com/dubo-dubon-duponey/goello
ARG           GIT_VERSION=6f6c96ef8161467ab25be45fe3633a093411fcf2

WORKDIR       $GOPATH/src/$GIT_REPO
RUN           git clone git://$GIT_REPO .
RUN           git checkout $GIT_VERSION
# hadolint ignore=DL4006
RUN           env GOOS=linux GOARCH="$(printf "%s" "$TARGETPLATFORM" | sed -E 's/^[^/]+\/([^/]+).*/\1/')" go build -v -ldflags "-s -w" \
                -o /dist/boot/bin/goello-server ./cmd/server/main.go

#######################
# Caddy
#######################
# hadolint ignore=DL3006,DL3029
FROM          --platform=$BUILDPLATFORM $BUILDER_BASE                                                                   AS builder-caddy

# This is 2.2.1 (11/16/2020)
ARG           GIT_REPO=github.com/caddyserver/caddy
ARG           GIT_VERSION=385adf5d878939c381c7f73c771771d34523a1a7

WORKDIR       $GOPATH/src/$GIT_REPO
RUN           git clone https://$GIT_REPO .
RUN           git checkout $GIT_VERSION

# hadolint ignore=DL4006
RUN           env GOOS=linux GOARCH="$(printf "%s" "$TARGETPLATFORM" | sed -E 's/^[^/]+\/([^/]+).*/\1/')" go build -v -ldflags "-s -w" \
                -o /dist/boot/bin/caddy ./cmd/caddy

#######################
# Rudder transformer
#######################
# hadolint ignore=DL3006,DL3029
FROM          --platform=$BUILDPLATFORM $BUILDER_BASE                                                                   AS builder-main-transformer

# XXX node-gyp is bollocks
ENV           USER=root
RUN           mkdir -p /tmp/.npm-global
ENV           PATH=/tmp/.npm-global/bin:$PATH
ENV           NPM_CONFIG_PREFIX=/tmp/.npm-global

ARG           GIT_REPO=github.com/rudderlabs/rudder-transformer
# XXX first working set
#ARG           GIT_VERSION=e9578cbb0b5f9dd85e8c63fb53539e1c27997e80
# Nov, 16, 2020
ARG           GIT_VERSION=cfef63a21fb0dbc3355bb3843fd24940e3296d8e

WORKDIR       $GOPATH/src/$GIT_REPO
RUN           git clone git://$GIT_REPO .
RUN           git checkout $GIT_VERSION
RUN           npm install --production
RUN           mkdir -p /dist/boot/bin
RUN           mv "$GOPATH/src/$GIT_REPO" /dist/boot/bin/

#######################
# Builder assemble
#######################
# hadolint ignore=DL3006
FROM          $BUILDER_BASE                                                                                             AS builder-assembly-transformer

COPY          --from=builder-healthcheck  /dist/boot/bin /dist/boot/bin
COPY          --from=builder-caddy        /dist/boot/bin /dist/boot/bin
COPY          --from=builder-goello       /dist/boot/bin /dist/boot/bin

COPY          --from=builder-main-transformer /dist/boot/bin /dist/boot/bin

RUN           chmod 555 /dist/boot/bin/*; \
              epoch="$(date --date "$BUILD_CREATED" +%s)"; \
              find /dist/boot/bin -newermt "@$epoch" -exec touch --no-dereference --date="@$epoch" '{}' +;

# hadolint ignore=DL3006
FROM          $RUNTIME_BASE                                                                                             AS transformer

USER          root

RUN           apt-get update -qq          && \
              apt-get install -qq --no-install-recommends \
                nodejs=10.21.0~dfsg-1~deb10u1 && \
              apt-get -qq autoremove      && \
              apt-get -qq clean           && \
              rm -rf /var/lib/apt/lists/* && \
              rm -rf /tmp/*               && \
              rm -rf /var/tmp/*

USER          dubo-dubon-duponey

COPY          --from=builder-assembly-transformer --chown=$BUILD_UID:root /dist .

EXPOSE        4000

VOLUME        /data

# mDNS
ENV           MDNS_NAME="Fancy Rudder Transformer Service Name"
ENV           MDNS_HOST="rudder-transformer"
ENV           MDNS_TYPE=_http._tcp

# Authentication
ENV           USERNAME="dubo-dubon-duponey"
ENV           PASSWORD="base64_bcrypt_encoded_use_caddy_hash_password_to_generate"
ENV           REALM="My precious rudder transformer"

# Log level and port
ENV           LOG_LEVEL=info
ENV           PORT=4000
ENV           INTERNAL_PORT=9090

ENV           HEALTHCHECK_URL=http://127.0.0.1:4000/

HEALTHCHECK   --interval=30s --timeout=30s --start-period=10s --retries=1 CMD http-health || exit 1

# ENTRYPOINT    ["node", "./rudder-transformer/index.js"]
