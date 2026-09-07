FROM hashicorp/terraform:1.16.1@sha256:f4d9594d2c8010c03f0149352682166410c58c21d46344cf256fd5a4b721a011

COPY --from=ghcr.io/terraform-linters/tflint:v0.60.0 /usr/local/bin/tflint /usr/local/bin/tflint

# checkovはバージョンを固定する。固定しないと、新しい版がルールを追加した時点で
# terraformを触る全PRが赤になる(baselineは既知の指摘しか凍結できず、新ルールの
# 指摘は素通りできない)。更新は人間が明示的に行い、増えた指摘を確認してから上げる。
RUN apk add --no-cache \
    python3 \
    py3-pip \
    git \
    && pip3 install --no-cache-dir --break-system-packages checkov==3.2.497

WORKDIR /workspace

COPY terraform/.tflint.hcl /root/.tflint.hcl
RUN tflint --init --config /root/.tflint.hcl

ENTRYPOINT []
CMD ["sh"]
