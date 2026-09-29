# Testcontainers用のDocker-in-Docker。
#
# compose.yaml に image: を直書きせずDockerfileに置いているのは、Dependabotの
# dockerレーンが docker/*/Dockerfile を対象にしており、直書きのままでは
# 更新経路が存在しないため。ベースイメージを差し替えるだけで中身は追加しない。
FROM docker:29-dind@sha256:3f3c01aaaebf7cce837356b688b7c059a4749f10bd7660dec7c58fc454a283f0
