# タスク

- [x] 1. 1つ目の PR で、backend が OIDC のログインの途中の情報をキャッシュから消すやり方を替え、点を含むシークレットのキーが設定の名前として読まれることを確かめる
- [x] 1.1 OIDC のログインの途中の情報を、3つのキーごとに消す (並行可)

  Claude は、部品「OIDC のログインの途中の情報のストア」の呼び出し方のとおり、`RedisOidcAuthorizationSessionStore.remove` を、`redisTemplate.delete(String)` を3つのキーに1回ずつ呼ぶ形にする。Claude は、`RedisOidcAuthorizationSessionStoreTest` の `test3` に、`remove` のあとに `oidc:state:` `oidc:provider:` `oidc:code_verifier:` に state を付けた3つのキーが、どれもキャッシュに残っていないことの確認を足す。
  - 完了の確かめ方: `test3` が、`find` が空を返すことと、3つのキーがどれも `hasKey` で偽になることを確かめて通る。`remove` から1つのキーを消す行を一時的に外すと、`test3` が失敗する。`remove` の引数と戻り値と、ほかのメソッドは変わっていない
  - 受入基準とテストの対応: 要件4の受入基準1(今と同じ機能を使える)のうち、OIDC のログインの途中の情報を消せる部分は、`RedisOidcAuthorizationSessionStoreTest` の `test3`(認可セッションを削除できる)で確かめる。クラスターの形のキャッシュで `CROSSSLOT` が起きないことは、開発環境のキャッシュが1台の形なので、このテストでは確かめられない。`CROSSSLOT` とは、クラスターの形のキャッシュに、置き場所の違う複数のキーを1回の命令で扱わせたときに返るエラーである。所有者が、2つ目の PR の本文の確認の手順で、Google のログインを通して確かめる
  - _要件: 4.1_
  - _対象の部品: OIDC のログインの途中の情報のストア_

- [x] 1.2 点を含むシークレットのキーが設定の名前として読まれることを確かめるテストを作る (並行可)

  Claude は、`backend/src/test/java/com/example/keirekipro/unit/infrastructure/config/SecretsManagerDottedKeyTest.java` を作る。このテストは、Spring Cloud AWS の Secrets Manager の設定の読み込みに、`spring.data.redis.cluster.nodes` と `spring.data.redis.username` のキーを持つ JSON を、テストの中の偽物の Secrets Manager から渡す。
  - 完了の確かめ方: `SecretsManagerDottedKeyTest` が、2つのキーが同じ名前の設定として読まれ、値が JSON の値と一致することを確かめて通る。偽物が返す JSON から `spring.data.redis.username` のキーを一時的に消すと、テストが失敗する。テストが、偽物を使わずに AWS に問い合わせることは無い
  - 受入基準とテストの対応: 要件3の受入基準7(シークレットを Secrets Manager に置き、読める役割を限る)のうち、backend がキャッシュの接続の設定を今と同じ1つのシークレットから読める部分は、`SecretsManagerDottedKeyTest` で確かめる。このテストが通らなければ、Claude は2つ目の PR を作らず、部品「シークレット keirekipro/redis」の失敗したときのとおり、設定の渡し方を所有者と決め直す
  - _要件: 3.7_
  - _対象の部品: シークレット keirekipro/redis_

- [x] 1.3 1つ目の PR を出す

  Claude は、`/verify-backend` を通したあと、`/ship` で1つ目の PR を出す。Claude は、PR の本文の「マージのあとにすること」に、移行の節の「1つ目の PR(準備)のマージのあとにすること」の手順を書く。
  - 完了の確かめ方: `/verify-backend` が成功している。PR の差分が `backend/` と `.kiro/specs/aws-monthly-cost-reduction/` だけにあり、`terraform/` の変更が無い。PR の本文に、所有者が打つ `release.yaml` のコマンドと、ジョブが緑で終わればうまくいったという見分け方と、`Spec: .kiro/specs/aws-monthly-cost-reduction` と `Refs: #614` の行がある。auto-merge の予約が付いている
  - 受入基準とテストの対応: 要件4の受入基準4(アプリの稼働時間の中にアプリは止まらない)のうち、1つ目の PR を稼働時間の中に本番に入れてよい部分は、PR の差分に `terraform/` の変更が無いことで確かめる
  - _要件: 4.4_
  - _依存: 1.1, 1.2_

- [x] 2. 2つ目の PR の Terraform のモジュールを変える

  Claude は、1つ目の PR が main にマージされたあとに、マージのあとの main から作ったブランチで、このタスクを始める。
- [x] 2.1 ALB を internal にし、置くサブネットを変数で受け取る

  Claude は、部品「ALB」の設定の値のとおり、`terraform/modules/alb/main.tf` の `aws_lb.main` を `internal = true` にし、`subnets` を変数 `subnet_ids` にする。Claude は、`terraform/modules/alb/variables.tf` の変数 `public_subnet_ids` を `subnet_ids` に改め、`terraform/main.tf` の ALB のモジュールに `subnet_ids = module.vpc.private_subnet_ids` を渡す。
  - 完了の確かめ方: `aws_lb.main` と `aws_lb_target_group.backend` の資源の名前と、`enable_deletion_protection = true` と、リスナーとリスナーのルールとアクセスログの設定が、差分で変わっていない。`enable_deletion_protection` を一時的に `false` にすると、checkov が CKV_AWS_150 の指摘を出す
  - 受入基準とテストの対応: 要件3の受入基準5(WAF を通らない経路が無い)のうち、ALB がインターネットから届かない部分は、`internal = true` の差分と、2つ目の PR の変更を確かめるタスク4.1 の checkov で確かめる。この変更には自動のテストが無い。所有者が、2つ目の PR の本文の確認の手順の `nslookup` で、本番で確かめる
  - _要件: 3.5_
  - _対象の部品: ALB_
  - _依存: 1.3_

- [x] 2.2 CloudFront から ALB への VPC オリジンを作り、API のオリジンを向ける

  Claude は、部品「VPC オリジン」の設定の値のとおり、`terraform/modules/cloudfront/main.tf` に `aws_cloudfront_vpc_origin` を足し、オリジン `ALB-api` の `custom_origin_config` を `vpc_origin_config` に替える。Claude は、`terraform/modules/cloudfront/variables.tf` に変数 `alb_arn` を足し、`terraform/main.tf` の CloudFront のモジュールに `alb_arn = module.alb.alb_arn` を渡す。
  - 完了の確かめ方: `aws_cloudfront_vpc_origin` の `origin_protocol_policy` が `https-only`、`origin_ssl_protocols` が `TLSv1.2` だけである。オリジン `ALB-api` の `domain_name` と `custom_header` の `X-Origin-Verify` と、ディストリビューションの `web_acl_id` が、差分で変わっていない
  - 受入基準とテストの対応: 要件3の受入基準1(WAF の6つのルールを残す)と受入基準3(通信の暗号化)のうち、CloudFront の部分は、`web_acl_id` が変わらないことと、VPC オリジンが HTTPS だけでつなぐことを、差分で確かめる。この変更には自動のテストが無い
  - _要件: 3.1, 3.3_
  - _対象の部品: VPC オリジン_
  - _依存: 1.3_

- [x] 2.3 ElastiCache Serverless と RBAC のユーザーを作り、出力を向け直す

  Claude は、部品「ElastiCache Serverless」の設定の値のとおり、`terraform/modules/elasticache/main.tf` に `aws_elasticache_user.app` と `aws_elasticache_user_group.app` と `aws_elasticache_serverless_cache.main` を足す。Claude は、`variables.tf` に変数 `app_user_password` を足して、`terraform/main.tf` の ElastiCache のモジュールに `app_user_password = module.secrets_manager.redis_password` を渡し、`outputs.tf` の `endpoint` `port` `cluster_id` を ElastiCache Serverless に向け、出力 `username` を足す。Claude は、古い `aws_elasticache_replication_group.main` とその付属の資源と変数 `auth_token` を残す。
  - 完了の確かめ方: `aws_elasticache_serverless_cache.main` の `engine` が `valkey`、`major_engine_version` が `"8"`、`cache_usage_limits` が保存量 1GB と毎秒 1000 ECPU で、`kms_key_id` と最低の使用量が無い。ECPU とは、ElastiCache Serverless が、リクエストの処理に使った CPU の時間と転送したデータの量を合わせて数える単位である。`aws_elasticache_user.app` の `authentication_mode` が `password` で、ユーザーグループに default のユーザーが無い。変数 `app_user_password` が `sensitive = true` である。古い `aws_elasticache_replication_group.main` が差分で消えていない
  - 受入基準とテストの対応: 要件3の受入基準3(backend とキャッシュの間の暗号化)と受入基準4(保存の暗号化)と受入基準8(替えたサービスにも同じ対策)は、ElastiCache Serverless の TLS と保存の暗号化が常に有効であることと、RBAC のパスワードとセキュリティグループを付けた差分で確かめる。RBAC とは、キャッシュに読み書きできる相手を、ユーザーごとのパスワードと使えるコマンドで限る仕組みである。要件3の受入基準6(キャッシュはパスワードを知っている backend だけを受け付ける)のうち、パスワードの部分は、ユーザーグループに default のユーザーが無いことで確かめる。この変更には自動のテストが無い
  - _要件: 3.3, 3.4, 3.6, 3.8_
  - _対象の部品: ElastiCache Serverless_
  - _依存: 1.3_

- [x] 2.4 キャッシュのセキュリティグループで許すポートの番号を 6379〜6380 にする (並行可)

  Claude は、部品「セキュリティグループ」の設定の値のとおり、`terraform/modules/vpc/main.tf` のルール `redis_ingress_ecs` と `ecs_egress_redis` で許すポートの番号を 6379〜6380 にする。
  - 完了の確かめ方: 2つのルールの `from_port` が 6379、`to_port` が 6380 で、許す相手が今と同じ ECS とキャッシュのセキュリティグループである。ALB と RDS のセキュリティグループのルールが、差分で変わっていない
  - 受入基準とテストの対応: 要件3の受入基準6(DB とキャッシュには backend からの通信だけが届く)のうち、キャッシュの部分は、許す相手が ECS のセキュリティグループだけであることを、差分で確かめる。この変更には自動のテストが無い
  - _要件: 3.6_
  - _対象の部品: セキュリティグループ_
  - _依存: 1.3_

- [x] 2.5 キャッシュのメモリのアラームとダッシュボードを ElastiCache Serverless の指標にする (並行可)

  Claude は、部品「キャッシュのメモリのアラーム」の設定の値のとおり、`terraform/modules/cloudwatch/main.tf` のアラーム `redis_memory_high` を、指標 `BytesUsedForCache`、次元 `clusterId`、閾値 300000000 にする。Claude は、ダッシュボードのキャッシュの2つの図を、`BytesUsedForCache` と `CurrConnections` を次元 `clusterId` で描く形にし、メモリの図の縦軸の上限を外す。今の `terraform/modules/cloudwatch/main.tf` は、ノードの名前に合わせて `var.redis_cluster_id` の後ろに `-001` を付けている。タスク2.3 が出力 `cluster_id` を ElastiCache Serverless の名前に向けるので、Claude は `-001` を外す。
  - 完了の確かめ方: `terraform/modules/cloudwatch/main.tf` に `${var.redis_cluster_id}-001` が残っていない。アラームの `evaluation_periods` `period` `statistic` `comparison_operator` `treat_missing_data` `alarm_actions` が、差分で変わっていない。アラームの数が9つのままである。ほかの8つのアラームが、差分で変わっていない
  - 受入基準とテストの対応: 要件5の受入基準1(8種類の異常のメールを今と同じ宛先に送る)と受入基準2(メールを送るまでの時間を長くしない)のうち、キャッシュのメモリの部分は、`alarm_actions` と期間と評価の回数が変わらないことと、閾値が design.md の「閾値を 300MB にした理由」の値であることを、差分で確かめる。この変更には自動のテストが無い。所有者が、2つ目の PR の本文の確認の手順の `set-alarm-state` で、メールが届くことを本番で確かめる
  - _要件: 5.1, 5.2_
  - _対象の部品: キャッシュのメモリのアラーム_
  - _依存: 1.3_

- [x] 3. 2つ目の PR で、シークレットのキーを変える

  Claude は、部品「シークレット keirekipro/redis」の呼び出し方の表のとおり、`aws_secretsmanager_secret_version.redis` の JSON を5つのキーにする。
  - 完了の確かめ方: `terraform validate` が成功する。シークレットの JSON に、表の5つのキーがあり、`spring.data.redis.cluster.nodes` の値が ElastiCache のモジュールの出力 `endpoint` と `port` を `:` でつないだものである。シークレットの数と、シークレットを読める役割が、差分で変わっていない
  - 受入基準とテストの対応: 要件3の受入基準7(シークレットを Secrets Manager に置き、読める役割を限る)は、シークレットの数と読める役割が変わらないことを、差分で確かめる。この変更には自動のテストが無い
  - _要件: 3.7_
  - _対象の部品: シークレット keirekipro/redis_

- [x] 4. 2つ目の PR の変更を確かめ、設計書を合わせる
- [x] 4.1 Terraform の検査と差分の読み取りで、変えてはいけないものが変わっていないことを確かめる

  Claude は、`/verify-terraform` を通す。Claude は、テストの方針の「差分の読み取り」のとおり、2つ目の PR の差分を読む。
  - 完了の確かめ方: `/verify-terraform` の fmt、validate、tflint、checkov が成功し、checkov が `terraform/.checkov.baseline` に無い指摘を出さない。差分で、`aws_lb.main` と `aws_lb_target_group.backend` の資源の名前が変わっておらず、`terraform/modules/ecs/` `terraform/modules/waf/` `terraform/modules/scheduler/` `frontend/` のファイルと `application-prod.yaml` が変わっていない
  - 受入基準とテストの対応: 次の4つは、どれも自動のテストが無く、差分の読み取りで確かめる。
    - 要件3の受入基準1(WAF の6つのルール)と受入基準9(切り替えの途中も対策が働く)は、`terraform/modules/waf/` と `web_acl_id` が変わらないことで確かめる
    - 要件3の受入基準2(GuardDuty)は、差分に GuardDuty の変更が無いことで確かめる
    - 要件1の受入基準3(見積もりが10,000円未満)と要件2の受入基準1から5(アプリの稼働時間を変えない)は、差分が design.md の見積もりの前提だけを変え、`terraform/modules/scheduler/` と `frontend/` のメンテ画面を変えていないことで確かめる。見積もりの前提は、ALB を internal にすることと、キャッシュを ElastiCache Serverless にすることの2つである
    - 要件7の受入基準1(表)は、design.md の安全の節の表の「変更のあとに受け持つ」の列と差分が食い違わないことで確かめる
  - _要件: 1.3, 2.1, 2.2, 2.3, 2.4, 2.5, 3.1, 3.2, 3.5, 3.9, 7.1_
  - _依存: 2.1, 2.2, 2.3, 2.4, 2.5, 3_

- [x] 4.2 インフラの設計書を、変更のあとの本番環境に合わせる (並行可)

  Claude は、部品「設計書」の直す中身のとおり、`doc/インフラ設計/AWS設計/` の7つの設計書と `doc/インフラ設計/Terraform設計/バックエンド・モジュール設計.md` を、3つ目の PR まで終えたあとの状態に直す。
  - 完了の確かめ方: 8つの設計書で、`grep` が `internet-facing` `cache.t4g.micro` `AUTHトークン` `auth_token` `1ノード構成` `DatabaseMemoryUsagePercentage` を、変更の前の状態を説明する文のほかに見つけない。変更の前の状態を説明する文とは、「変更の前は」「以前は」のように、今は使っていない設定であることを文の中で書いている文である。8つの設計書のどれにも、部品「設計書」の箇条に挙げた中身がある
  - 受入基準とテストの対応: 要件8の受入基準1(設計書を変更のあとに合わせる)は、完了の確かめ方の `grep` と、部品「設計書」の箇条との突き合わせで確かめる。文書には自動のテストが無い
  - _要件: 8.1_
  - _対象の部品: 設計書_

- [x] 4.3 本番環境の構成図を、変更のあとの本番環境に合わせる

  Claude は、`doc/インフラ設計/構成図/本番環境構成/本番環境構成図.drawio.svg` の、ALB の置き場所をプライベートのサブネットに、キャッシュを ElastiCache Serverless に直し、CloudFront から ALB への線に VPC オリジンを書き添える。
  - 完了の確かめ方: 直した SVG が XML として読め、ブラウザで開くと、ALB がプライベートのサブネットの枠の中にあり、キャッシュの名前が ElastiCache Serverless である
  - 受入基準とテストの対応: 要件8の受入基準1(設計書を変更のあとに合わせる)のうち、構成図の部分は、完了の確かめ方に書いた、直した SVG をブラウザで開いて読む確認で確かめる。図には自動のテストが無い
  - _要件: 8.1_

- [ ] 5. 2つ目の PR を出し、切り替えの apply のログで plan を読む
- [ ] 5.1 2つ目の PR を、所有者が決めた切り替えの日に合わせて出す

  Claude は、所有者が、1つ目の PR の backend のリリースを終えたことと、切り替えの日を書いたあとに、`/ship` で2つ目の PR を出す。Claude は、部品「3つの PR の本文」のとおり、PR の本文の「マージのあとにすること」に、移行の節の「2つ目の PR(切り替え)の作り方とマージのあとにすること」から、次の5つを書く。1つ目は削除保護を外す手順、2つ目は apply を始める時間の幅、3つ目はマージから切り替えの apply までの間はほかの目的で `terraform-apply.yaml` を動かさないという注意、4つ目は5つの確認の手順、5つ目は元に戻す手順である。Claude は、PR の本文に、WAF の6つのルールの設定を変えていないことと、`terraform/modules/waf/` のファイルを変えていないことを書く。
  - 完了の確かめ方: PR の本文に、所有者が打つコマンドが、移行の節のコマンドと1文字も違わずにあり、手順ごとにうまくいったかの見分け方がある。PR の本文に、マージから切り替えの apply までの間はほかの目的で `terraform-apply.yaml` を動かさないという注意と、動かすと ALB が作り直されてアプリの稼働時間の中に API に届かなくなるという理由がある。PR の本文に `Spec: .kiro/specs/aws-monthly-cost-reduction` と `Refs: #614` の行がある。auto-merge の予約が付いている
  - 受入基準とテストの対応: 次の3つは、どれも自動のテストが無い。
    - 要件6の受入基準1(元に戻す手順)と受入基準2(apply のあとの3つの確認)は、PR の本文と移行の節の突き合わせで確かめる
    - 要件7の受入基準2(WAF の設定を変えたかどうか)は、PR の本文の文と、2つ目の PR の変更を確かめるタスク4.1 の差分の読み取りで確かめる
    - 要件4の受入基準2(ログインし直すのは入れるときと戻すときだけ)、受入基準3(保存したデータが消えない)、受入基準4(稼働時間の中に止まらない)、受入基準5(期限までリンクとコードが使える)と、要件3の受入基準9(切り替えの途中)は、Claude が、PR の本文の apply を始める時間の幅と元に戻す手順で確かめる。所有者が、これらの受入基準を本番で確かめる
  - _要件: 3.9, 4.2, 4.3, 4.4, 4.5, 6.1, 6.2, 7.2_
  - _対象の部品: 3つの PR の本文_
  - _依存: 1.3, 4.1, 4.2, 4.3_

- [ ] 5.2 切り替えの apply のログで plan を読む

  Claude は、所有者が切り替えの apply を終えたと伝えたあとに、`gh run view <実行の番号> --log` で `terraform-apply.yaml` のログを読む。食い違いがあれば、Claude は所有者に知らせる。
  - 完了の確かめ方: plan で、`module.alb.aws_lb.main` が作り直しになり、`module.alb.aws_lb_target_group.backend` と `module.ecs.aws_ecs_service.backend` が作り直しにならず、`module.waf` に変更が無かったことを、Claude が所有者に1行ずつ示している
  - 受入基準とテストの対応: 要件3の受入基準1(WAF の6つのルール)と受入基準5(WAF を通らない経路が無い)は、plan で `module.waf` に変更が無く、ALB が作り直しになったことで確かめる。これは apply のあとの確認で、自動のテストは無い
  - _要件: 3.1, 3.5_

- [ ] 6. 3つ目の PR で、古いキャッシュを片付ける
- [ ] 6.1 古いキャッシュの資源と AUTH トークンの変数を消す

  Claude は、所有者が2つ目の PR の確認が済んだと伝えたあとに、`terraform/modules/elasticache/main.tf` から `aws_elasticache_replication_group.main` `aws_elasticache_parameter_group.main` `aws_elasticache_subnet_group.main` を消し、`variables.tf` から変数 `auth_token` を消し、`terraform/main.tf` から `auth_token` を渡す行を消す。
  - 完了の確かめ方: `/verify-terraform` が成功する。`grep -rn --include='*.tf' "auth_token\|replication_group" terraform/` が何も見つけない。`terraform/.checkov.baseline` に残る古いキャッシュの行は、design.md が `.checkov.baseline` を変えないと決めているので、消さない。ElastiCache Serverless とシークレット `keirekipro/redis` の資源が、差分で変わっていない
  - 受入基準とテストの対応: 要件4の受入基準1(今と同じ機能を使える)のうち、片付けが backend の使うキャッシュに触れない部分は、ElastiCache Serverless とシークレットが差分で変わらないことで確かめる。この変更には自動のテストが無い
  - _要件: 4.1_
  - _依存: 5.2_

- [ ] 6.2 3つ目の PR を出す

  Claude は、`/ship` で3つ目の PR を出す。Claude は、PR の本文の「マージのあとにすること」に、移行の節の「3つ目の PR(片付け)のマージのあとにすること」の手順を書く。
  - 完了の確かめ方: PR の本文に、所有者が打つ `terraform-apply.yaml` のコマンドと、ElastiCache の画面から `keirekipro-redis` が消えればうまくいったという見分け方と、`Spec: .kiro/specs/aws-monthly-cost-reduction` と `Refs: #614` の行がある。auto-merge の予約が付いている
  - 受入基準とテストの対応: 要件6の受入基準1(元に戻す手順)のうち、3つ目の PR の部分は、Claude が、元に戻す手順が要らないことを PR の本文に書いて確かめる。3つ目の PR は、利用者から見える動きを変えないので、元に戻す手順が要らない。自動のテストは無い
  - _要件: 6.1_

- [ ] 7. 判定の月の請求を見積もりと比べる

  Claude は、所有者が判定の月の請求の内訳を貼ったあとに、部品「月額の見積もり」の「判定の月の請求と比べるとき」のとおり、内訳を design.md の見積もりの表の同じ行と比べる。
  - 完了の確かめ方: Claude が、見積もりを上回ったサービスと、上回った額をドルで所有者に示している。税込の合計に154を掛けた額が10,000円以上のときは、Claude が、シークレットを1つにまとめる案と Fargate のメモリを減らす案も示している
  - 受入基準とテストの対応: 要件1の受入基準1(判定の月で判定する)、受入基準2(1ドル154円で換算する)、受入基準4(上回ったサービスと額を示す)は、Claude が所有者に示した比べた結果で確かめる。判定は所有者が行うので、自動のテストは無い
  - _要件: 1.1, 1.2, 1.4_
  - _対象の部品: 月額の見積もり_
  - _依存: 6.2_

## 完了条件(全タスク共通)

Claude は、どのタスクでも、タスクの箇条書きの欄を書いたうえで、次の4つを満たしたときにタスクを完了とする。

1. Claude は、タスクが満たす requirements.md の受入基準(要件の番号付きの項目)ごとに、それを確かめるテストのファイル名とテスト名を「受入基準とテストの対応」の行に書く。Claude は、確かめるテストの無い受入基準を残さない。
2. タスクで変えた領域の verify のスキル(`/verify-frontend` `/verify-backend` `/verify-terraform`)が、すべて成功している。
3. Claude は、テストを飛ばす設定、アサーションの削除、カバレッジや lint の対象からの除外を足して、完了条件を満たしたように見せない。CI の escape-hatch の検査が、これらの追加を機械で見つける。
4. Claude は、新しく書いたテストについて、テストの対象のコードを一時的に壊してテストが失敗することを確かめてから、コードを元に戻す。

## 実装のメモ

- design.md の「テストの方針」に書いたとおり、Terraform の変更と、PR の本文と、設計書には、自動のテストが無い。そのため、2つ目の PR から判定の月の請求を比べるまでのタスク2から7では、Claude は、各タスクの「受入基準とテストの対応」に書いた確認を、テストの代わりに使う。テストの代わりにするのは、完了条件のうち、受入基準ごとに確かめるテストを書く1つ目と、新しく書いたテストが対象のコードを壊すと失敗することを確かめる4つ目である
- ALB と CloudFront と ElastiCache のモジュールを変えるタスク2.1 から 2.3 は、変数を足すか名前を改めたモジュールに、`terraform/main.tf` で値を渡すところまでを受け持つ。そうしないと、タスクを終えた時点で `terraform validate` が通らず、完了条件の2つ目の `/verify-terraform` が失敗するためである。3つのタスクが同じ `terraform/main.tf` を変えるので、Claude は、3つのタスクに並行可の印を付けない
- Claude は、3つ目の PR の変更を、2つ目の PR のマージのあとの main から作ったブランチで作る
- Claude は、どの PR でも、PR の本文の Issue の行を `Refs: #614` にする。Issue を閉じる語を使わないのは、3つ目の PR のマージのあとも、判定の月の請求を比べるタスク7が残るためである
- タスク4.1 の確認では、手元の terraform のイメージ(2026-09-29 に作ったもの)の checkov が 3.3.19 で、`docker/terraform/requirements.txt` で固定した 3.3.29 より古かった。そのため、手元の checkov の合格は 3.3.29 での合格ではない。3.3.29 での合格は、2つ目の PR の CI の terraform-static の結果で確かめる
