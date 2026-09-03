# S3・Secrets Manager・SES のローカルエミュレータ。
#
# compose.yaml に image: を直書きせずDockerfileに置いているのは、Dependabotの
# dockerレーンが docker/*/Dockerfile を対象にしており、直書きのままでは
# 更新経路が存在しないため。ベースイメージを差し替えるだけで中身は追加しない。
#
# 2026.3.0 でコミュニティ版とPro版のイメージが統合され、起動に認証トークンが
# 必要になった。非商用利用は無料枠(Hobby)の対象で費用はかからないが、
# LOCALSTACK_AUTH_TOKEN を docker/localstack/.env.local に設定しないと
# 起動時に exit 55 で終了する。取得手順は初期セットアップ手順を参照。
FROM localstack/localstack:2026.8.0@sha256:21fe0a67fe7993a5b0082a29bfc94fce5a15b6622c87b0d98f9df2882a9afca3
