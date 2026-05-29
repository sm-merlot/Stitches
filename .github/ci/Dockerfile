FROM ghcr.io/cirruslabs/flutter:stable

# Flutter Linux desktop build dependencies + virtual display for headless tests
RUN apt-get update && apt-get install -y --no-install-recommends \
    clang \
    cmake \
    ninja-build \
    pkg-config \
    libgtk-3-dev \
    libblkid-dev \
    liblzma-dev \
    xvfb \
    && rm -rf /var/lib/apt/lists/*

# Enable Linux desktop target and pre-cache Linux engine artifacts
RUN flutter config --enable-linux-desktop \
    && flutter precache --linux
