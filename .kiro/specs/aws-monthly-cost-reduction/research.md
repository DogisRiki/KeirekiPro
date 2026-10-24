# 調査の記録

## 要約

- **機能**: `aws-monthly-cost-reduction`
- **調べた範囲**: 本番環境の AWS の構成を変える変更(Complex Integration)として、2026年9月の請求の内訳、AWS の公開の価格表(Price List API)の東京リージョンの単価、CloudFront の VPC オリジンと ElastiCache Serverless for Valkey の公式文書、Terraform の各モジュール、backend のキャッシュの使い方、checkov の凍結した指摘の一覧(`terraform/.checkov.baseline`)を調べた
- **主な発見**:
  - 料金を下げられる大きな項目は2つある。1つ目は、インターネットに向いた ALB が持つ2つの公開の IPv4 アドレスの料金(月 $7.44)である。ALB をインターネットに向けない形(internal)にし、CloudFront から VPC オリジンでつなぐと、この料金が無くなる。2つ目は、ElastiCache のノード(cache.t4g.micro、月 $14.88)である。ElastiCache Serverless for Valkey に替えると、保存量の最低の課金(100MB)だけになり、月 $7.52 になる
  - 2つを変えたあとの、料金が最も高くなる月(31日で平日が23日の月)の見積もりは、税抜 $58.56、税込 $64.42 で、154を掛けると約9,920円になる。アプリの稼働時間を短くせずに1万円を下回る。ただし、1万円までの余裕は約80円しかない
  - ElastiCache Serverless は、AUTH トークンを受け付けず、ユーザー名とパスワードで認証する(RBAC)。また、クラスターの形でしか動かないので、backend のキャッシュの接続をクラスターの形に替える必要がある。backend のキャッシュの操作のうち、複数のキーを1回で消す操作が1か所だけある
  - ALB を別の名前の新しい資源として足すと、checkov が新しい指摘を出す。凍結した指摘の一覧は資源の名前(`module.alb.aws_lb.main` など)で照らし合わせるためである。そのため、ALB は同じ資源の名前のまま作り直す

## 調べたこと

### 今の請求と構成

- **出典**: 所有者が貼った2026年9月の請求の内訳、`terraform/` の各モジュール(2026-10-24 時点の main)
- **分かったこと**:
  - 2026年9月の請求は税込約78ドルで、154を掛けると約12,000円である
  - ALB(`terraform/modules/alb/main.tf` の `aws_lb.main`)は、インターネットに向いた形で、公開のサブネット2つに置かれている。公開の IPv4 アドレスを、サブネットごとに1つずつ持つ
  - ElastiCache(`terraform/modules/elasticache/main.tf` の `aws_elasticache_replication_group.main`)は、Valkey 8.0 の cache.t4g.micro のノード1台で、毎日24時間動いている。通信の暗号化と AUTH トークンを使い、保存の暗号化は使っていない
  - ECS のタスク(Fargate、ARM64、0.25 vCPU、メモリ 2GB)は、公開のサブネットに置かれ、公開の IPv4 アドレスを持つ。平日 8:00〜20:00 だけ動く
  - RDS(db.t4g.micro、gp3 20GB)は、平日 7:50〜20:05 だけ動く
  - WAF の Web ACL は CloudFront のディストリビューションに付いている(`terraform/modules/cloudfront/main.tf` の `web_acl_id`)。ALB には付いていない
  - CloudFront、SES、SQS、SNS、CloudWatch Logs は、9月の請求に料金が出ていない(無料の範囲に収まっている)

### 単価

- **出典**: AWS の Price List API の東京リージョンの価格表 `https://pricing.us-east-1.amazonaws.com/offers/v1.0/aws/<サービス>/current/ap-northeast-1/index.json`(2026-10-24 に確かめた)と、各サービスの料金のページ
- **分かったこと**:

| 項目 | 単価 | 出どころ |
|---|---|---|
| ALB の時間の料金 | $0.0243/時 | AWSELB の価格表(公開日 2026-09-11) |
| ALB の LCU | $0.008/LCU時 | 同上 |
| 公開の IPv4 アドレス | $0.005/時 | AmazonVPC の価格表(公開日 2026-10-16) |
| ElastiCache Valkey cache.t4g.micro | $0.020/時 | AmazonElastiCache の価格表(公開日 2026-10-14) |
| ElastiCache Serverless Valkey の保存量 | $0.101/GB時 | 同上 |
| ElastiCache Serverless Valkey の ECPU | $0.0027/100万 ECPU | 同上 |
| ElastiCache Serverless の保存量の最低の課金 | 100MB | https://aws.amazon.com/elasticache/pricing/ |
| RDS db.t4g.micro | $0.025/時 | AmazonRDS の価格表(公開日 2026-10-20) |
| RDS gp3 | $0.138/GB月 | 同上 |
| RDS のバックアップ | 保存量の100%を超えた分が $0.095/GB月 | https://aws.amazon.com/rds/postgresql/pricing/ |
| Fargate ARM の vCPU | $0.04045/vCPU時 | AmazonECS の価格表(公開日 2026-10-19) |
| Fargate ARM のメモリ | $0.00442/GB時 | 同上 |
| WAF | Web ACL $5/月、ルール $1/月、要求 $0.60/100万 | awswaf の価格表(公開日 2026-09-14) |
| Secrets Manager | $0.40/シークレット月、$0.05/1万回 | AWSSecretsManager の価格表(公開日 2026-09-11) |
| Route 53 | ホストゾーン $0.50/月。エイリアスのレコードへの問い合わせは無料 | AmazonRoute53 の価格表(公開日 2026-09-11) |
| CloudWatch のアラーム | $0.10/アラーム月。10個までは無料 | https://aws.amazon.com/cloudwatch/pricing/ |
| 日本の消費税 | 10% | https://aws.amazon.com/tax-help/japan/ |

- **設計への影響**: 見積もりは、料金が最も高くなる月(31日=744時間、平日23日)で出す。平日の数が多いほど、Fargate と RDS の料金が上がるためである

### CloudFront の VPC オリジン

- **出典**: https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/private-content-vpc-origins.html 、Terraform AWS provider の `aws_cloudfront_vpc_origin` と `aws_cloudfront_distribution` の文書
- **分かったこと**:
  - VPC オリジンを使うと、CloudFront は、プライベートのサブネットに置いた internal の ALB に、インターネットを通らずにつなぐ。追加の料金は無い
  - VPC にインターネットゲートウェイが要る(今の VPC にある)。ALB を置くプライベートのサブネットに、空いた IP アドレスが1つ以上要る
  - 東京リージョンでは、アベイラビリティーゾーンの ID が apne1-az3 のゾーンを使えない。ゾーンの名前(ap-northeast-1a など)と ID の対応はアカウントごとに違うので、所有者が `aws ec2 describe-availability-zones` で確かめる必要がある
  - CloudFront と ALB の間は HTTPS で暗号化できる。ALB の証明書は、オリジンのドメインの欄の名前と合っている必要がある。そのため、オリジンのドメインの欄には今の `api.keirekipro.click` を残し、ALB には今の api の証明書を付ける
  - オリジンに付けるヘッダー(`custom_header`)は、VPC オリジンでも送られる。今のヘッダー `X-Origin-Verify` はそのまま使える
  - ALB のセキュリティグループで、CloudFront のオリジン向けのプレフィックスリスト `com.amazonaws.global.cloudfront.origin-facing` を許す形が使える。今の ALB のセキュリティグループはこの形である
  - VPC オリジンの作成には最大15分かかる。VPC オリジンを直すときは、先にディストリビューションから外す必要がある
  - Terraform では、`aws_cloudfront_vpc_origin` に ALB の ARN、ポート、`origin_protocol_policy`、`origin_ssl_protocols` を書き、ディストリビューションのオリジンの `vpc_origin_config` で、その ID を指す。provider の 5.82 以降で使える(このリポジトリは 5.100.0)
  - gRPC と、オリジンへの要求で動く Lambda@Edge は使えない(このリポジトリはどちらも使っていない)

### ElastiCache Serverless for Valkey

- **出典**: https://docs.aws.amazon.com/AmazonElastiCache/latest/dg/WhatIs.corecomponents.html 、https://docs.aws.amazon.com/AmazonElastiCache/latest/dg/Clusters.RBAC.html 、Terraform AWS provider の `aws_elasticache_serverless_cache` `aws_elasticache_user` `aws_elasticache_user_group` の文書
- **分かったこと**:
  - 認証は RBAC(ユーザー名とパスワード)だけで、AUTH トークンは使えない。Valkey のユーザーグループには、default のユーザーを入れなくてよい。クライアントは `AUTH <ユーザー名> <パスワード>` で認証する
  - 通信の暗号化(TLS)と保存の暗号化は、常に有効で、外せない
  - 書き込みと読み取りの口は 6379、読み取り専用の口は 6380 である。セキュリティグループで両方を許す
  - クラスターの形でしか動かない。クライアントはクラスターの形に対応している必要がある。異なるスロットのキーを1回の命令で扱うと、`CROSSSLOT` のエラーになる
  - パラメータグループは使えない。追い出しの方式は volatile-lru に固定されている
  - スナップショットは既定で作られない。マイナーバージョンは自動で上がり、メンテナンスの時間帯は無い
  - 使用量の上限を決められる。保存量の上限(1〜5000GB)に達すると、期限付きのキーから追い出し、追い出せなくなると書き込みが OOM のエラーになる。ECPU の上限(毎秒1000〜15,000,000)に達すると、要求が絞られる。最低の使用量を決めると、使わなくてもその分が課金されるので、最低の使用量は決めない
  - CloudWatch の指標は、次元 `clusterId`(キャッシュの名前)で出る。使っているメモリの量は `BytesUsedForCache` で見る。ノードの指標 `DatabaseMemoryUsagePercentage` は出ない
  - ノードで動くキャッシュから Serverless へ、データをそのまま移す方法は無い。空のキャッシュから始める

### backend のキャッシュの使い方

- **出典**: `backend/src/main/java/com/example/keirekipro/infrastructure/store/auth/` の5つのストア、`backend/src/main/java/com/example/keirekipro/infrastructure/shared/redis/`、`backend/src/main/resources/application-prod.yaml`
- **分かったこと**:
  - backend は、`application-prod.yaml` で Secrets Manager の `keirekipro/redis` を読み込み、`redis-host` `redis-port` `redis-password` の3つのキーで接続先を決める。Spring Cloud AWS は、シークレットの JSON のキーを、そのまま設定の名前として読み込む
  - Spring Boot は、`spring.data.redis.cluster.nodes` が設定されていると、host と port より優先してクラスターの形でつなぐ
  - 複数のキーを1回の命令で扱うのは、`RedisOidcAuthorizationSessionStore.remove` の `redisTemplate.delete(List.of(...))` の1か所だけである。3つのキー(`oidc:state:` `oidc:provider:` `oidc:code_verifier:` に state を付けたもの)は、別々のスロットに入りうる
  - ほかのストアの操作は、どれも1つのキーだけを扱う
  - パスワードの再設定の印、二段階認証のコードと確認の印、OIDC の認可の途中の情報の有効期限は、どれも10分である。ログインし直さずに使える期間を決める印(リフレッシュトークン)の有効期限は7日である

### checkov の凍結した指摘

- **出典**: `terraform/.checkov.yaml`、`terraform/.checkov.baseline`、`docker/terraform/requirements.txt`(checkov 3.3.29)
- **分かったこと**:
  - 凍結した指摘は、ファイルと資源の名前の組で照らし合わせる。`module.alb.aws_lb.main` には CKV2_AWS_28(ALB に WAF が付いていない)と CKV_AWS_131(不正なヘッダーを捨てていない)が、`module.alb.aws_lb_target_group.backend` には CKV_AWS_378(ターゲットグループが HTTP を使う)が凍結されている
  - ALB やターゲットグループを、別の資源の名前で新しく足すと、同じ指摘が凍結の一覧に無い新しい指摘として出て、品質チェックが失敗する。凍結の一覧に足すことも、`.checkov.yaml` に除外を足すことも、ゲートの設定を変えることになるので、自律の変更ではできない
  - ALB のターゲットグループは、同時に1つのロードバランサーにしかつなげない

## 構成の比べ方

| 案 | 月の削減 | セキュリティの対策 | 判断 |
|---|---|---|---|
| ALB を internal にして、CloudFront から VPC オリジンでつなぐ | ALB の公開の IPv4 の $7.44 | WAF は CloudFront に付いたまま。ALB はインターネットから届かなくなる | 採る |
| CloudFront の定額のプラン(Free は WAF のルール5つまで、Pro は月 $15) | Free なら WAF の料金が無くなる | Free では WAF のルールが6つから5つに減る | 採らない。Free はルールを減らすことになり、Pro は今より高い |
| API Gateway の HTTP API で ALB を置き換える | ALB の料金の全部 | HTTP API には WAF を付けられない | 採らない。WAF を通らない経路ができる |
| backend を Lambda Web Functions に移す | 大きい | 未調査 | この spec の範囲の外(要望で別に扱う)。Java には対応していない |
| ElastiCache Serverless for Valkey に替える | $7.36 | 通信と保存の暗号化は常に有効。パスワードの認証は RBAC で続く | 採る |
| キャッシュを DynamoDB か PostgreSQL に替える | ノードの料金の全部 | 暗号化と経路の制限は付けられる | 採らない。backend のストア5つの作り直しになり、RDS は夜と週末に止まるので使えない |
| Secrets Manager を Parameter Store に移す | シークレットの料金 | - | 採らない。Issue の本文で禁じている |
| RDS のバックアップの期間を短くする、GuardDuty の RDS の保護を外す | 小さい | 守りが減る | 採らない |
| シークレットを1つにまとめる | 約 $1.60 | 変わらない | 今は採らない。判定の月に1万円を超えたときの候補にする |
| Fargate のメモリを 1GB にする | 約 $1.22 | 変わらない | 今は採らない。backend がメモリ不足で止まるおそれがある。判定の月に1万円を超えたときの候補にする |

## 決めたこと

### 決めたこと: ALB を同じ資源の名前のまま internal に作り直し、CloudFront から VPC オリジンでつなぐ

- **背景**: ALB の公開の IPv4 の料金を無くしたい。ALB を別の資源の名前で足すと、checkov の新しい指摘で品質チェックが失敗する
- **比べた案**:
  1. 新しい internal の ALB を別の資源の名前で足し、今の ALB と並べてから切り替える
  2. 今の ALB(`aws_lb.main`)を、同じ資源の名前のまま internal に作り直す
- **選んだ案**: 2
- **理由**: 案1は、ALB とターゲットグループの凍結した指摘が新しい資源には当てはまらず、品質チェックが通らない。また、ターゲットグループは1つのロードバランサーにしかつなげないので、並べる間に新しいターゲットグループも要り、ECS のサービスのつなぎ先も変わる。案2は、資源の名前と凍結した指摘がそのまま合い、ターゲットグループと ECS のサービスを変えずに済む
- **引き換え**: 作り直しの間(数分から15分ほど)は API に届かない。週末に切り替えるので、アプリの稼働時間には当たらない。ALB の削除保護が有効だと作り直しが失敗するので、作り直す前に削除保護を外す変更を本番に入れる必要がある
- **確かめること**: 所有者が、本番のアカウントのアベイラビリティーゾーンの ID を確かめ、プライベートのサブネットのゾーンが apne1-az3 でないこと

### 決めたこと: キャッシュを ElastiCache Serverless for Valkey に替え、RBAC のユーザーで認証する

- **背景**: キャッシュのノードは毎日24時間課金される。利用は少ない
- **選んだ案**: `aws_elasticache_serverless_cache` を足し、RBAC のユーザー `keirekipro-app` のパスワードに今の AUTH トークンと同じ値(`random_password.redis`、英数字32文字)を使う。保存量の上限を 1GB、ECPU の上限を毎秒1000にし、最低の使用量とスナップショットは決めない
- **理由**: 最低の課金の 100MB で、月 $7.52 に下がる。パスワードの値を変えないので、新しいシークレットは要らない。RBAC のパスワードの長さの決まり(16〜128文字)にも合う。上限を決めるのは、異常な使われ方で料金が膨らむのを止めるためである
- **引き換え**: 切り替えのときにキャッシュが空になるので、利用者は一度ログインし直す(要件で認められている)
- **確かめること**: Spring Boot の死活の確かめ(`/actuator/health`)がクラスターの形のキャッシュに送る命令(`CLUSTER INFO`)を ElastiCache Serverless が受け付けることを、実装のときに公式文書で確かめる

### 決めたこと: backend をクラスターの形につなぐ設定は、シークレットのキーで渡す

- **背景**: backend の接続をクラスターの形に替え、ユーザー名を渡す必要がある
- **比べた案**:
  1. `application-prod.yaml` に `spring.data.redis.cluster.nodes` と `username` を書く
  2. シークレット `keirekipro/redis` の JSON に、キー `spring.data.redis.cluster.nodes` と `spring.data.redis.username` を足す
- **選んだ案**: 2
- **理由**: 案2なら、backend の設定ファイルは変わらない。古いシークレット(キーが無い)を読む backend は今までどおり1台の形でつなぎ、新しいシークレットを読む backend はクラスターの形でつなぐ。そのため、元に戻すときも backend を作り直さずに済む
- **確かめること**: Spring Cloud AWS が、点を含む JSON のキーを設定の名前として読み込むことを、実装のときに公式文書で確かめる

### 決めたこと: 複数のキーを1回で消す操作を、1つずつ消す操作に替える

- **背景**: クラスターの形では、別々のスロットのキーを1回で消すと `CROSSSLOT` のエラーになる
- **選んだ案**: `RedisOidcAuthorizationSessionStore.remove` で、3つのキーを1つずつ消す
- **理由**: キーの名前にハッシュタグ(`{state}`)を付けて同じスロットに集める案もあるが、キーの名前を変えると、切り替えの前に作られた途中の情報を読めなくなる。1つずつ消せば、1台の形でもクラスターの形でも同じに動く
- **引き換え**: 消す命令が1回から3回に増える。OIDC のログインのときだけなので、ECPU の料金への影響は無視できる

### 決めたこと: キャッシュのメモリのアラームは、使っているバイト数で見る

- **背景**: ElastiCache Serverless には、今のアラームが見ている `DatabaseMemoryUsagePercentage` が無い
- **選んだ案**: アラーム `keirekipro-redis-memory-high` を、指標 `BytesUsedForCache`、次元 `clusterId` が 300,000,000 バイト以上になったときに鳴らす形に替える。期間 300秒、評価 2回、統計 Average、データが無いときの扱い missing は今と同じにする
- **理由**: 今のアラームは、cache.t4g.micro のノードの最大メモリ(約0.5GiB)の、予約分(25%)を除いた量の80%で鳴る。予約分の扱いによって、今のアラームが鳴るのは約322MB〜429MB である。300MB はそのどれよりも小さいので、今より遅く鳴ることはない。保存量の上限 1GB より十分小さいので、上限に近づく前に所有者に知らせられる
- **引き換え**: 割合ではなくバイト数で見るので、上限を変えたときは閾値も見直す

### 決めたこと: アプリの稼働時間とほかの料金は変えない

- **背景**: 2つの変更だけで見積もりが1万円を下回る
- **選んだ案**: アプリの稼働時間(平日 8:00〜20:00)、DB と backend の起動と停止の予定、シークレットの数、Fargate の大きさを変えない
- **理由**: 要件のとおり、ほかの変更で1万円を下回るならアプリの稼働時間を短くしない。シークレットをまとめる案と Fargate のメモリを減らす案は、見積もりが1万円を下回るので、変えるものを増やさないために採らない
- **引き換え**: 1万円までの余裕が約80円と小さい。判定の月に1万円を超えたときは、シークレットをまとめる案(約270円の削減)と Fargate のメモリを減らす案(約200円の削減)を、所有者に示す

### 決めたこと: 3つの PR に分けて本番に入れる

- **背景**: ALB の削除保護が有効なままだと、ALB の作り直しが削除のところで失敗する。古いキャッシュは、元に戻すときのために、確かめが済むまで残したい
- **選んだ案**:
  1. 1つ目の PR(準備): ALB の削除保護を外し、backend の消す操作を1つずつに替える。どちらも、今の構成のままで動く
  2. 2つ目の PR(切り替え): ALB を internal に作り直し、VPC オリジン、ElastiCache Serverless、シークレットのキー、アラーム、設計書を変える。古いキャッシュは残す
  3. 3つ目の PR(片付け): 古いキャッシュとその付属の資源を消し、ALB の削除保護を有効に戻す
- **理由**: 1つ目の PR の変更は、どちらも先に本番に入れておけば、2つ目の PR の apply をただ1回で済ませられる。2つ目の PR のマージを取り消したときに、古いキャッシュと、削除保護の外れた ALB が残っているので、取り消しの apply が通る

## 所有者が実装の前に確かめたこと(2026-10-24)

所有者が、design の移行の節の「実装の前に所有者が確かめること」の3つのコマンドを打ち、出力を会話に貼った。どれも合っていた。

- アベイラビリティーゾーン: ap-northeast-1a は apne1-az4、ap-northeast-1c は apne1-az1 で、どちらも apne1-az3 ではない
- Valkey の版: 東京リージョンで 7.2、8.0、8.1、8.2、9.0、9.1 を選べる。8 で始まる版がある
- apply のロールの権限: `aws iam simulate-principal-policy` で、`keirekipro-github-actions-role` の9つの操作(`cloudfront:CreateVpcOrigin` `cloudfront:UpdateDistribution` `iam:CreateServiceLinkedRole` `elasticache:CreateServerlessCache` `elasticache:CreateUser` `elasticache:CreateUserGroup` `ec2:CreateVpcEndpoint` `elasticloadbalancing:CreateLoadBalancer` `elasticloadbalancing:DeleteLoadBalancer`)が、どれも `allowed` だった

## 危ないことと備え

- 1万円までの余裕が約80円しかない。LCU、ECPU、CloudFront の転送量が見積もりより増えると1万円を超える。判定の月に超えたら、見積もりと請求を比べ、決めたことの節の2つの候補を所有者に示す
- 東京リージョンのアベイラビリティーゾーン apne1-az3 では VPC オリジンを使えない。プライベートのサブネットのゾーンが apne1-az3 に当たったら、apply の前に止めて、所有者と方式を決め直す
- VPC オリジンで、オリジンのドメインの欄の名前が DNS で引ける必要があるかは確かめられていない。そのため、`api.keirekipro.click` のレコードを残し、internal の ALB を指す
- ElastiCache Serverless に渡すサブネットの数が2つでよいか、東京リージョンで Valkey の主な版 8 を選べるかは、実装のときに公式文書で確かめる
- Spring Cloud AWS が点を含む JSON のキーを設定の名前として読み込むこと、`/actuator/health` の命令を ElastiCache Serverless が受け付けることは、実装のときに確かめる。受け付けないときは、apply のあとの所有者の確かめで API が 502 を返すので、そこで元に戻す
- ALB を作り直す間は API に届かない。切り替えは、金曜の 20:15 以降か週末に行う
- 日本の消費税の率は、AWS の税のページの文面を一部しか確かめられていない

## この spec の範囲の外で見つけたこと

- なし

## 出典

- https://pricing.us-east-1.amazonaws.com/offers/v1.0/aws/AWSELB/current/ap-northeast-1/index.json — ALB の単価(2026-10-24 に確かめた)
- https://pricing.us-east-1.amazonaws.com/offers/v1.0/aws/AmazonVPC/current/ap-northeast-1/index.json — 公開の IPv4 の単価(2026-10-24)
- https://pricing.us-east-1.amazonaws.com/offers/v1.0/aws/AmazonElastiCache/current/ap-northeast-1/index.json — ElastiCache の単価(2026-10-24)
- https://pricing.us-east-1.amazonaws.com/offers/v1.0/aws/AmazonRDS/current/ap-northeast-1/index.json — RDS の単価(2026-10-24)
- https://pricing.us-east-1.amazonaws.com/offers/v1.0/aws/AmazonECS/current/ap-northeast-1/index.json — Fargate の単価(2026-10-24)
- https://pricing.us-east-1.amazonaws.com/offers/v1.0/aws/awswaf/current/index.json — WAF の単価(2026-10-24)
- https://pricing.us-east-1.amazonaws.com/offers/v1.0/aws/AWSSecretsManager/current/ap-northeast-1/index.json — Secrets Manager の単価(2026-10-24)
- https://pricing.us-east-1.amazonaws.com/offers/v1.0/aws/AmazonRoute53/current/index.json — Route 53 の単価(2026-10-24)
- https://aws.amazon.com/elasticache/pricing/ — Serverless の最低の課金
- https://aws.amazon.com/rds/postgresql/pricing/ — RDS のバックアップの料金
- https://aws.amazon.com/cloudwatch/pricing/ — アラームの料金
- https://aws.amazon.com/tax-help/japan/ — 日本の消費税
- https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/private-content-vpc-origins.html — VPC オリジン
- https://docs.aws.amazon.com/AmazonElastiCache/latest/dg/Clusters.RBAC.html — RBAC
- https://registry.terraform.io/providers/hashicorp/aws/5.100.0/docs/resources/cloudfront_vpc_origin — Terraform の VPC オリジン
- https://registry.terraform.io/providers/hashicorp/aws/5.100.0/docs/resources/elasticache_serverless_cache — Terraform の ElastiCache Serverless
