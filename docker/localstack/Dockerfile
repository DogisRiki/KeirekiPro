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
FROM localstack/localstack:2026.07.4@sha256:f7b778d03717b58c3adce81a740bfafff5c6f9d639159bbf08da557c9ac1b513
