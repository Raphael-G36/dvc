
# Base Debian image
FROM mcr.microsoft.com/vscode/devcontainers/base:debian

# Update packages and install required tools
RUN apt-get update && \
    apt-get install -y \
    pipx \
    zsh \
    curl \
    git \
    build-essential && \
    rm -rf /var/lib/apt/lists/*

# Set zsh as the default shell
ENV SHELL=/usr/bin/zsh

# Switch to vscode user
USER vscode

# Install Rust
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y

ENV PATH="/home/vscode/.cargo/bin:${PATH}"

# Install solc-select
RUN pipx install solc-select

# Install Foundry
RUN curl -L https://foundry.paradigm.xyz | bash

ENV PATH="/home/vscode/.foundry/bin:${PATH}"

RUN foundryup

# Return to vscode user
USER vscode