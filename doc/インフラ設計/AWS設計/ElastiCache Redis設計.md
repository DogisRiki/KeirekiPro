# ElastiCache Redis設計書

## 1. キャッシュ設計

### 1.1 基本設定

| 項目 | 設定値 |
|------|--------|
| 種類 | ElastiCache Serverless |
| キャッシュ名 | keirekipro-cache |
| エンジン | Valkey |
| メジャーエンジンバージョン | 8 |
| ポート | 6379（読み書き）、6380（読み取り専用） |
| 接続の形 | クラスターの形（backend はシークレットの `spring.data.redis.cluster.nodes` で接続する） |

### 1.2 使用量の上限

| 項目 | 設定値 |
|------|--------|
| 保存量の上限 | 1GB |
| 処理の量の上限 | 毎秒 1000 ECPU |
| 最低の使用量 | 設定しない（設定すると、使わなくてもその分が課金されるため） |

- 保存量が上限に達すると、ElastiCache Serverless は期限付きのキーから追い出す。backend のキーはどれも期限付きなので、書き込みは止まらない
- 要求が毎秒 1000 ECPU を超えると、ElastiCache Serverless は要求を絞る

### 1.3 ネットワーク設定

| 項目 | 設定値 |
|------|--------|
| VPC | keirekipro-vpc |
| サブネット | keirekipro-private-1a, keirekipro-private-1c |
| セキュリティグループ | keirekipro-redis-sg（ポート 6379〜6380 を keirekipro-ecs-sg からだけ許す） |

※ ElastiCache Serverless は、サブネットグループとパラメータグループを使わない。サブネットはキャッシュに直接指定する。

## 2. 認証設定（RBAC）

### 2.1 ユーザー

| 項目 | 設定値 |
|------|--------|
| ユーザーID | keirekipro-app |
| ユーザー名 | keirekipro-app |
| エンジン | valkey |
| アクセス文字列 | on ~* &* +@all |
| 認証の方式 | パスワード |
| パスワード | Secrets Managerで管理（keirekipro/redis の redis-password） |

### 2.2 ユーザーグループ

| 項目 | 設定値 |
|------|--------|
| ユーザーグループID | keirekipro-app |
| エンジン | valkey |
| 所属するユーザー | keirekipro-app だけ（default のユーザーは入れない） |
| 付け先 | keirekipro-cache |

## 3. 暗号化設定

| 項目 | 設定値 |
|------|--------|
| 転送中の暗号化 | 有効（ElastiCache Serverless では常に有効。TLS で接続する） |
| 保管時の暗号化 | 有効（AWS が持つ鍵を使う。`kms_key_id` は設定しない） |

## 4. メンテナンス設定

| 項目 | 設定値 |
|------|--------|
| メンテナンスウィンドウ | なし（ElastiCache Serverless は、AWS が止めずに更新する） |

## 5. バックアップ設定

| 項目 | 設定値 |
|------|--------|
| 自動バックアップ | 無効（スナップショットの設定をしない） |

※ キャッシュの中身は、作り直すと消える。消えるのは、ログインの状態、パスワードの再設定の印、二段階認証のコード、OIDC の途中の情報で、どれも利用者がログインし直せば作り直される。

## 6. モニタリング設定

| 項目 | 設定値 |
|------|--------|
| メモリのアラーム | keirekipro-redis-memory-high（BytesUsedForCache が 300MB 以上。CloudWatch設計書を参照） |
| CloudWatch Logs | 無効 |

## 7. Secrets Manager連携

| シークレット名 | 用途 |
|---------------|------|
| keirekipro/redis | キャッシュの接続情報（redis-host, redis-port, redis-password, spring.data.redis.cluster.nodes, spring.data.redis.username） |
