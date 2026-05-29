FROM ghcr.io/cirruslabs/flutter:stable

# Flutter Linux desktop deps + headless display
RUN apt-get update && apt-get install -y --no-install-recommends \
    clang \
    cmake \
    ninja-build \
    pkg-config \
    libgtk-3-dev \
    libblkid-dev \
    liblzma-dev \
    xvfb \
    nodejs \
    git \
    curl \
    && rm -rf /var/lib/apt/lists/*

# GitHub CLI (used by workflow status-reporting steps)
RUN curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
        | dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg && \
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
        | tee /etc/apt/sources.list.d/github-cli.list > /dev/null && \
    apt-get update && apt-get install -y --no-install-recommends gh && \
    rm -rf /var/lib/apt/lists/*

# Enable Linux desktop target and pre-cache Linux engine artifacts
RUN flutter config --enable-linux-desktop \
    && flutter precache --linux
