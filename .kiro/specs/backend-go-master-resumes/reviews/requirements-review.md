## サイクル1 往復1(2026-11-14)

### 審査の範囲

範囲: 全体

### 実ファイルで確かめた文

パスの `J/` は `backend/src/main/java/com/example/keirekipro/` を指す。

- はじめに「今の Go 版は、マスタと経歴書の操作の要求に、未実装であることを示す答えを返す」: backend/internal/httpapi/server.go 17-21行、backend/internal/httpapi/unimplemented.go 83-230行 / 合っていた
- はじめに「26の操作(マスタ3、経歴書23)」「経歴書の作成には、コピーして作ることも含む」: backend/api/openapi.yaml(26の operationId)、J/presentation/resume/controller/CreateResumeController.java、J/usecase/resume/CopyCreateResumeUseCase.java / 合っていた
- はじめにの表「置き換えの spec の16の受入基準の中身」: .kiro/specs/backend-go-replacement/requirements.md(要件1.6、2.5、4.2、4.4、4.5、4.6、8.1、8.2、9.1、9.2、9.5、9.6、9.7、12.1、13.1、13.2)/ 合っていた
- 範囲の前提1「Go 版の土台、比べる検査、版をまたいで確かめる検査、API の仕様書が main に入っている。仕様書にマスタと経歴書の操作も書かれている」: backend/compat/harness/compare.go、cross.go、perf.go、backend/api/openapi.yaml 622-1375行、.kiro/specs/backend-go-replacement/progress.md / 合っていた
- 範囲の前提2「認証のまとまりの Go 版は main に入っている」: .kiro/specs/backend-go-replacement/progress.md 36行 / 合っていた
- 範囲の前提3「段階1で、マスタと経歴書の操作に当たる動きのうち、次の2つを試しに作らなかった」: .kiro/specs/backend-go-replacement/research.md 37-45行、J/infrastructure/repository/resume/ResumeMapper.xml、J/domain/policy/resume/ResumeEntryOrderPolicy.java、J/presentation/resume/controller/UpdateCareerController.java 45-46行 / 食い違っていた(R1-1-1)
- 範囲の前提4と要件1「ポートフォリオ、SNS、自己PR の並び順の違いが、所有者が受け入れた違いとして載っている」: backend/compat/changed-behaviors.yaml 6-37行(CB-001)、J/domain/policy/resume/ResumeEntryOrderPolicy.java / 合っていた
- 要件1「画面は `isActive` の名前で送り、`active` の名前で受け取る」: J/presentation/resume/dto/CreateCareerRequest.java 41行、J/presentation/resume/dto/ResumeInfoResponse.java 189行 / 合っていた
- 要件2「年月の書き方、リンクが https で始まること」: J/presentation/resume/dto/CreateCareerRequest.java 33-37行、J/presentation/resume/dto/CreatePortfolioRequest.java 36行、CreateSnsPlatformRequest.java 29行 / 合っていた
- 要件2「1人の利用者が作れる経歴書は50件まで。欄ごとの項目の数の上限がある」: J/usecase/resume/policy/ResumeLimits.java 15行、20-45行 / 合っていた
- 要件2「1人の利用者の中で、経歴書の名前が重ならないこと」: J/domain/service/resume/ResumeNameDuplicationCheckService.java 37-46行 / 合っていた
- 要件2「経歴書の名前に使えない文字と、姓と名に使える文字」: J/domain/model/resume/ResumeName.java 18行、51-56行、J/domain/model/resume/FullName.java 18行 / 合っていた
- 要件2「終了の年月が開始の年月より前の期間と、職歴どうしの期間の重なりを断る」: J/domain/model/resume/Period.java 60-72行、J/domain/model/resume/Resume.java 283行、343行 / 合っていた
- 要件3の受入基準1と2「Java 版は、ほかの利用者の経歴書の要求に無い経歴書と同じ答えを返し、自分の経歴書に無い項目の要求に無い項目の答えを返す」: J/usecase/resume/UpdateCareerUseCase.java、DeleteCareerUseCase.java、ResumeIdResolver.java / 合っていた
- 要件3の受入基準3「Java 版は、項目の数の上限を、経歴書が誰のものかより先に確かめる」: J/usecase/resume/CreateCareerUseCase.java 44-52行、J/usecase/resume/policy/ResumeLimitChecker.java / 合っていた
- 要件3の受入基準4「認証のまとまりの spec が、すでに居ない利用者の要求は検査を通るとし、答えを操作を作るまとまりの spec で Java 版と同じにすると決めた」: .kiro/specs/backend-go-auth/requirements.md 113行 / 合っていた
- 要件4「マスタと経歴書の操作は、メールを送らず、ログインの状態の保存先にも書かない」: J/usecase/resume/ を `Redis|Mail|Ses|Email` で Grep(一致なし)/ 合っていた
- 要件4の受入基準2「比べる検査は、データベースに残ったデータを比べる」: backend/compat/harness/compare.go 340行(CompareDB)、backend/compat/harness/snapshot.go 24行(DumpDatabase)/ 合っていた
- 要件4の受入基準3「要求のたびに違う値は、形が同じかを確かめる。前の答えと同じ値になるかを確かめる」: backend/compat/harness/normalize.go 16-25行、122-132行、157-180行 / 合っていた(日時は形だけを比べ、時刻は比べない。R1-1-2)
- 要件4の受入基準4「Java 版は、項目の ID の場所に ID の形でない文字を入れた要求に 500 で答える」: J/presentation/resume/controller/UpdateCareerController.java 45-46行、J/presentation/shared/AppExceptionHandler.java 173-183行 / 合っていた
- 要件5の受入基準2「画面は、経歴書の一覧に、経歴書ごとの作成と更新の日時を見せる」: frontend/src/features/resume/components/resume-list/ResumeCard.tsx 46-59行 / 合っていた
- 要件5の受入基準3「版をまたいで確かめる検査は CI で動き、通らない PR は main に入らない」: .github/workflows/ci.yaml 474-509行(backend-compat の `make compat-cross`)、525-542行(backend のまとめの仕事が結果を読む)/ 合っていた
- 要件5の受入基準3「版をまたいで確かめる検査は、1つ目の要求を一方の版に送り、2つ目からの要求をもう一方の版に送る」: backend/compat/harness/cross.go 16-26行、40-83行、backend/compat/harness/scenario.go 167-172行 / 合っていた(検査は1つの筋書きを3つの送り先の組で動かし、段の `to: other` で版を替え、最後の段を必ず前と違う版に送る。応答で確かめるのは状態の番号と項目の有無だけである。R1-1-3)
- 要件6の受入基準1「Java 版は、資格と SNS の名前の一覧を返すときに並べ方を指定していない」: J/infrastructure/query/certification/CertificationQueryMapper.xml 8-14行、J/infrastructure/query/snsplatform/SnsPlatformQueryMapper.xml 8-14行 / 合っていた
- 要件6の受入基準1「Java 版は、作成と更新の日時を、時差を持たない日時として作る」: J/domain/model/resume/Resume.java 139-140行(`LocalDateTime.now()`)/ 合っていた
- 要件6の受入基準3「進み具合の表の状態『作り終えた』『比べる検査に通った』」: .kiro/specs/backend-go-replacement/progress.md / 合っていた

### 申告

**1. ほかの利用者の経歴書に項目を足す要求に、Java 版と違う答えを返す** — requirements.md 要件3の受入基準3、要件1の受入基準1

- Issue の記載: なし。Issue は、置き換えの spec の要件9の受入基準5(目にしない動きを変えてよい)と受入基準6(変えた動きの一覧)を満たすことだけを求めている
- 決めたこと: Java 版は、その欄の項目の数が上限に達しているときだけ上限の答えを返す。Go 版は、いつも無い経歴書の答えを返す。違いを、変えた動きの一覧に載せる
- 他にありえた選択肢: Java 版と同じ答え(上限の答え)のままにする
- 外れていた場合: 所有者が Java 版と同じ答えを望んでいたときは、Go 版の検査の順と筋書きと変えた動きの一覧を直すことになる

**2. Java 版が 500 で答える要求に、Go 版は 400 か 404 で答える** — requirements.md 要件4の受入基準4、要件3の受入基準4

- Issue の記載: なし
- 決めたこと: Java 版が 500 で答える要求のすべてに、Go 版は要求の誤りか対象が無いことを示す状態の番号で答える。どちらにするかは設計で決める。退会した利用者の要求に Java 版が 500 で答えるときも、同じ扱いにする
- 他にありえた選択肢: Java 版と同じ 500 のままにする。認証のまとまりの spec と同じく、400 に決め打ちする
- 外れていた場合: 変えた動きの一覧に載る件数と、筋書きが期待する答えが変わる。退会した利用者の要求は、画面が送ることのある要求なので、所有者が違いを受け入れないときは作り直しになる(R1-1-4)

**3. 版をまたぐ筋書きを足す** — requirements.md 要件5の受入基準3

- Issue の記載: 置き換えの spec の要件13の受入基準1と2はある。版をまたいで確かめる検査を求める要件13の受入基準6は、Issue の一覧に無い
- 決めたこと: 経歴書の作成、項目の追加、更新、削除、経歴書の削除を続ける筋書きを、版をまたいで確かめる検査に足す
- 他にありえた選択肢: 筋書きを足さず、版ごとの比べる検査だけで確かめる
- 外れていた場合: 足す分には手戻りは小さい。足さないと、要件13の受入基準1と2を機械で確かめる手段が無くなる

**4. 応答の時間を測る主な操作を5つに決めた** — requirements.md 要件4の受入基準5

- Issue の記載: なし。置き換えの spec も、まとまりごとの主な操作を挙げていない
- 決めたこと: 経歴書の一覧の取得、経歴書1件の取得、基本の情報の更新、プロジェクトの項目の更新、技術スタックのマスタの取得の5つを測る
- 他にありえた選択肢: 26の操作のすべてを測る。経歴書の作成(コピー)や項目の追加も測る
- 外れていた場合: 測らなかった操作が Java 版より遅くても、検査は止めない

**5. 設計の前に試しに作る動きを5つに決めた** — requirements.md 要件6の受入基準1

- Issue の記載: 置き換えの spec の要件2の受入基準5を満たすことだけを求めている
- 決めたこと: 資格と SNS の一覧の並び、日時の保存と読み方、空白と文字数、https の判定、年月の読み方の5つを「少なくとも」試す
- 他にありえた選択肢: 段階1で試作しなかった、文字列の配列の列、複数の SQL の文、UUID の比べ方と読み方も一覧に入れる(R1-1-1)
- 外れていた場合: 一覧に無い動きが設計のあとに Java 版と同じにできないと分かると、spec を承認し直すことになる

### 指摘

| ID | レベル | 該当箇所 | 内容 | 直し方の案 |
|---|---|---|---|---|
| R1-1-1 | 中 | requirements.md 範囲の前提の3つ目、要件6の受入基準1 | 事実の誤り。本文は「マスタと経歴書の操作に当たる動きのうち、次の2つを試しに作らなかった」と書くが、.kiro/specs/backend-go-replacement/research.md 37-45行で「試作せず」の動きのうち、経歴書の操作に当たるものは2つより多い。E3(文字列の配列の列。ResumeMapper.xml のプロジェクトの技術スタックの列)、E4(複数の SQL の文を1回で送る箇所。ResumeMapper.xml の insertProject、updateProject、deleteProject)、E5 の2行目(同じ名前のときの UUID の比べ方。ResumeEntryOrderPolicy.java が、職歴・プロジェクト・資格の同じ日付の項目を UUID の順で並べる)、F3(UUID の読み方。UpdateCareerController.java 46行が項目の ID を UUID で受ける)も試作していない。要件6の受入基準1の5つにも、この4つは入っていない。「2つ」と言い切った文を残すと、設計の前に試す動きが5つで足りると読める | 前提の文を、research.md の表のとおりに、経歴書の操作に当たる「試作せず」の動きを全部挙げる形に直す。要件6の受入基準1の一覧に、この4つを足すか、足さない動きごとに、試さなくてよい理由を書く |
| R1-1-2 | 高 | requirements.md 要件4の受入基準3、要件5の受入基準2 | Go 版が保存する作成と更新の日時が、正しい時刻(Java 版と同じ日本の時刻)であることを確かめる受入基準が無い。要件4の受入基準3は、日時を形だけ確かめるとし、比べる検査も時刻を比べない(backend/compat/harness/normalize.go 157-180行。データベースの値も同じ置き換えをする)。要件5の受入基準2は、2つの版が同じ値を同じ時刻として返すことだけを求める。そのため、Go 版が日時を世界標準時で保存しても、どの受入基準にも反しない。そのときは、Go 版で作った経歴書の日時が、画面の一覧で9時間ずれて見える。Java 版は `LocalDateTime.now()`(Resume.java 139-140行)で、時差を持たない日本の時刻を保存している | 要件4か要件5に受入基準を足す。例: 「Go 版が保存する作成と更新の日時は、要求を受けた時の日本の時刻である。比べる検査は、同じ段で Java 版と Go 版が保存した日時の差が、設計で決めた幅の内側にあるかを確かめる」 |
| R1-1-3 | 中 | requirements.md 要件5の受入基準3 | 受入基準3の筋書きでは、受入基準1と2の一部を確かめられない。筋書きは「1つ目の要求を一方の版に送り、2つ目からの要求をもう一方の版に送る」ので、項目の追加と更新と削除は同じ版に届く。受入基準1の「一方の版で足した項目を、もう一方の版で直し、消せる」を確かめる段が無い。また、筋書きの5つの操作に読み取りが無く、受入基準2(日時を同じ時刻として返す)を確かめる段も無い。今の検査は、応答の状態の番号と項目の有無だけを確かめ、値を比べない(backend/compat/harness/scenario.go 167-172行)。なお、今の検査は1つの筋書きを3つの送り先の組(Java から Go、Go から Java、交互)で動かすので(backend/compat/harness/cross.go 16-26行)、向きごとに筋書きを書く必要は無い | 筋書きに、項目を足した版と違う版で、その項目を直し、消す段を入れると書く。一方の版が保存した経歴書をもう一方の版で読み、作成と更新の日時が保存した版の答えと同じ値であることを確かめる段を入れると書く。値を比べる手段を検査に足すことを、この spec で決めることに含める |
| R1-1-4 | 低 | requirements.md 要件4の受入基準4、要件3の受入基準4 | 要件4の受入基準4は「画面はこのような要求を送らないので、この違いは利用者の目に触れない」と書くが、要件3の受入基準4が同じ扱いにする、退会した利用者のログインの状態を持つ要求は、画面が送ることがある(別の端末でログインしたままの画面)。この要求については、理由の文が当てはまらない | 退会した利用者の要求については、理由を分けて書く。例: 「利用者は、どちらの答えでも操作を終えられず、画面はエラーを見せる」 |

- 往復: 1回目 / 高1 中2 低1

## サイクル1 往復2(2026-11-14)

### 審査の範囲

範囲: 差分

- requirements.md 範囲の「この spec で決めること」(3つから4つ): 差分の行。足した4つ目は要件5の受入基準3の直しと対になるので、要件5の受入基準3と合わせて読んだ
- requirements.md 範囲の前提の1つ目と4つ目: 差分の行(文を分けただけで、中身は変わっていない)
- requirements.md 範囲の前提の3つ目(2つから6つ): 差分の行。「技術スタック」「1回の送信」「ID の順」「ID の読み方」で本文を検索し、要件6の受入基準1の足した4つと対応するかを見た
- requirements.md 要件1の受入基準1: 差分の行。指す先の要件3の受入基準3と要件4の受入基準4の文と食い違わないかを見た
- requirements.md 要件4の受入基準3: 差分の行。「日時」で本文を検索し、要件5の受入基準2と要件6の受入基準1の2つ目(日時の保存の仕方)を合わせて読んだ。足した確かめが今の比べる検査の環境で成り立つかを、実ファイルで確かめた
- requirements.md 要件4の受入基準4: 差分の行。「退会」で本文を検索し、要件3の受入基準4と食い違わないかを見た
- requirements.md 要件5の受入基準2と3: 差分の行。受入基準1(直しは無い)は、受入基準3の筋書きが確かめる対象なので合わせて読んだ
- requirements.md 要件6の受入基準1(5つから9つ): 差分の行
- はじめに、要件2、要件3、要件4の受入基準1と2と5、要件6の受入基準2と3: 差分の語が現れないか、現れても文の意味が変わらないので、読み直していない

### 実ファイルで確かめた文

パスの `J/` は `backend/src/main/java/com/example/keirekipro/` を指す。

- 範囲の前提3「段階1で、マスタと経歴書の操作に当たる動きのうち、次の6つを試しに作らなかった」: .kiro/specs/backend-go-replacement/research.md 38行(E2)、39行(E3)、40行(E4)、42行(E5 の2行目)、43行(F1)、45行(F3)/ 合っていた
- 要件6の受入基準1「Java 版は、技術スタックの種類ごとに、名前の並びを1つの列に入れて保存する」: J/infrastructure/repository/resume/ResumeMapper.xml 36-43行、367-374行、437-469行(`stringListTypeHandler`)/ 合っていた
- 要件6の受入基準1「Java 版は、プロジェクトの項目と、その項目の技術スタックを、データベースへの1回の送信で保存する」: J/infrastructure/repository/resume/ResumeMapper.xml 275-317行(insertProject が `;` で区切った2つの文を持つ)、411-435行(updateProject)/ 合っていた
- 要件6の受入基準1「Java 版は、6つの欄の項目を、期間か、取得の年月か、名前で並べ、それが同じ項目どうしを ID の順に並べる」: J/domain/policy/resume/ResumeEntryOrderPolicy.java 50-168行、276-287行 / 合っていた
- 要件6の受入基準1「要求の中の経歴書と項目の ID の読み方」: J/presentation/resume/controller/UpdateCareerController.java 45-46行(経歴書の ID は String、項目の ID は UUID で受ける)/ 合っていた
- 要件5の受入基準3「今の版をまたいで確かめる検査は、答えの状態の番号と、答えに項目があるかどうかだけを確かめ、値を比べない」: backend/compat/harness/scenario.go 167-172行(Expect は Status と Fields だけを持つ)/ 合っていた
- 要件5の受入基準2「Java 版と同じく、要求を受けた時の日本の時刻として保存する」と、要件4の受入基準3「同じ要求を受けて2つの版がそれぞれ保存した日時の差が、設計で決めた幅の内側にあることも確かめる」: J/domain/model/resume/Resume.java 139-140行、terraform/modules/ecs/main.tf 62-63行、docker/backend/Dockerfile.prod、backend/compat/harness/versions.go 72-92行、backend/compat/harness/images.go 44行、backend/src/main を `setDefault|ZoneId|user.timezone|Asia/Tokyo` で Grep(一致なし)/ 食い違っていた(R1-2-1)。Java 版が日本の時刻で保存するのは、本番の ECS がコンテナに `TZ=Asia/Tokyo` を渡しているからである。Java 版のコードとイメージは時間帯を決めていない。比べる検査と版をまたいで確かめる検査が Java 版のコンテナに渡す環境変数(JavaEnv)には `TZ` が無い

### 申告

**1. 版をまたいで確かめる検査に、値を比べる手段を足す** — requirements.md 範囲の「この spec で決めること」の4つ目、要件5の受入基準3

- Issue の記載: なし。Issue は、置き換えの spec の要件13の受入基準1と2を満たすことだけを求めている
- 決めたこと: 段階2で作った検査の土台(backend/compat/harness)を、この spec で直し、前の段の答えの値とあとの段の答えの値を比べられるようにする
- 他にありえた選択肢: 検査の土台を置き換えの spec の側で直す。値を比べず、データベースの中身を版ごとの比べる検査だけで確かめる
- 外れていた場合: 検査の土台は、ほかのまとまりの spec も使う。この spec で決めた筋書きの書き方が、ほかのまとまりの筋書きと合わないと、土台を直し直すことになる

**2. 2つの版が保存した日時の差を、設計で決めた幅で比べる** — requirements.md 要件4の受入基準3

- Issue の記載: なし
- 決めたこと: 比べる検査は、同じ要求を受けて2つの版が保存した日時の差が幅の内側かを確かめる。幅は設計で決める
- 他にありえた選択肢: Go 版だけについて、保存した日時が要求を送った時の日本の時刻に近いかを確かめる(Java 版の値と比べない)。Go 版の単体のテストで時間帯を確かめる
- 外れていた場合: 幅が広すぎると時差の誤りを見逃し、狭すぎると検査がときどき落ちる。Java 版の値と比べる方式は、検査の環境の Java 版の時間帯に左右される(R1-2-1)

### 指摘

| ID | レベル | 該当箇所 | 内容 | 直し方の案 |
|---|---|---|---|---|
| R1-2-1 | 中 | requirements.md 要件4の受入基準3、要件5の受入基準2 | 事実の食い違い。本文は、Go 版が日時を「Java 版と同じく、要求を受けた時の日本の時刻として保存する」とし、比べる検査が「2つの版がそれぞれ保存した日時の差」を確かめるとする。Java 版は `LocalDateTime.now()`(Resume.java 139-140行)で、コンテナの時間帯の時刻を保存する。日本の時刻になるのは、本番の ECS が `TZ=Asia/Tokyo` を渡すからである(terraform/modules/ecs/main.tf 62-63行)。Java 版のコードにもイメージ(docker/backend/Dockerfile.prod)にも、時間帯の指定は無い。比べる検査と版をまたいで確かめる検査は、このイメージを使い(backend/compat/harness/images.go 44行)、Java 版のコンテナに `TZ` を渡さない(backend/compat/harness/versions.go 72-92行)。そのため、今の検査の環境では、Java 版は日本の時刻で保存しない見込みが高く、日本の時刻で保存する正しい Go 版との差は約9時間になる。足した確かめは、このままでは正しい Go 版で落ちる。本文には、Go 版が時間帯を何から決めるか(日本の時刻に固定するか、Java 版と同じくコンテナの `TZ` に従うか)と、検査の環境の Java 版の時間帯をどうするかが無い。検査を通すために Go 版を検査の環境の Java 版に合わせると、R1-1-2 で塞いだ穴(日本の時刻でない保存)が戻る | 要件5の受入基準2に、Java 版が日本の時刻で保存するのは、本番でコンテナの時間帯を日本にしているからであることを書く。Go 版が時間帯を何から決めるかを書く(例: 「Go 版は、コンテナの時間帯の設定によらず、日本の時刻で保存する」)。要件4の受入基準3に、比べる検査の環境で Java 版のコンテナの時間帯を本番と同じ日本にすることを書くか、設計で決めると書く。検査の土台を直すことになるので、範囲の「この spec で決めること」にも足す |

- 往復: 2回目 / 高0 中1 低0

## サイクル1 往復3(2026-11-14)

### 審査の範囲

範囲: 差分

- requirements.md 範囲の「この spec で決めること」(4つから5つ): 差分の行。足した5つ目は要件4の受入基準3の足した文と対になるので、合わせて読んだ。箇条の数(5つ)と見出しの数が合うことを見た
- requirements.md 要件4の受入基準3(Java 版を本番と同じ日本の時間帯で動かす文を足した): 差分の行。「時間帯」「日本の時刻」で本文を検索し、要件5の受入基準2と3、要件6の受入基準1の2つ目(日時の保存の仕方と読み方)と食い違わないかを見た
- requirements.md 要件4の受入基準4: 差分の行(文を分けただけで、中身は変わっていない)。「退会」で本文を検索し、要件3の受入基準4と要件1の受入基準1と食い違わないことを見た
- requirements.md 要件5の受入基準2: 差分の行。足した文が挙げる環境(本番、比べる検査、版をまたいで確かめる検査)が、要件4の受入基準3と範囲の5つ目と合うことを見た
- requirements.md 要件6の題名と前置きの段落: 差分の行。「進み具合」で本文を検索し、要件6の受入基準3と、はじめにの表(要件6の受入基準1と2を指す行)と食い違わないことを見た
- はじめに、範囲の「決めないこと」と前提、要件1、要件2、要件3、要件4の受入基準1と2と5、要件5の受入基準1と3、要件6の受入基準1から3: 差分の語が現れないか、現れても文の意味が変わらないので、読み直していない

### 実ファイルで確かめた文

- 要件5の受入基準2「Java 版は、本番では時間帯を日本に設定したコンテナで動く」: terraform/modules/ecs/main.tf 56-69行(62-63行が `TZ` = `Asia/Tokyo`)/ 合っていた
- 要件4の受入基準3と範囲の5つ目「検査の環境の Java 版が本番と違う時間帯で動く」(今の検査は Java 版に時間帯を渡していないという前提): backend/compat/harness/versions.go 72-92行(JavaEnv が返す環境変数に `TZ` が無い)/ 合っていた
- 要件5の受入基準2「Go 版は、どの環境でも、日本の時刻として保存する」(今の Go 版の土台と認証のまとまりの書き方と食い違わないか): backend/internal/platform/database/database.go 19行、47行(接続ごとに時間帯を `Asia/Tokyo` にする)、backend/internal/auth/accesstoken.go 21-23行(時間帯を固定の値で持ち、コンテナの設定を読まない)/ 合っていた
- 要件6の前置き「所有者は、置き換えがどこまで進んだかを、置き換えの spec の進み具合の表で、機能のまとまりごとに見る」: .kiro/specs/backend-go-replacement/requirements.md 188-190行(要件7)、.kiro/specs/backend-go-replacement/progress.md 28-40行(まとまりの表。マスタと経歴書の行は38行)/ 合っていた

### 申告

**1. 検査の環境の Java 版を、日本の時間帯で動かす** — requirements.md 範囲の「この spec で決めること」の5つ目、要件4の受入基準3

- Issue の記載: なし
- 決めたこと: Java 版と Go 版を比べる検査と、版をまたいで確かめる検査で、Java 版のコンテナを本番と同じ日本の時間帯で動かす。段階2で作った検査の土台(backend/compat/harness)を、この spec で直すことになる
- 他にありえた選択肢: 検査の土台を置き換えの spec の側で直す。Java 版の時間帯を変えず、Go 版の日時だけを、要求を送った時の日本の時刻と比べる
- 外れていた場合: 検査の土台は、認証のまとまりの筋書きも動かす。Java 版の時間帯を変えると、認証のまとまりの筋書きで Java 版が保存する日時も変わるので、認証のまとまりの筋書きが通り続けるかを、設計か実装で確かめることになる

**2. Go 版は、コンテナの時間帯の設定によらず、日本の時刻で保存する** — requirements.md 要件5の受入基準2

- Issue の記載: なし
- 決めたこと: Go 版は、本番と2つの検査のどの環境でも、日本の時刻で保存する。Java 版は、コンテナの時間帯の設定に従う
- 他にありえた選択肢: Go 版も、Java 版と同じくコンテナの時間帯の設定に従う
- 外れていた場合: 手戻りは小さい。本番はどちらの版にも日本の時間帯を渡すので、本番の動きは変わらない

### 指摘

この往復の指摘は無い(高0 中0 低0)。R1-2-1 は、要件5の受入基準2、要件4の受入基準3、範囲の5つ目の直しで解消した。

| ID | レベル | 該当箇所 | 内容 | 直し方の案 |
|---|---|---|---|---|

- 往復: 3回で収束 / 未解決: 0件

## サイクル2 往復1(2026-11-14)

### 審査の範囲

範囲: 差分

- requirements.md 範囲の「この spec で決めること」(5つから4つ): 差分の行。見出しの数(4つ)と箇条の数(4つ)が合うことを見た。消した箇条(検査が値を比べられるようにすること)は要件5の受入基準3の直しと対になるので、合わせて読んだ
- requirements.md 要件5の受入基準3の末尾の段落: 差分の行。「値を比べ」「比べられる」「取り出し」で requirements.md を検索し、検査に値を比べる手段を足すと書いた文が、ほかの箇所に残っていないことを見た(一致は要件5の受入基準3の1行だけ)
- requirements.md 要件5の受入基準1と2: 受入基準3の筋書きが確かめる対象なので合わせて読んだ。直した文は、3つ目の段(項目の値と、作成と更新の日時が同じであること)を今ある比べ方で確かめると書いており、受入基準1と2を確かめる手段は減っていない
- はじめに、範囲の「決めないこと」と前提、要件1から要件4、要件6: 差分の語が現れないので、読み直していない

### 実ファイルで確かめた文

- 要件5の受入基準3「版をまたいで確かめる検査は、前の段の答えから値を取り出し、あとの段の答えの値と比べられる」: backend/compat/harness/scenario.go 110行(Step の Capture)、194-195行(Expect の Values。値に {名前} を差し込める)、backend/compat/harness/send.go 145行(版に送る段の応答から capture で値を取り出す)、231-251行(captureValue)、backend/compat/harness/capture.go 199-244行(expand と expandJSON が {名前} を取り出した値に置き換える)、backend/compat/harness/steps.go 94-131行(CheckValues)、135-137行(checkStepExpect)、backend/compat/harness/cross.go 183-185行(版をまたぐ動かし方が、版に送る段の応答を checkStepExpect で確かめる)、backend/compat/scenarios/users/cross-update.yaml 31行、46行、88行、107行(capture と values を使っている筋書き)/ 合っていた
- 要件5の受入基準3「版をまたいで確かめる検査は、この筋書きを、Java 版から Go 版への向きと、Go 版から Java 版への向きの両方で動かす」(差分の行に続く、直していない文): backend/compat/harness/cross.go 16-26行 / 合っていた

### 申告

この往復の差分に、新しく決めたことは無い。差分は、サイクル1 往復2 の申告1(版をまたいで確かめる検査に、値を比べる手段を足す)を取り下げる直しである。値を比べる手段は #851 で main に入っており、この spec は検査の土台のこの箇所を直さなくなった。

### 指摘

| ID | レベル | 該当箇所 | 内容 | 直し方の案 |
|---|---|---|---|---|
| R2-1-1 | 低 | requirements.md 要件5の受入基準3 | 事実の誤りではなく、設計への覚え書きである。capture は、取り出した値を文字にして覚える(backend/compat/harness/send.go 241-248行。数と真偽の値も文字になる。並びと入れ子の値は取り出せない)。expect の values の `{名前}` は文字の値として置き換わるので(backend/compat/harness/capture.go 217-220行)、前の段から取り出した真偽の値や数を、あとの段の真偽の値や数と比べると、型が違って合わない。作成と更新の日時と ID は文字なので、取り出して比べられる。項目の値のうち、真偽の値(職歴の `active` など)と並び(技術スタックなど)は、筋書きが送った値を expect の values にそのまま書けば比べられる(cross-update.yaml 88行、107行と同じ書き方) | requirements は直さなくてよい。design で、筋書きの3つ目の段を書くときに、日時と ID は capture で取り出して比べ、真偽の値と並びは送った値を values にそのまま書く、と決める |

- 往復: 1回で収束 / 未解決: 0件
