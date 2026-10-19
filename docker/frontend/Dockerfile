FROM node:24.22.0-bookworm-slim@sha256:a5f4366e834695d5f363b920c104953a535d3a9864d1bdf74566a0ebe01daee5

RUN corepack enable && corepack prepare pnpm@11.10.0 --activate

USER node
WORKDIR /home/node/app

RUN mkdir node_modules
