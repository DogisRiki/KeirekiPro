FROM node:24.21.0-bookworm-slim@sha256:0e0ff40c39bc087845bfb27465a0df4ea419520094bc35842ff83dd8cbe6f9b6

RUN corepack enable && corepack prepare pnpm@11.10.0 --activate

USER node
WORKDIR /home/node/app

RUN mkdir node_modules
