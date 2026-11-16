FROM ghcr.io/terraform-linters/tflint:v0.66.0@sha256:65b9944a9274c4989492c1d79998c2801664bf8a55fddb4bd3a9e6d73a006ddc AS tflint

FROM hashicorp/terraform:1.17.2@sha256:6e9c1e647c31a960dc9b59e13272f9111d90010c10b717f77ffb324767660475

COPY --from=tflint /usr/local/bin/tflint /usr/local/bin/tflint

# checkovはバージョンを固定する(requirements.txt)。固定しないと、新しい版がルールを追加した時点で
# terraformを触る全PRが赤になる(baselineは既知の指摘しか凍結できず、新ルールの
# 指摘は素通りできない)。更新はDependabotのPRで届き、増えた指摘はそのPRの
# terraform-staticが赤で示す(赤のPRは自動マージされない)。
COPY docker/terraform/requirements.txt /tmp/requirements.txt
RUN apk add --no-cache \
    python3 \
    py3-pip \
    git \
    && pip3 install --no-cache-dir --break-system-packages -r /tmp/requirements.txt

WORKDIR /workspace

COPY terraform/.tflint.hcl /root/.tflint.hcl
# tflint --init は、ルールの部品の版を GitHub の API に問い合わせる。ログインしない問い合わせは
# IP アドレスごとに1時間60回までで、GitHub Actions のランナーはこの回数をほかの利用者と分け合う。
# そのため、CI は自動で付くトークンを github_token の名前で渡し、ログインして問い合わせる
# (https://github.com/terraform-linters/tflint/blob/master/docs/user-guide/plugins.md の Avoiding rate limiting)。
# トークンはこの RUN の間だけ環境変数に入り、イメージには残らない。トークンを渡さない手元の
# compose のビルドでは、環境変数が空になり、tflint はこれまでどおりログインせずに問い合わせる。
RUN --mount=type=secret,id=github_token,env=GITHUB_TOKEN tflint --init --config /root/.tflint.hcl

ENTRYPOINT []
CMD ["sh"]
