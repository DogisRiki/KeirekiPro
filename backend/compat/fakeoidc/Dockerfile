# 比べる検査の Google と GitHub のログインの代わり(fakeoidc)のイメージ。
#
# 組み立ての文脈は ./backend である。比べる検査の harness が、検査のたびにこのイメージを組み立てる。
#   docker build -f backend/compat/fakeoidc/Dockerfile backend
# fakeoidc は標準のライブラリだけを使うので、依存のモジュールを取り込まない。

# -----------------------------------------------------------------------------
# 組み立ての工程
# -----------------------------------------------------------------------------
FROM golang:1.27.4-trixie@sha256:f18c3d73a184fb0582828510722e723b63a93f7188d11dd223d9be6f6880e65d AS builder

WORKDIR /src
COPY go.mod go.sum ./
COPY compat/fakeoidc compat/fakeoidc
RUN CGO_ENABLED=0 go build -tags compat -trimpath -ldflags="-s -w" -o /out/fakeoidc ./compat/fakeoidc/cmd/fakeoidc

# -----------------------------------------------------------------------------
# 実行の工程
# -----------------------------------------------------------------------------
FROM gcr.io/distroless/static-debian13:nonroot@sha256:8ce6dd87e9823c5b48dcfb2c8604714ccb351ce59607327bcc4957448da279b5

COPY --from=builder /out/fakeoidc /fakeoidc
EXPOSE 8080
ENTRYPOINT ["/fakeoidc"]
