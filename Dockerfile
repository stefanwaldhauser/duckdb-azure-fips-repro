# Minimal, non-proprietary reproduction of:
# "azure extension's TLS fails when the host libcrypto has activated OpenSSL's FIPS provider"
#
# Base: debian:13-slim + openssl-provider-fips from Debian repos + Node 22 from NodeSource.
FROM debian:13-slim
ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update -qq \
 && apt-get install -y -qq --no-install-recommends \
      ca-certificates curl gnupg xz-utils openssl openssl-provider-fips \
 && curl -fsSL https://deb.nodesource.com/setup_22.x | bash - >/dev/null \
 && apt-get install -y -qq --no-install-recommends nodejs \
 && rm -rf /var/lib/apt/lists/*

# Debian ships fips.so but no fipsmodule.cnf — provision one.
RUN openssl fipsinstall \
      -out /etc/ssl/fipsmodule.cnf \
      -module /usr/lib/x86_64-linux-gnu/ossl-modules/fips.so

COPY fips.cnf /etc/ssl/fips.cnf
ENV OPENSSL_CONF=/etc/ssl/fips.cnf
ENV OPENSSL_MODULES=/usr/lib/x86_64-linux-gnu/ossl-modules

WORKDIR /work
RUN npm --os=linux --cpu=x64 --libc=glibc --silent install @duckdb/node-api@1.5.5-r.5
COPY repro.js /work/repro.js
CMD ["node", "/work/repro.js"]
