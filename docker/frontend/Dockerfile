FROM node:22.22.2-bookworm-slim

USER root

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
    git \
    openssh-client \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/* \
    && echo "alias git='git -C /workspace/keirekipro'" >> /home/node/.bashrc \
    && chown node:node /home/node/.bashrc

USER node

RUN git config --global --add safe.directory /workspace/keirekipro

WORKDIR /home/node/app

RUN mkdir node_modules
