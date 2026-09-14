FROM node:24.21.0-bookworm-slim@sha256:2fe369e969550cde8e867afc3fe370b260140cab4a23d467074295b42163d553

RUN corepack enable && corepack prepare pnpm@11.10.0 --activate

USER node
WORKDIR /home/node/app

RUN mkdir node_modules
