# 比べる検査の AWS の代わり(fakeaws)のイメージ。
#
# 組み立ての文脈は ./backend である。比べる検査の harness が、検査のたびにこのイメージを組み立てる。
#   docker build -f backend/compat/fakeaws/Dockerfile backend
# fakeaws は標準のライブラリだけを使うので、依存のモジュールを取り込まない。

# -----------------------------------------------------------------------------
# 組み立ての工程
# -----------------------------------------------------------------------------
FROM golang:1.27.4-trixie@sha256:f18c3d73a184fb0582828510722e723b63a93f7188d11dd223d9be6f6880e65d AS builder

WORKDIR /src
COPY go.mod go.sum ./
COPY compat/fakeaws compat/fakeaws
RUN CGO_ENABLED=0 go build -tags compat -trimpath -ldflags="-s -w" -o /out/fakeaws ./compat/fakeaws/cmd/fakeaws

# -----------------------------------------------------------------------------
# 実行の工程
# -----------------------------------------------------------------------------
FROM gcr.io/distroless/static-debian13:nonroot@sha256:aafe993665bf6200db38a02c11a9351e782a84b6a45e7f33b6695638c88e3931

COPY --from=builder /out/fakeaws /fakeaws
EXPOSE 4566
ENTRYPOINT ["/fakeaws"]
