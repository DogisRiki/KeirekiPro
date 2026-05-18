FROM eclipse-temurin:21-jdk

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
    git \
    openssh-client \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/* \
    && echo "alias git='git -C /workspace/keirekipro'" >> /root/.bashrc \
    && git config --global --add safe.directory /workspace/keirekipro

COPY ./backend /home/spring/app
WORKDIR /home/spring/app
