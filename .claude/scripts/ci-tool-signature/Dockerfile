# CI の道具の版を配布元の署名で確かめるときに、gpg を動かす1回きりのコンテナのイメージ。
# verify-ci-tool.sh が docker build で作り、docker run --rm で gpg を動かす。
# 開発者の PC に gpg が無くても、同じ版の gpg で確かめられるようにするため。
#
# Debian の slim のイメージを digest で固定する。digest はイメージの中身から計算した値で、
# 中身が変わると値も変わる。タグだけで書くと、同じタグのまま中身が替わっても気づけない。
FROM debian:trixie-slim@sha256:f6b08b09a05725f9431502d3b5714f5c4576e82c1a84fa1debe0c24a7e0c3ec4

RUN apt-get update \
    && apt-get install -y --no-install-recommends gnupg \
    && rm -rf /var/lib/apt/lists/*
