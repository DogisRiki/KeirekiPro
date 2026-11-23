# 比べる検査の AWS の代わり(fakeaws)のイメージ。
#
# 組み立ての文脈は ./backend である。比べる検査の harness が、検査のたびにこのイメージを組み立てる。
#   docker build -f backend/compat/fakeaws/Dockerfile backend
# fakeaws は標準のライブラリだけを使うので、依存のモジュールを取り込まない。

# -----------------------------------------------------------------------------
# 組み立ての工程
# -----------------------------------------------------------------------------
FROM golang:1.27.4-trixie@sha256:b54b2639de8c1bfe538ec5ffc45f29b1932235ac5f6d63c059853646677112d9 AS builder

WORKDIR /src
COPY go.mod go.sum ./
COPY compat/fakeaws compat/fakeaws
RUN CGO_ENABLED=0 go build -tags compat -trimpath -ldflags="-s -w" -o /out/fakeaws ./compat/fakeaws/cmd/fakeaws

# -----------------------------------------------------------------------------
# 実行の工程
# -----------------------------------------------------------------------------
FROM gcr.io/distroless/static-debian13:nonroot@sha256:8ce6dd87e9823c5b48dcfb2c8604714ccb351ce59607327bcc4957448da279b5

COPY --from=builder /out/fakeaws /fakeaws
EXPOSE 4566
ENTRYPOINT ["/fakeaws"]
