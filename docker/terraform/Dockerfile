FROM ghcr.io/terraform-linters/tflint:v0.60.0@sha256:cef181224b4a9cea521d8f785d50957ea3215b449e2d97e7793f222e2808d188 AS tflint

FROM hashicorp/terraform:1.16.4@sha256:985cdc6c1d9b0a65b83377f666efd2f740b47f02ac55be1ced3d18f7d3b0e829

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
