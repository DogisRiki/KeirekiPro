---
description: devサーバを起動し、Playwright MCPで変更対象の画面を実際に操作してコンソールエラーとスクリーンショットを確認する。UI変更時の一次スクリーニング。
---

# verify-ui

## Job

UI変更を実画面で検証する。人間が触る前の一次スクリーニング
(人間の体験検証はデプロイ前のローカル確認で行われる。ここで拾えるものは先に拾う)。

## Steps

1. devサーバを起動する(既に起動済みなら再利用):

```
docker compose exec -d -w /home/spring/app backend ./gradlew bootRun --args=--spring.profiles.active=dev
```

```
docker compose exec -d -u node -w /home/node/app frontend pnpm run dev
```

   backendは `http://localhost:8080/actuator/health` が200になるまで待つ。

2. Playwright MCPで `http://host.docker.internal:5173`(コンテナ内から)または `http://localhost:5173` を開き、**変更した画面**へ遷移する。

3. 変更したコントロールを実際に操作する(入力・クリック・ドラッグ等)。状態変化を前後のスクリーンショットで記録する。

4. ブラウザコンソールを確認する: **新規のエラー・警告が0件**であること。

5. 変更がレスポンシブ表示に影響する場合はビューポートを変えて再確認する。

## Rules

- スクリーンショットは「操作前」「操作後」の両方を取得する
- コンソールエラーが出たら、それを修正してから再検証する(握りつぶさない)
- 検証後、自分が起動したdevサーバのプロセスを放置してよい(常駐開発サーバのため)

## Report

```
verify-ui(対象: <画面名>):
- 画面表示     -> OK/NG
- 操作確認     -> OK/NG (操作内容)
- コンソール   -> エラー0 / エラーあり(内容)
- スクリーンショット -> 添付
```
