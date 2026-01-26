# Route 53・ACM設計書

## 1. Route 53 ホストゾーン設計

### 1.1 ホストゾーン基本設定

| 項目 | 設定値 |
|------|--------|
| ドメイン名 | keirekipro.click |
| ホストゾーンタイプ | パブリックホストゾーン |
| コメント | KeirekiPro production domain |

### 1.2 ネームサーバー設定

| 項目 | 設定値 |
|------|--------|
| NSレコード | Route 53が自動生成する4つのネームサーバー |
| TTL | 172800秒（48時間） |

## 2. DNSレコード設計

### 2.1 レコード一覧

| レコード名 | タイプ | ルーティング | ターゲット | TTL | 用途 |
|-----------|--------|------------|-----------|-----|------|
| keirekipro.click | NS | シンプル | Route 53 NS | 172800 | ドメイン委任 |
| keirekipro.click | SOA | シンプル | Route 53 SOA | 900 | 権威情報 |
| app.keirekipro.click | A | シンプル | CloudFront（エイリアス） | - | アプリケーションアクセス |
| app.keirekipro.click | AAAA | シンプル | CloudFront（エイリアス） | - | IPv6アクセス |
| api.keirekipro.click | A | シンプル | ALB（エイリアス） | - | APIアクセス（CloudFrontオリジン用） |
| _xxxxxxxx.app.keirekipro.click | CNAME | シンプル | ACM検証値 | 300 | CloudFront用証明書検証 |
| _yyyyyyyy.app.keirekipro.click | CNAME | シンプル | ACM検証値 | 300 | ALB用証明書検証（app） |
| _zzzzzzzz.api.keirekipro.click | CNAME | シンプル | ACM検証値 | 300 | ALB用証明書検証（api） |

### 2.2 Aレコード（CloudFront向けエイリアス）

| 項目 | 設定値 |
|------|--------|
| レコード名 | app.keirekipro.click |
| レコードタイプ | A |
| エイリアス | はい |
| トラフィックのルーティング先 | CloudFrontディストリビューションへのエイリアス |
| ディストリビューション | keirekipro-distribution |
| ルーティングポリシー | シンプルルーティング |
| ターゲットの正常性を評価 | いいえ |

### 2.3 AAAAレコード（CloudFront向けエイリアス・IPv6）

| 項目 | 設定値 |
|------|--------|
| レコード名 | app.keirekipro.click |
| レコードタイプ | AAAA |
| エイリアス | はい |
| トラフィックのルーティング先 | CloudFrontディストリビューションへのエイリアス |
| ディストリビューション | keirekipro-distribution |
| ルーティングポリシー | シンプルルーティング |
| ターゲットの正常性を評価 | いいえ |

### 2.4 Aレコード（ALB向けエイリアス・APIサブドメイン）

| 項目 | 設定値 |
|------|--------|
| レコード名 | api.keirekipro.click |
| レコードタイプ | A |
| エイリアス | はい |
| トラフィックのルーティング先 | Application Load Balancerへのエイリアス |
| ALB | keirekipro-alb |
| ルーティングポリシー | シンプルルーティング |
| ターゲットの正常性を評価 | はい |

## 3. SES用DNSレコード設計

### 3.1 ドメイン認証レコード

| レコード名 | タイプ | 値 | TTL | 用途 |
|-----------|--------|-----|-----|------|
| _amazonses.keirekipro.click | TXT | SESが発行する検証トークン | 300 | SESドメイン認証 |

### 3.2 DKIMレコード

| レコード名 | タイプ | 値 | TTL | 用途 |
|-----------|--------|-----|-----|------|
| {selector1}._domainkey.keirekipro.click | CNAME | SESが発行するDKIM値 | 300 | DKIM署名検証 |
| {selector2}._domainkey.keirekipro.click | CNAME | SESが発行するDKIM値 | 300 | DKIM署名検証 |
| {selector3}._domainkey.keirekipro.click | CNAME | SESが発行するDKIM値 | 300 | DKIM署名検証 |

### 3.3 SPFレコード

| レコード名 | タイプ | 値 | TTL | 用途 |
|-----------|--------|-----|-----|------|
| keirekipro.click | TXT | "v=spf1 include:amazonses.com ~all" | 300 | SPF認証 |

### 3.4 DMARCレコード

| レコード名 | タイプ | 値 | TTL | 用途 |
|-----------|--------|-----|-----|------|
| _dmarc.keirekipro.click | TXT | "v=DMARC1; p=quarantine; rua=mailto:dmarc@keirekipro.click" | 300 | DMARC認証 |

### 3.5 カスタムMAIL FROMレコード

| レコード名 | タイプ | 値 | TTL | 用途 |
|-----------|--------|-----|-----|------|
| mail.keirekipro.click | MX | 10 feedback-smtp.ap-northeast-1.amazonses.com | 300 | カスタムMAIL FROM |
| mail.keirekipro.click | TXT | "v=spf1 include:amazonses.com ~all" | 300 | MAIL FROM用SPF |

## 4. ACM証明書設計

### 4.1 証明書一覧

| 用途 | リージョン | ドメイン名 | 検証方法 |
|------|-----------|-----------|---------|
| CloudFront用 | us-east-1 | app.keirekipro.click | DNS検証 |
| ALB用（app） | ap-northeast-1 | app.keirekipro.click | DNS検証 |
| ALB用（api） | ap-northeast-1 | api.keirekipro.click | DNS検証 |

### 4.2 CloudFront用証明書（us-east-1）

| 項目 | 設定値 |
|------|--------|
| ドメイン名 | app.keirekipro.click |
| 追加の名前（SAN） | なし |
| 検証方法 | DNS検証 |
| リージョン | us-east-1（バージニア北部） |
| キーアルゴリズム | RSA 2048 |
| 証明書の透明性ログ | 有効 |
| 自動更新 | 有効（DNS検証のため） |

### 4.3 ALB用証明書（ap-northeast-1・app）

| 項目 | 設定値 |
|------|--------|
| ドメイン名 | app.keirekipro.click |
| 追加の名前（SAN） | なし |
| 検証方法 | DNS検証 |
| リージョン | ap-northeast-1（東京） |
| キーアルゴリズム | RSA 2048 |
| 証明書の透明性ログ | 有効 |
| 自動更新 | 有効（DNS検証のため） |

### 4.4 ALB用証明書（ap-northeast-1・api）

| 項目 | 設定値 |
|------|--------|
| ドメイン名 | api.keirekipro.click |
| 追加の名前（SAN） | なし |
| 検証方法 | DNS検証 |
| リージョン | ap-northeast-1（東京） |
| キーアルゴリズム | RSA 2048 |
| 証明書の透明性ログ | 有効 |
| 自動更新 | 有効（DNS検証のため） |

### 4.5 DNS検証レコード

CloudFront用（us-east-1）:

| 項目 | 設定値 |
|------|--------|
| レコード名 | _xxxxxxxx.app.keirekipro.click |
| レコードタイプ | CNAME |
| 値 | _yyyyyyyy.acm-validations.aws |
| TTL | 300秒 |

ALB用（ap-northeast-1・app）:

| 項目 | 設定値 |
|------|--------|
| レコード名 | _aaaaaaaa.app.keirekipro.click |
| レコードタイプ | CNAME |
| 値 | _bbbbbbbb.acm-validations.aws |
| TTL | 300秒 |

ALB用（ap-northeast-1・api）:

| 項目 | 設定値 |
|------|--------|
| レコード名 | _cccccccc.api.keirekipro.click |
| レコードタイプ | CNAME |
| 値 | _dddddddd.acm-validations.aws |
| TTL | 300秒 |

## 5. ヘルスチェック設計

### 5.1 ヘルスチェック設定

| 項目 | 設定値 |
|------|--------|
| ヘルスチェック | 設定しない |
| 理由 | CloudFrontのフェイルオーバー機能を使用しないため |

## 6. クエリログ設計

### 6.1 クエリログ設定

| 項目 | 設定値 |
|------|--------|
| クエリログ | 無効 |
| 理由 | ポートフォリオ用途でコスト最適化のため |

## 7. DNSSEC設計

### 7.1 DNSSEC設定

| 項目 | 設定値 |
|------|--------|
| DNSSEC署名 | 無効 |
| 理由 | ポートフォリオ用途では運用負荷軽減を優先 |
