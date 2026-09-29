# 2FAコード・パスワードリセットトークン・OIDCセッションの一時保存に使うキャッシュ。
#
# 本番(ElastiCache)と同じ製品・同じ系列の Valkey 8.0 を使う(#409)。本番の系列は
# terraform/modules/elasticache/main.tf の engine_version。本番の系列を変えるときは
# ここも合わせる。サービス名(redis)とディレクトリ名は、接続先の名前として
# docker/localstack/init-localstack.sh などから参照されているため変えていない。
#
# compose.yaml に image: を直書きせずDockerfileに置いているのは、Dependabotの
# dockerレーンが docker/*/Dockerfile を対象にしており、直書きのままでは
# 更新経路が存在しないため。ベースイメージを差し替えるだけで中身は追加しない。
FROM valkey/valkey:8.0.11-alpine@sha256:fd348c9b6999ef15719a1d6b43b810ee1bf2068ded2d7ab6f6dd15943841f28b
