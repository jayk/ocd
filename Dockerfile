# Dockerfile.opencode
FROM debian:bookworm-slim

RUN apt-get update \
    && apt-get install -y --no-install-recommends curl ca-certificates 

RUN curl -fsSL https://deb.nodesource.com/setup_22.x | bash - \
    && apt-get install -y --no-install-recommends nodejs \
    && npm --version \
    && node --version \
    && npm install -g dtl-js \
    && rm -rf /var/lib/apt/lists/* 

# Base packages needed for Node install and OpenCode usage
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        bash \
        vim \
        ripgrep \
        diffutils \
        fd-find \
        tree \
        xz-utils \
        zip \
        unzip \
        python3 \
        git \
        procps \
        nano \
        jq \
        make \
        openssh-client \
    && rm -rf /var/lib/apt/lists/*

# Install Node.js 22 (official NodeSource binary distribution)

# Create developer user/group with UID/GID 1000 and HOME=/opt/ocd_dev
RUN groupadd -g 1000 developer \
    && useradd -m -d /opt/ocd_dev -s /bin/bash -u 1000 -g 1000 developer \
    && mkdir -p /opt/ocd_dev \
    && mkdir -p /opt/ocd_dev/.local \
    && mkdir -p /opt/ocd_dev/.config \
    && mkdir -p /opt/ocd_dev/.agents \
    && chown -R developer:developer /opt/ocd_dev

COPY opencode-entrypoint.sh /usr/local/bin/opencode-entrypoint

ENV HOME=/opt/ocd_dev
ENV EDITOR=nano

# Switch to developer for OpenCode install (required)
USER developer
WORKDIR /opt/ocd_dev

# Install OpenCode via official installer
RUN curl -fsSL https://opencode.ai/install | bash

# Ensure OpenCode binaries are reachable
ENV PATH="/opt/ocd_dev/.opencode/bin:/opt/ocd_dev/bin:/opt/ocd_dev/.local/bin:${PATH}"

# Explicit locations for mounted runtime state
ENV XDG_DATA_HOME="/opt/ocd_dev/.opencode/share"
ENV OPENCODE_CONFIG_DIR="/opt/ocd_dev/.opencode/config"

ENTRYPOINT ["/usr/local/bin/opencode-entrypoint"]
# CMD ["/bin/bash", "-c", "opencode"]
