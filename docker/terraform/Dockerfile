FROM hashicorp/terraform:1.14.3

COPY --from=ghcr.io/terraform-linters/tflint:v0.60.0 /usr/local/bin/tflint /usr/local/bin/tflint

RUN apk add --no-cache \
    python3 \
    py3-pip \
    git \
    && pip3 install --no-cache-dir --break-system-packages checkov

WORKDIR /workspace

COPY terraform/.tflint.hcl /root/.tflint.hcl
RUN tflint --init --config /root/.tflint.hcl

ENTRYPOINT []
CMD ["sh"]
