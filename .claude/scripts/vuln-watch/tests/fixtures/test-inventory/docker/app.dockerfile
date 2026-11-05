# syntax=docker/dockerfile:1
FROM --platform=$BUILDPLATFORM eclipse-temurin:21-jdk@sha256:1111111111111111111111111111111111111111111111111111111111111111 AS builder
RUN echo build

FROM builder AS test
RUN echo test

FROM debian:trixie-slim@sha256:2222222222222222222222222222222222222222222222222222222222222222
COPY --from=builder /app /app

FROM scratch AS empty
