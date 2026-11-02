FROM node:24.22.2-bookworm-slim@sha256:c86ecead9e55a5210ac1727de38a4ca840bf03dcaf34dc9749addbf383b1920c

RUN corepack enable && corepack prepare pnpm@11.10.0 --activate

USER node
WORKDIR /home/node/app

RUN mkdir node_modules
