# ElastiCache Redis設計書

## 1. クラスター設計

### 1.1 基本設定

| 項目 | 設定値 |
|------|--------|
| クラスター名 | keirekipro-redis |
| エンジン | Valkey |
| エンジンバージョン | 8.0 |
| ポート | 6379 |
| パラメータグループ | keirekipro-redis-params |

### 1.2 ノード設計

| 項目 | 設定値 |
|------|--------|
| ノードタイプ | cache.t4g.micro |
| ノード数 | 1 |
| レプリカ数 | 0 |
| クラスターモード | 無効 |
| マルチAZ | 無効 |

### 1.3 ネットワーク設定

| 項目 | 設定値 |
|------|--------|
| VPC | keirekipro-vpc |
| サブネットグループ | keirekipro-redis-subnet-group |
| セキュリティグループ | keirekipro-redis-sg |

## 2. サブネットグループ設計

| 項目 | 設定値 |
|------|--------|
| 名前 | keirekipro-redis-subnet-group |
| 説明 | Subnet group for KeirekiPro Redis |
| VPC | keirekipro-vpc |
| サブネット | keirekipro-private-1a, keirekipro-private-1c |

## 3. パラメータグループ設計

| 項目 | 設定値 |
|------|--------|
| パラメータグループ名 | keirekipro-redis-params |
| ファミリー | valkey8 |

### 3.1 カスタムパラメータ

| パラメータ名 | 設定値 | 説明 |
|-------------|--------|------|
| maxmemory-policy | volatile-lru | メモリ上限到達時の削除ポリシー。TTLが設定されたキーの中から最も長く使われていないものを削除する |
| timeout | 300 | アイドル状態のクライアント接続を切断するまでの秒数。未使用の接続がリソースを占有し続けることを防止する |

## 4. 認証設定

| 項目 | 設定値 |
|------|--------|
| 転送中の暗号化 | 有効 |
| 保管時の暗号化 | 有効 |
| AUTH | 有効 |
| AUTHトークン | Secrets Managerで管理（keirekipro/redis） |

## 5. メンテナンス設定

| 項目 | 設定値 |
|------|--------|
| メンテナンスウィンドウ | Sun:20:00-Sun:21:00 UTC（JST 月05:00-06:00） |
| 自動マイナーバージョンアップグレード | 有効 |

## 6. バックアップ設定

| 項目 | 設定値 |
|------|--------|
| 自動バックアップ | 無効 |
| スナップショット保持期間 | 0日 |

## 7. モニタリング設定

| 項目 | 設定値 |
|------|--------|
| CloudWatch Logs | 無効 |
| Slow Logエクスポート | 無効 |
| Engine Logエクスポート | 無効 |

## 8. Secrets Manager連携

| シークレット名 | 用途 |
|---------------|------|
| keirekipro/redis | Redis接続情報（redis-host, redis-port, redis-password） |
