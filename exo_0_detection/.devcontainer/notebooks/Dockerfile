FROM mcr.microsoft.com/devcontainers/base:ubuntu-22.04

USER root

# Jammy amd64 archives do not publish armhf packages; use Ubuntu ports for ARM.
RUN dpkg --add-architecture armhf \
    && printf '%s\n' \
        'deb [arch=amd64] http://archive.ubuntu.com/ubuntu jammy main restricted universe multiverse' \
        'deb [arch=amd64] http://archive.ubuntu.com/ubuntu jammy-updates main restricted universe multiverse' \
        'deb [arch=amd64] http://archive.ubuntu.com/ubuntu jammy-backports main restricted universe multiverse' \
        'deb [arch=amd64] http://security.ubuntu.com/ubuntu jammy-security main restricted universe multiverse' \
        > /etc/apt/sources.list \
    && printf '%s\n' \
        'deb [arch=armhf] http://ports.ubuntu.com/ubuntu-ports jammy main restricted universe multiverse' \
        'deb [arch=armhf] http://ports.ubuntu.com/ubuntu-ports jammy-updates main restricted universe multiverse' \
        'deb [arch=armhf] http://ports.ubuntu.com/ubuntu-ports jammy-backports main restricted universe multiverse' \
        'deb [arch=armhf] http://ports.ubuntu.com/ubuntu-ports jammy-security main restricted universe multiverse' \
        > /etc/apt/sources.list.d/armhf.list \
    && apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        build-essential \
        cmake \
        ninja-build \
        git \
        curl \
        wget \
        ca-certificates \
        xz-utils \
        unzip \
        zip \
        file \
        binutils \
        pkg-config \
        python3 \
        python3-dev \
        python3-pip \
        python3-venv \
        libpython3.10-dev:armhf \
    && test -f /usr/include/arm-linux-gnueabihf/python3.10/pyconfig.h \
    && rm -rf /var/lib/apt/lists/*

# Use Ubuntu's Python 3.10 in an isolated environment for the build tools.
RUN /usr/bin/python3 -m venv /opt/notebooks-venv \
    && /opt/notebooks-venv/bin/python3 -m pip install --no-cache-dir \
        numpy==1.21.5 \
        pybind11 \
        wheel \
        setuptools \
    && chown -R vscode:vscode /opt/notebooks-venv

ENV PATH="/opt/notebooks-venv/bin:${PATH}"

USER vscode
