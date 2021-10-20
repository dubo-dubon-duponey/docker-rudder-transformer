ARG           FROM_REGISTRY=ghcr.io/dubo-dubon-duponey

ARG           FROM_IMAGE_BUILDER=base:builder-bullseye-2021-10-15@sha256:1609d1af44c0048ec0f2e208e6d4e6a525c6d6b1c0afcc9d71fccf985a8b0643
ARG           FROM_IMAGE_AUDITOR=base:auditor-bullseye-2021-10-15@sha256:2c95e3bf69bc3a463b00f3f199e0dc01cab773b6a0f583904ba6766b3401cb7b
ARG           FROM_IMAGE_RUNTIME=base:runtime-bullseye-2021-10-15@sha256:5c54594a24e3dde2a82e2027edd6d04832204157e33775edc66f716fa938abba
ARG           FROM_IMAGE_TOOLS=tools:linux-bullseye-2021-10-15@sha256:4de02189b785c865257810d009e56f424d29a804cc2645efb7f67b71b785abde

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
ARG           GIT_REPO=github.com/rudderlabs/rudder-transformer
ARG           GIT_VERSION=1dca690
ARG           GIT_COMMIT=1dca69062748a2491e39a437009ad1e485c74d07

WORKDIR       $GOPATH/src/$GIT_REPO
RUN           git clone --recurse-submodules git://"$GIT_REPO" . && git checkout "$GIT_COMMIT"
RUN           npm install --production
RUN           mkdir -p /dist/boot/bin
RUN           mv "$GOPATH/src/$GIT_REPO" /dist/boot/bin/

#######################
# Builder assemble
#######################
FROM          --platform=$BUILDPLATFORM $FROM_REGISTRY/$FROM_IMAGE_AUDITOR                                              AS builder-assembly-transformer

COPY          --from=builder-main-transformer /dist/boot      /dist/boot

COPY          --from=builder-tools  /boot/bin/goello-server-ng  /dist/boot/bin
COPY          --from=builder-tools  /boot/bin/caddy          /dist/boot/bin
COPY          --from=builder-tools  /boot/bin/http-health    /dist/boot/bin

RUN           setcap 'cap_net_bind_service+ep' /dist/boot/bin/caddy

RUN           chmod 555 /dist/boot/bin/*; \
              epoch="$(date --date "$BUILD_CREATED" +%s)"; \
              find /dist/boot -newermt "@$epoch" -exec touch --no-dereference --date="@$epoch" '{}' +;

# Replace with copy from node image
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
                nodejs=12.22.5~dfsg-2~11u1 && \
              apt-get -qq autoremove      && \
              apt-get -qq clean           && \
              rm -rf /var/lib/apt/lists/* && \
              rm -rf /tmp/*               && \
              rm -rf /var/tmp/*

USER          dubo-dubon-duponey

COPY          --from=builder-assembly-transformer --chown=$BUILD_UID:root /dist /

EXPOSE        4000

VOLUME        /data

### Front server configuration
# Port to use
ENV           PORT=443
ENV           PORT_HTTP=80
EXPOSE        443
EXPOSE        80
# Log verbosity for
ENV           LOG_LEVEL="warn"
# Domain name to serve
ENV           DOMAIN="$_SERVICE_NICK.local"
ENV           ADDITIONAL_DOMAINS=""

# Whether the server should behave as a proxy (disallows mTLS)
ENV           SERVER_NAME="DuboDubonDuponey/1.0 (Caddy/2) [$_SERVICE_NICK]"

# Control wether tls is going to be "internal" (eg: self-signed), or alternatively an email address to enable letsencrypt
ENV           TLS_MODE="internal"
# 1.2 or 1.3
ENV           TLS_MIN=1.2
# Either require_and_verify or verify_if_given
ENV           MTLS_ENABLED=true
ENV           MTLS_MODE="verify_if_given"
ENV           MTLS_TRUST="/certs/pki/authorities/local/root.crt"
# Issuer name to appear in certificates
#ENV           TLS_ISSUER="Dubo Dubon Duponey"
# Either disable_redirects or ignore_loaded_certs if one wants the redirects
ENV           TLS_AUTO=disable_redirects

ENV           AUTH_ENABLED=false
# Realm in case access is authenticated
ENV           AUTH_REALM="My Precious Realm"
# Provide username and password here (call the container with the "hash" command to generate a properly encrypted password, otherwise, a random one will be generated)
ENV           AUTH_USERNAME="dubo-dubon-duponey"
ENV           AUTH_PASSWORD="cmVwbGFjZV9tZV93aXRoX3NvbWV0aGluZwo="

### mDNS broadcasting
# Type to advertise
ENV           MDNS_TYPE="_$_SERVICE_TYPE._tcp"
# Name is used as a short description for the service
ENV           MDNS_NAME="$_SERVICE_NICK mDNS display name"
# The service will be annonced and reachable at $MDNS_HOST.local (set to empty string to disable mDNS announces entirely)
ENV           MDNS_HOST="$_SERVICE_NICK"
# Also announce the service as a workstation (for example for the benefit of coreDNS mDNS)
ENV           MDNS_STATION=true

ENV           HEALTHCHECK_URL=http://127.0.0.1:10000/

HEALTHCHECK   --interval=120s --timeout=30s --start-period=10s --retries=1 CMD http-health || exit 1

# ENTRYPOINT    ["node", "./rudder-transformer/index.js"]
