# SES設計書

## 1. SES基本設定

### 1.1 リージョン設定

| 項目 | 設定値 |
|------|--------|
| リージョン | ap-northeast-1（東京） |

### 1.2 送信元アドレス設計

| 送信元アドレス | 用途 |
|--------------|------|
| info@keirekipro.click | ユーザー向け通知メール |

## 2. ドメイン認証設計

### 2.1 ドメイン検証

| 項目 | 設定値 |
|------|--------|
| 検証ドメイン | keirekipro.click |
| 検証方法 | DNS検証（TXTレコード） |
| 検証レコード名 | _amazonses.keirekipro.click |
| 検証レコード値 | SESが発行するトークン |

### 2.2 DKIM設定

| 項目 | 設定値 |
|------|--------|
| DKIM | 有効（Easy DKIM） |
| 署名キー長 | 2048ビット |
| DNSレコード数 | 3つのCNAMEレコード |

### 2.3 DKIM CNAMEレコード

| レコード名 | タイプ | 値 |
|-----------|--------|-----|
| {selector1}._domainkey.keirekipro.click | CNAME | {selector1}.dkim.amazonses.com |
| {selector2}._domainkey.keirekipro.click | CNAME | {selector2}.dkim.amazonses.com |
| {selector3}._domainkey.keirekipro.click | CNAME | {selector3}.dkim.amazonses.com |

## 3. メール認証設計

### 3.1 SPF設定

| 項目 | 設定値 |
|------|--------|
| SPFレコード | keirekipro.click |
| レコードタイプ | TXT |
| 値 | "v=spf1 include:amazonses.com ~all" |
| ポリシー | ~all（ソフトフェイル） |

### 3.2 DMARC設定

| 項目 | 設定値 |
|------|--------|
| DMARCレコード | _dmarc.keirekipro.click |
| レコードタイプ | TXT |
| ポリシー（p） | quarantine |
| レポート送信先（rua） | mailto:dmarc@keirekipro.click |

DMARC TXTレコード値:
```
"v=DMARC1; p=quarantine; rua=mailto:dmarc@keirekipro.click"
```

## 4. カスタムMAIL FROM設計

### 4.1 MAIL FROMドメイン設定

| 項目 | 設定値 |
|------|--------|
| カスタムMAIL FROMドメイン | mail.keirekipro.click |
| バウンス時の動作 | SESデフォルトMAIL FROMにフォールバック |

### 4.2 MAIL FROM用DNSレコード

MXレコード:

| 項目 | 設定値 |
|------|--------|
| レコード名 | mail.keirekipro.click |
| レコードタイプ | MX |
| 優先度 | 10 |
| 値 | feedback-smtp.ap-northeast-1.amazonses.com |

SPFレコード:

| 項目 | 設定値 |
|------|--------|
| レコード名 | mail.keirekipro.click |
| レコードタイプ | TXT |
| 値 | "v=spf1 include:amazonses.com ~all" |

## 5. 送信設定

### 5.1 設定セット

| 項目 | 設定値 |
|------|--------|
| 設定セット名 | keirekipro-config-set |
| イベント発行先 | なし |

## 6. バウンス・苦情処理設計

### 6.1 通知設定

| 項目 | 設定値 |
|------|--------|
| バウンス通知 | 無効 |
| 苦情通知 | 無効 |
| 配信通知 | 無効 |

## 7. IAM権限設計

### 7.1 ECSタスクロール用SES権限

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "SESSendEmail",
      "Effect": "Allow",
      "Action": "ses:SendEmail",
      "Resource": "*",
      "Condition": {
        "StringEquals": {
          "ses:FromAddress": "info@keirekipro.click"
        }
      }
    }
  ]
}
```

## 8. アプリケーション連携設計

### 8.1 SDK設定

| 項目 | 設定値 |
|------|--------|
| SDK | AWS SDK for Java v2 |
| クライアント | SesClient |
| リージョン | ap-northeast-1（Spring Cloud AWSで自動設定） |
| 認証 | ECSタスクロールによるIAM認証 |

## 9. 監視設計

### 9.1 CloudWatchメトリクス

| メトリクス | 説明 | 監視方針 |
|-----------|------|---------|
| Send | 送信試行数 | 参考値として確認 |
| Bounce | バウンス数 | 急増時は調査 |
| Complaint | 苦情数 | 発生時は即時対応 |
| Reject | 拒否数 | 発生時は設定確認 |

### 9.2 アラーム設定

| 項目 | 設定値 |
|------|--------|
| アラーム | 設定しない |
| 理由 | 送信量が少なく、CloudWatch標準メトリクスで十分 |

## 10. セキュリティ設計

### 10.1 送信制限

| 項目 | 設定値 |
|------|--------|
| 送信元制限 | info@keirekipro.clickのみ |
| IAMポリシーによる制限 | 送信元アドレスをConditionで制限 |
| 送信先制限 | なし（登録ユーザーのメールアドレスへ送信） |
