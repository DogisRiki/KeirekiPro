# Testcontainers用のDocker-in-Docker。
#
# compose.yaml に image: を直書きせずDockerfileに置いているのは、Dependabotの
# dockerレーンが docker/*/Dockerfile を対象にしており、直書きのままでは
# 更新経路が存在しないため。ベースイメージを差し替えるだけで中身は追加しない。
FROM docker:29-dind@sha256:9e79b879b177fbd72c34376a3dd3d91747da5db49e1f560f76aea59561471977
