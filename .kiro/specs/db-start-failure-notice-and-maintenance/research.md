# 調査と設計の判断の記録

## Summary
- **Feature**: `db-start-failure-notice-and-maintenance`
- **Discovery Scope**: Extension(既存の定時の起動とアラームの仕組みに、通知を足す。frontend の既存の画面の切り替えを広げる)
- **Key Findings**:
  - 朝のDBの起動の失敗には2つの形がある。起動の指令が断られる同期の失敗(StartDBInstance が InsufficientDBInstanceCapacity などを返す)と、受け付けたあとに立ち上がらずに止まる非同期の失敗である。どちらも、コードを書かずに AWS の既存の機能で拾える
  - 同期の失敗は、EventBridge Scheduler の CloudWatch のメトリクス `TargetErrorCount` に出る。次元はスケジュールグループだけなので、DBの起動のスケジュールを専用のグループに移すと、DBの起動の失敗だけを切り分けられる
  - 非同期の失敗に当たる RDS のイベントIDは、公式の文書の表で1つに決められない。カテゴリ `failure` で広く拾う

## Research Log

### 今の起動の仕組みとアラーム
- **Context**: 失敗を拾う場所を決めるため
- **Sources Consulted**: `terraform/modules/scheduler/main.tf`、`terraform/modules/cloudwatch/main.tf`、`terraform/main.tf`
- **Findings**:
  - `rds_start` は `cron(50 22 ? * SUN-THU *)`(UTC、JST 平日 7:50)、`retry_policy { maximum_retry_attempts = 2 }`、DLQ なし。4本のスケジュールはどれも default のスケジュールグループにある
  - アラームは7本で、すべて `alarm_actions = [aws_sns_topic.alerts.arn]` だけを持つ。SNS のトピックのポリシーは `cloudwatch.amazonaws.com` だけに `sns:Publish` を許している
- **Implications**: アラームを1本足すと8本になり、CloudWatch のアラームの無料枠(10個)に収まる。EventBridge から送るには、トピックのポリシーに `events.amazonaws.com` を足す

### EventBridge Scheduler の失敗のメトリクス
- **Context**: 同期の失敗を拾う方法を決めるため
- **Sources Consulted**:
  - https://docs.aws.amazon.com/scheduler/latest/UserGuide/monitoring-cloudwatch.html
  - https://docs.aws.amazon.com/scheduler/latest/APIReference/API_RetryPolicy.html
  - https://docs.aws.amazon.com/scheduler/latest/UserGuide/configuring-schedule-dlq.html
- **Findings**:
  - 名前空間は `AWS/Scheduler`。次元は `ScheduleGroup` だけで、スケジュール単位の次元は無い
  - `TargetErrorCount` は、ターゲットの API が例外を返したときに出る。再試行のたびにも出る
  - メトリクスの配信はベストエフォートで、欠けたり遅れたりしうる
  - InsufficientDBInstanceCapacity(400)を Scheduler が再試行するかは、文書から決められない
- **Implications**: `TargetErrorCount` に、DBの起動だけのスケジュールグループの次元でアラームを掛ける。再試行するかどうかにかかわらず、最初の失敗で数が増える

### RDS のイベント
- **Context**: 非同期の失敗を拾う方法を決めるため
- **Sources Consulted**:
  - https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/USER_Events.Messages.html
  - https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/rds-cloud-watch-events.html
  - https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/USER_Events.overview.html
  - https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/CHAP_Troubleshooting.html
  - https://docs.aws.amazon.com/AmazonRDS/latest/APIReference/API_CreateEventSubscription.html
- **Findings**:
  - 起動のときの容量不足に当たるイベントIDは、表に無い。DBが止まった状態に入ると出るのは、カテゴリ `failure` の RDS-EVENT-0031・0035・0036 などである。停止していたインスタンスの起動で `incompatible-network` になりうることが、トラブルシューティングの文書に書かれている
  - RDS のイベントは、`source: aws.rds`、`detail-type: RDS DB Instance Event` として EventBridge に届く。detail に `EventCategories` `SourceIdentifier` `EventID` `Message` がある。届くまでに最大5分かかることがある
  - RDS のイベント通知(イベントの購読)は、カテゴリまでしか絞れない
- **Implications**: EventBridge のルールで、対象のDBの `failure` のイベントを拾う。イベントIDでは絞らない

### SNS とメール
- **Context**: メールの形と、トピックのポリシーを決めるため
- **Sources Consulted**:
  - https://docs.aws.amazon.com/eventbridge/latest/userguide/eb-use-resource-based.html
  - https://docs.aws.amazon.com/eventbridge/latest/userguide/eb-transform-target-input.html
  - https://docs.aws.amazon.com/sns/latest/dg/sns-email-notifications.html
- **Findings**:
  - EventBridge のルールから SNS へ送るときは、トピックのポリシーに Principal `events.amazonaws.com`、Action `sns:Publish`、Resource トピックの ARN の文を足す。文書の SNS の例には条件が無い
  - input_transformer で、イベントの項目を埋め込んだ文字列をメールの本文にできる
  - SNS のメールの本文の書式は変えられない
- **Implications**: 最初の design では input_transformer で SNS へ送る形を考えたが、メールを1通にまとめられないので採らなかった(Design Decisions の「ルールは送り先を持たず、当たった数にアラームを掛ける」)

### 費用
- **Sources Consulted**: https://aws.amazon.com/cloudwatch/pricing/ 、https://aws.amazon.com/eventbridge/pricing/ 、https://aws.amazon.com/sns/faqs/
- **Findings**: AWS のサービスのイベントを EventBridge で受けるのは無料。CloudWatch のアラームは10個まで無料。SNS のメールは月1,000通まで無料
- **Implications**: この設計で増える費用は0円である

## Architecture Pattern Evaluation

| 案 | 中身 | 強み | 弱み | 判断 |
|---|---|---|---|---|
| アラームと EventBridge のルール | 同期の失敗はスケジュールのメトリクスのアラーム、非同期の失敗は RDS のイベントのルールで拾う | コードが要らない。費用0円 | 非同期の失敗のイベントIDを決められず、カテゴリで広く拾う | 採る |
| RDS のイベントの購読だけ | `failure` のカテゴリを SNS へ直接送る | 1つのリソースで済む | 同期の失敗を拾えない。トピックのポリシーに要る主体を確かめられていない | 採らない |
| Lambda で 8:00 にDBの状態を見る | 8:00 に動く関数が `available` でなければメールを送る | 失敗の形を問わない | コードとテストの仕組みが要る。所有者が作り込まない方針を決めた | 採らない |
| CloudTrail 経由 | 失敗した API の呼び出しを拾う | 失敗の理由が分かる | trail と S3 のバケットが要る | 採らない |

## Design Decisions

### Decision: DBの起動のスケジュールを専用のスケジュールグループに移す
- **Context**: `AWS/Scheduler` のメトリクスはスケジュールグループ単位でしか分からない
- **Selected Approach**: スケジュールグループ `keirekipro-db-start` を作り、`rds_start` をそこへ移す。時刻、ターゲット、入力、再試行の回数は変えない
- **Trade-offs**: plan では `rds_start` が作り直しになる。apply のあいだの数秒は起動のスケジュールが無いので、所有者は 7:50 の前後を避けて apply する

### Decision: アラームは直前60分の中に1回でも失敗があれば鳴らす
- **Context**: 再試行の間隔が文書で決まらず、失敗が散らばることがある。散らばったまま鳴り直すと、1回の失敗でメールが2通以上届く
- **Selected Approach**: 期間60秒、評価の期間60、鳴らすのに要る点1、合計が1以上、データが無いときは鳴らさない(`notBreaching`)。アラームは毎分評価される(https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/alarm-evaluation.html)ので、最初の失敗から数分で ALARM になり、最後の失敗から60分たつまで ALARM のまま残る
- **Trade-offs**: 再試行が60分を超えて散らばると、メールが2通になる

### Decision: ルールは送り先を持たず、当たった数にアラームを掛ける
- **Context**: design の審査(D3-1-1)で、ルールから SNS へ直接送ると、1回の異常で failure のイベントが2つ以上出たときにメールが2通以上になり、要件1の受入基準4に反すると分かった
- **Selected Approach**: ルールは送り先を持たず、`AWS/Events` の `MatchedEvents`(次元 `RuleName`)に、直前60分の中に1回でも当たれば鳴るアラームを掛ける(https://docs.aws.amazon.com/eventbridge/latest/userguide/eb-monitoring.html)。SNS のトピックのポリシーは変えずに済み、本番での確認も `set-alarm-state` で通せる
- **Trade-offs**: メールに RDS のイベントのメッセージは載らない。送り先を持たないルールでも `MatchedEvents` が出るかは文書に明記が無く、Claude の読みである

### Decision: 起動の指令が通ったあとの失敗は、AWS が failure の知らせを出したときだけ通知する
- **Context**: design の審査(D2-1-1)で、容量不足のときの非同期の失敗のイベントを文書で決められないことが分かった
- **Selected Approach**: 所有者が案Aを選んだ。カテゴリ `failure` のイベントを時刻を問わず通知し、出ない場合は ALB の異常のアラームで気づく

## Risks & Mitigations
- 非同期の失敗で、`failure` のカテゴリのイベントが出ない場合がありうる — 所有者は ALB の異常のアラームのメールで気づく(要件1の受入基準2)
- 1回の非同期の失敗で、`failure` のイベントが2つ以上出ると、メールが2通以上届く — 防がない。所有者は、同じ時刻のメールを1件の失敗として読める
- 7:50 の時点でDBがすでに動いていると、起動の指令が `InvalidDBInstanceState` で断られ、アラームが鳴る — 所有者が手で起動した日に限られる。防がない
- メトリクスの配信が欠けると、同期の失敗でもアラームが鳴らないことがある — 防がない(文書がベストエフォートと書いている)

## References
- [EventBridge Scheduler の CloudWatch のメトリクス](https://docs.aws.amazon.com/scheduler/latest/UserGuide/monitoring-cloudwatch.html)
- [RDS のイベントの一覧](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/USER_Events.Messages.html)
- [RDS のイベントと EventBridge](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/rds-cloud-watch-events.html)
- [EventBridge の送り先のリソースのポリシー](https://docs.aws.amazon.com/eventbridge/latest/userguide/eb-use-resource-based.html)
- [EventBridge の input_transformer](https://docs.aws.amazon.com/eventbridge/latest/userguide/eb-transform-target-input.html)
- [ALB のトラブルシューティング(502・503・504)](https://docs.aws.amazon.com/elasticloadbalancing/latest/application/load-balancer-troubleshooting.html)
- [CloudFront の HTTP ステータス](https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/HTTPStatusCodes.html)
