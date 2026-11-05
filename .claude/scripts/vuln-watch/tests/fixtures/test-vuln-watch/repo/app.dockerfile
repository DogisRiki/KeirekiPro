FROM eclipse-temurin:21-jdk AS builder
RUN echo build

FROM debian:trixie-slim
COPY --from=builder /app /app
