# 開発環境の API の説明画面(http://localhost:8082)。
#
# compose のサービス api-docs がこのイメージを使い、backend/api/openapi.yaml を読み取りだけで差し込んで、
# 環境変数 SWAGGER_JSON で表示する。本番のイメージには入れない。
#
# compose.yaml に image: を直書きせず Dockerfile に置いているのは、Dependabot の
# docker の項目が docker/*/Dockerfile を対象にしており、直書きのままでは
# 更新の経路が無いため。土台のイメージを差し替えるだけで中身は足さない。
FROM swaggerapi/swagger-ui:v5.34.1@sha256:59ee9021a8884437c7fd8aae79e0a46ee6b6dd3afd7f24a587c4501585fde53b
