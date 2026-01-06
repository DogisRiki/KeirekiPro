FROM eclipse-temurin:21-jdk-alpine
RUN apk add --no-cache bash curl ca-certificates unzip

# VSCode拡張機能を事前ダウンロード
RUN mkdir -p /opt/vscode-extensions && \
    curl -L -o /opt/vscode-extensions/redhat.java-1.50.0.vsix \
    "https://open-vsx.org/api/redhat/java/1.50.0/file/redhat.java-1.50.0.vsix"

COPY ./backend /home/spring/app
WORKDIR /home/spring/app
