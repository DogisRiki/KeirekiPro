# 比べる検査の Google と GitHub のログインの代わり(fakeoidc)のイメージ。
#
# 組み立ての文脈は ./backend である。比べる検査の harness が、検査のたびにこのイメージを組み立てる。
#   docker build -f backend/compat/fakeoidc/Dockerfile backend
# fakeoidc は標準のライブラリだけを使うので、依存のモジュールを取り込まない。

# -----------------------------------------------------------------------------
# 組み立ての工程
# -----------------------------------------------------------------------------
FROM golang:1.27.3-trixie@sha256:af1bfc2614ebb1dbd31af514b78740fd678850e76498762b425ecee4c5c6ea80 AS builder

WORKDIR /src
COPY go.mod go.sum ./
COPY compat/fakeoidc compat/fakeoidc
RUN CGO_ENABLED=0 go build -tags compat -trimpath -ldflags="-s -w" -o /out/fakeoidc ./compat/fakeoidc/cmd/fakeoidc

# -----------------------------------------------------------------------------
# 実行の工程
# -----------------------------------------------------------------------------
FROM gcr.io/distroless/static-debian13:nonroot@sha256:25ac8f0c3b2334a9eb05452266bd4697864a8c8ef0ef71e5e6480d7f92868329

COPY --from=builder /out/fakeoidc /fakeoidc
EXPOSE 8080
ENTRYPOINT ["/fakeoidc"]
