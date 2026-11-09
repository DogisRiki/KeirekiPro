# Go 版の backend の開発環境と品質チェックのイメージ。
#
# compose のサービス backend-go と、run-check.sh の領域 backend-go がこのイメージを使う。
# 入れるもの:
#   - golangci-lint: 静的な検査と書式の検査。版は .github/workflows/ci.yaml の backend-go の仕事と
#     そろえる(版を上げるときは2か所を同じ PR で上げる)
#   - poppler-utils: Java 版と Go 版の PDF を比べる検査(pdftotext pdffonts pdftoppm)
#   - Docker の CLI: 比べる検査と結合テストが dind の Docker を使う
#   - chromium と fonts-noto-cjk: PDF を作る部品の単体テストと、開発サーバの PDF の出力
# Go のモジュールとビルドのキャッシュは /cache に置き、compose のボリューム backend-go-cache を差し込む。
FROM docker:29-cli@sha256:2357639ad1ea7d0194134bf3292622fd4e562483966ed674e5d7c945b5f3b28d AS docker-cli

FROM golang:1.27.3-trixie@sha256:af1bfc2614ebb1dbd31af514b78740fd678850e76498762b425ecee4c5c6ea80

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        chromium \
        fonts-noto-cjk \
        poppler-utils \
    && rm -rf /var/lib/apt/lists/*

COPY --from=docker-cli /usr/local/bin/docker /usr/local/bin/docker

# golangci-lint は、公式が勧める、版を固定した実行ファイルで入れる(go tool では入れない)。
# 配布物は、公式の checksums.txt に載った SHA-256 と照らしてから入れる。
ARG GOLANGCI_LINT_VERSION=2.15.0
RUN set -eux; \
    arch="$(dpkg --print-architecture)"; \
    case "$arch" in \
        amd64) sum=9b7fe6a6bf6334b98decf8d86b11415ea7889afdabdd1959fdce23af2a9ebcea ;; \
        arm64) sum=b4d8f17068b35ee6060cc2f69a16fb48740d706fbba81661c318649c114a6998 ;; \
        *) echo "golangci-lint の配布物が無い CPU: $arch" >&2; exit 1 ;; \
    esac; \
    name="golangci-lint-${GOLANGCI_LINT_VERSION}-linux-${arch}"; \
    curl -fsSLo /tmp/golangci-lint.tar.gz \
        "https://github.com/golangci/golangci-lint/releases/download/v${GOLANGCI_LINT_VERSION}/${name}.tar.gz"; \
    echo "${sum}  /tmp/golangci-lint.tar.gz" | sha256sum -c -; \
    tar -xzf /tmp/golangci-lint.tar.gz -C /tmp; \
    install -m 0755 "/tmp/${name}/golangci-lint" /usr/local/bin/golangci-lint; \
    rm -rf /tmp/golangci-lint.tar.gz "/tmp/${name}"

ENV GOMODCACHE=/cache/mod \
    GOCACHE=/cache/build \
    GOLANGCI_LINT_CACHE=/cache/golangci-lint

WORKDIR /app
