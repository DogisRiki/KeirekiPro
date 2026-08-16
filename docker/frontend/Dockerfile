FROM node:24.16.0-bookworm-slim@sha256:2c87ef9bd3c6a3bd4b472b4bec2ce9d16354b0c574f736c476489d09f560a203

RUN corepack enable && corepack prepare pnpm@11.10.0 --activate

USER node
WORKDIR /home/node/app

RUN mkdir node_modules
