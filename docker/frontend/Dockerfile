FROM node:22.22.2-bookworm-slim

RUN corepack enable && corepack prepare pnpm@11.5.0 --activate

USER node
WORKDIR /home/node/app

RUN mkdir node_modules
