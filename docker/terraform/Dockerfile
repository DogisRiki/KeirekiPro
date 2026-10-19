FROM ghcr.io/terraform-linters/tflint:v0.64.0@sha256:1c595f42d794c32c45a6ea8b58655fd66433d4ca3b1bc631c574a48d120bd19f AS tflint

FROM hashicorp/terraform:1.16.6@sha256:bfffc1ded5fbf0a17beaaf22eb4793980abdb19d0761ff6a3a0efb2ab4d9b316

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
RUN tflint --init --config /root/.tflint.hcl

ENTRYPOINT []
CMD ["sh"]
