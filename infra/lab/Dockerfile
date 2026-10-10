# syntax=docker/dockerfile:1
#
# The lab: one Linux box with the whole "See It" palette, so every lesson's
# observations (tcpdump, strace, ss, /proc, perf, tshark) run the same way on
# a macOS laptop, a Linux laptop and the CI runner.
#
#   just lab                 # interactive shell, repo mounted at /work
#   just see 03/04           # run one lesson's see.sh inside the lab
#
# docker-compose.yml runs this with cap_add [NET_ADMIN, NET_RAW, SYS_PTRACE],
# pid: host and network_mode: host. On Docker Desktop "host" means the Linux
# VM, so run the server you want to observe inside the lab too.
#
# Policy: the core palette must install or the build fails. Everything marked
# OPTIONAL warns and continues, so a missing package never blocks the lab.
FROM ubuntu:24.04

ARG DEBIAN_FRONTEND=noninteractive
# Pinned fallbacks, used only when apt cannot provide a tool.
ARG K6_VERSION=v1.0.0
ARG HEY_URL_AMD64=https://hey-release.s3.us-east-2.amazonaws.com/hey_linux_amd64
# Toolchains so demos/<mm>/<ll>/run.sh and see.sh can run all three ports in
# the lab. Go matches apps/go/go.mod; Rust tracks stable like CI.
ARG GO_VERSION=1.23.12
ARG RUST_TOOLCHAIN=stable

ENV LANG=C.UTF-8 \
    TZ=Etc/UTC \
    PATH=/usr/local/go/bin:/root/go/bin:/root/.cargo/bin:$PATH

# tshark asks whether non-root users may capture. Answer before installing;
# the lab runs as root anyway.
RUN echo "wireshark-common wireshark-common/install-setuid boolean false" | debconf-set-selections

# ---- Core palette (required) -------------------------------------------------
RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates curl gnupg jq less vim-tiny xxd file \
        tcpdump strace iproute2 iputils-ping dnsutils lsof procps psmisc ethtool \
        tshark wireshark-common \
        netcat-openbsd conntrack iptables \
        gdb python3 python3-pip python3-venv \
        postgresql-client redis-tools openssl \
        build-essential git unzip \
    && rm -rf /var/lib/apt/lists/*

# ---- OPTIONAL apt packages ---------------------------------------------------
# All present in Ubuntu 24.04 (amd64 + arm64) as of 2026-10; fallbacks below
# cover the ones a lesson cannot live without.
RUN apt-get update \
    && for pkg in ltrace wrk hey just linux-tools-generic; do \
         apt-get install -y --no-install-recommends "$pkg" \
           || echo "lab: OPTIONAL apt package '$pkg' unavailable" >&2; \
       done \
    && rm -rf /var/lib/apt/lists/*

# perf: linux-tools-generic installs /usr/lib/linux-tools/<kver>/perf behind a
# wrapper that refuses to run on any other kernel, and Docker Desktop's kernel
# never matches. Point `perf` straight at the real binary.
RUN p="$(ls -1 /usr/lib/linux-tools/*/perf 2>/dev/null | tail -n 1)"; \
    if [ -n "$p" ]; then ln -sf "$p" /usr/local/bin/perf; \
    else echo "lab: OPTIONAL perf unavailable" >&2; fi

# wrk fallback: build from source.
RUN command -v wrk >/dev/null || { \
      git clone --depth 1 https://github.com/wg/wrk.git /tmp/wrk \
      && make -C /tmp/wrk -j"$(nproc)" \
      && install -m 0755 /tmp/wrk/wrk /usr/local/bin/wrk; \
      rm -rf /tmp/wrk; \
      command -v wrk >/dev/null || echo "lab: OPTIONAL wrk unavailable" >&2; }

# hey fallback: upstream only publishes an amd64 release binary.
RUN command -v hey >/dev/null || { \
      if [ "$(dpkg --print-architecture)" = "amd64" ]; then \
        curl -fsSL "$HEY_URL_AMD64" -o /usr/local/bin/hey && chmod 0755 /usr/local/bin/hey; \
      fi; \
      command -v hey >/dev/null || echo "lab: OPTIONAL hey unavailable" >&2; }

# just fallback: official installer.
RUN command -v just >/dev/null || { \
      curl --proto '=https' --tlsv1.2 -fsSL https://just.systems/install.sh \
        | bash -s -- --to /usr/local/bin; \
      command -v just >/dev/null || echo "lab: OPTIONAL just unavailable" >&2; }

# k6: Grafana's official apt repo, falling back to the pinned GitHub release.
# (As of 2026-10 dl.k6.io ships amd64 only, so arm64 hosts use the release.)
RUN set -u; \
    if curl -fsSL https://dl.k6.io/key.gpg | gpg --dearmor -o /usr/share/keyrings/k6-archive-keyring.gpg \
       && echo "deb [signed-by=/usr/share/keyrings/k6-archive-keyring.gpg] https://dl.k6.io/deb stable main" \
            > /etc/apt/sources.list.d/k6.list \
       && apt-get update \
       && apt-get install -y --no-install-recommends k6; then \
      echo "lab: k6 from dl.k6.io"; \
    else \
      rm -f /etc/apt/sources.list.d/k6.list; \
      arch="$(dpkg --print-architecture)"; \
      curl -fsSL "https://github.com/grafana/k6/releases/download/${K6_VERSION}/k6-${K6_VERSION}-linux-${arch}.tar.gz" \
        | tar -xz -C /tmp \
        && install -m 0755 "/tmp/k6-${K6_VERSION}-linux-${arch}/k6" /usr/local/bin/k6 \
        || echo "lab: OPTIONAL k6 unavailable" >&2; \
    fi; \
    rm -rf /var/lib/apt/lists/* /tmp/k6-*

# py-spy: not packaged by Ubuntu. PEP 668 needs --break-system-packages for a
# system-wide pip install; acceptable in a throwaway lab image.
RUN pip3 install --no-cache-dir --break-system-packages py-spy \
    || echo "lab: OPTIONAL py-spy unavailable" >&2

# ---- Toolchains for the three ports -----------------------------------------
COPY --from=ghcr.io/astral-sh/uv:0.11.28 /uv /uvx /usr/local/bin/

RUN arch="$(dpkg --print-architecture)" \
    && curl -fsSL "https://go.dev/dl/go${GO_VERSION}.linux-${arch}.tar.gz" | tar -xz -C /usr/local \
    && go version

RUN curl --proto '=https' --tlsv1.2 -fsSL https://sh.rustup.rs \
      | sh -s -- -y --profile minimal --default-toolchain "${RUST_TOOLCHAIN}" \
    && rustc --version

# Keep build output out of the bind-mounted repo: macOS and Linux artifacts in
# the same target/ or .venv/ would fight.
ENV CARGO_TARGET_DIR=/root/.cache/cargo-target \
    UV_PROJECT_ENVIRONMENT=/root/.cache/uv-venv \
    GOFLAGS=-buildvcs=false

# The repo is bind-mounted and owned by the host user; let root's git use it.
RUN git config --system --add safe.directory '*'

WORKDIR /work
CMD ["bash"]
