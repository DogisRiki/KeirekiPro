# 開発環境の API の説明画面(http://localhost:8082)。
#
# compose のサービス api-docs がこのイメージを使い、backend/api/openapi.yaml を読み取りだけで差し込んで、
# 環境変数 SWAGGER_JSON で表示する。本番のイメージには入れない。
#
# compose.yaml に image: を直書きせず Dockerfile に置いているのは、Dependabot の
# docker の項目が docker/*/Dockerfile を対象にしており、直書きのままでは
# 更新の経路が無いため。土台のイメージを差し替えるだけで中身は足さない。
FROM swaggerapi/swagger-ui:v5.35.1@sha256:cd314c0a167841dc1c9869ff2df6f949e2e7fa63f8b77f610b7e75878ac2da4e
