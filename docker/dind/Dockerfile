# Testcontainers用のDocker-in-Docker。
#
# compose.yaml に image: を直書きせずDockerfileに置いているのは、Dependabotの
# dockerレーンが docker/*/Dockerfile を対象にしており、直書きのままでは
# 更新経路が存在しないため。ベースイメージを差し替えるだけで中身は追加しない。
FROM docker:29-dind@sha256:7dcdfc4a20246236f558175182ccace1eb15a41bd3eb119dd2284f393498b7c1
