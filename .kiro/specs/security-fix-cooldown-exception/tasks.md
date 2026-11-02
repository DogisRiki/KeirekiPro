# タスク

- [x] 1. 判定に使う確認のスクリプトを作る
- [x] 1.1 公開から72時間経っていない版を脆弱性の警告に照らすスクリプトを作る (並行可)

  Claude は、部品「cooldown-match-alerts.sh」と、そのテスト `test-cooldown-match-alerts.sh` を、置き場所の `place-1/.github/scripts/` と、テストを置く `place-1/.github/scripts/tests/` に作る。このスクリプトは、Dependabot の警告の API を部品ごとに読み、版ごとに、72時間待たずに入れてよいかと、理由の種類と、理由になった警告を返す。
  - 完了の確かめ方: Linux のコンテナで流した `test-cooldown-match-alerts.sh` の場合が、すべて通る。`KP_TEST_CASE` に場合の名前を入れると、その場合だけが流れる。このタスクで作るか変えたスクリプトとテストに流した shellcheck の指摘が0件である
  - 受入基準とテストの対応: 要件1の受入基準1(本番で動く部品の high か critical の警告の最初の修正版は入る)は、テストの「high の警告の最初の修正版は eligible になる」で確かめる。要件1の受入基準3(警告が2つ以上あれば、どの最初の修正版も入る)は「high と critical の警告が2つあれば、満たす警告がすべて返る」で確かめる。要件1の受入基準4(深刻度が低い警告)は「medium の警告だけなら low-severity になる」で確かめる。要件1の受入基準5(開発のときだけ使う部品)は「scope が development なら development になる」で確かめる。要件1の受入基準6(本番で動くかが載っていない警告)は「scope が null なら no-scope になる」で確かめる。要件2の受入基準1(最初の修正版より新しい版は入らない)は「最初の修正版より新しい版は not-first-patched になり、最初の修正版が返る」で確かめる。あわせて、「警告の API が失敗したら alerts-unreadable になる」「条件を満たさない警告がいくつかあれば、最初の修正版の一致に最も近い理由を返す」「入力が JSON の配列でなければ終了コード 2 になる」のテストを作る
  - _要件: 1.1, 1.3, 1.4, 1.5, 1.6, 2.1_
  - _対象の部品: cooldown-match-alerts.sh_

- [x] 1.2 部品を悪意のある部品の一覧に照らすスクリプトを作る (並行可)

  Claude は、部品「cooldown-check-malware.sh」と、そのテスト `test-cooldown-check-malware.sh` を、置き場所の `place-1/.github/scripts/` と、テストを置く `place-1/.github/scripts/tests/` に作る。このスクリプトは、部品の一覧を OSV の querybatch に1000件ずつ送り、部品ごとに、悪意のある部品として公表されているかと、公表の記載を返す。
  - 完了の確かめ方: Linux のコンテナで流した `test-cooldown-check-malware.sh` の場合が、すべて通る。このタスクで作るか変えたスクリプトとテストに流した shellcheck の指摘が0件である
  - 受入基準とテストの対応: 要件3の受入基準1(変更で入るすべての部品を一覧に照らす)は、テストの「MAL- の ID が返った部品は malicious になる」「GHSA- の ID で CWE-506 を含む部品は malicious になり、含まない部品は clean になる」で確かめる。要件3の受入基準2(一覧に照らせなければ入らない)は「querybatch が失敗したら、送った部品がすべて unknown になる」「vulns の取得が失敗したら、その ID を持つ部品が unknown になる」で確かめる。要件7の受入基準3(公表の記載が出る)のうち、スクリプトが公表の記載を返すことは「malicious の部品に、ID と要約と URL が返る」で確かめる。あわせて、「next_page_token が付いた要素だけが送り直される」「1001件の入力は2回に分けて送られる」「maven の部品は ecosystem を Maven にし、名前を groupId:artifactId のまま送る」のテストを作る
  - _要件: 3.1, 3.2, 7.3_
  - _対象の部品: cooldown-check-malware.sh_

- [x] 1.3 npm の部品の署名した者を比べるスクリプトを作る (並行可)

  Claude は、部品「cooldown-check-signer.sh」のうち npm の部品を比べる部分と、そのテスト `test-cooldown-check-signer.sh` を、置き場所の `place-1/.github/scripts/` と、テストを置く `place-1/.github/scripts/tests/` に作る。このスクリプトは、前の版と新しい版の SLSA の来歴の証明書から、design.md の cooldown-check-signer.sh の節に書いた3つの欄を読んで比べ、新しい版の来歴を `gh attestation verify` で検証する。来歴とは、その版をどのリポジトリのどの組み立ての設定で作ったかを、組み立てたサービスが署名して残した記録である。
  - 完了の確かめ方: Linux のコンテナで流した `test-cooldown-check-signer.sh` の npm の場合が、すべて通る。テストのスタブが返す来歴の証明書は、実際の npm の部品の来歴から1回取った証明書をもとにしてある。スタブとは、テストのときに、外部のサービスやコマンドの代わりに決まった答えを返す偽物である。このタスクで作るか変えたスクリプトとテストに流した shellcheck の指摘が0件である
  - 受入基準とテストの対応: 要件4の受入基準1(署名した者が前の版と同じときだけ入る)と受入基準2(署名した者は署名から分かる公開元の身元)は、テストの「3つの欄が同じなら same になる」「元のリポジトリの ID が違えば different になる」「組み立ての設定の URI の @ より後ろだけが違えば same になる」で確かめる。要件4の受入基準1のうち、新しい版に署名が無いときは「前の版に来歴があり新しい版に無ければ no-new-signature になる」で確かめる。要件4の受入基準3(公開元を見分けられない署名は署名が無いものとして扱う)は「registry の署名と publish attestation だけがある版は、署名が無いものとして扱う」で確かめる。要件4の受入基準4(前の版に署名が無ければ止める理由にならない)は「前の版に来歴が無ければ no-prior-signature になる」で確かめる。要件4の受入基準5(署名を調べられなければ入らない)は「gh attestation verify が失敗したら unknown になる」「来歴の取得が失敗したら unknown になる」「tgz が dist.integrity と合わなければ unknown になる」で確かめる
  - _要件: 4.1, 4.2, 4.3, 4.4, 4.5_
  - _対象の部品: cooldown-check-signer.sh_

- [x] 1.4 maven の部品の署名した者を比べる部分を足す

  Claude は、部品「cooldown-check-signer.sh」に maven の部品を比べる部分を足し、テスト `test-cooldown-check-signer.sh` に maven の場合を足す。このスクリプトは、`.pom.asc` の発行者の指紋で、公開鍵を配る鍵サーバから公開鍵を取り、使い捨ての `GNUPGHOME` で署名を検証し、`VALIDSIG` の主鍵の指紋を比べる。`.pom.asc` に発行者の指紋が無いときは、このスクリプトは、発行者の鍵 ID で鍵サーバから公開鍵を取る。指紋とは、鍵の中身から計算した、鍵を見分けるための値である。鍵 ID とは、指紋の後ろの16桁である。主鍵とは、公開元の鍵の中心になる鍵で、公開元が署名に使う副鍵を替えても変わらない。このタスクは、npm の部品の署名した者を比べるスクリプトを作るタスク 1.3 と同じファイルを変えるので、1.3 のあとに行う。
  - 完了の確かめ方: Linux のコンテナで流した `test-cooldown-check-signer.sh` の npm と maven の場合が、すべて通る。テストの署名と鍵は、テストの中で作った使い捨ての鍵で作ってある。加えて、テストは、Claude が、署名に発行者の鍵 ID だけを持つ backend の部品 `org.postgresql:postgresql` の今の版と1つ前の版から1回取った `.pom` と `.pom.asc` と鍵サーバの公開鍵で、主鍵の指紋が同じなら same になる場合を持つ。取った署名から発行者の指紋も鍵 ID も読めないと分かったときは、Claude は、design.md の maven の部品の比べ方を見直すきっかけとして所有者に報告して止まる。このタスクで作るか変えたスクリプトとテストに流した shellcheck の指摘が0件である
  - 受入基準とテストの対応: 要件4の受入基準1(署名した者が前の版と同じときだけ入る)と受入基準2(署名した者は署名から分かる公開元の身元)は、テストの「主鍵の指紋が同じなら same になる」「主鍵の指紋が違えば different になる」「副鍵が替わっても主鍵が同じなら same になる」「発行者の指紋が無い署名は鍵 ID で鍵を取る」で確かめる。要件4の受入基準1のうち、新しい版に署名が無いときは「前の版に .pom.asc があり新しい版の .pom.asc が 404 なら no-new-signature になる」で確かめる。要件4の受入基準4(前の版に署名が無ければ止める理由にならない)は「前の版の .pom.asc が 404 なら no-prior-signature になる」で確かめる。要件4の受入基準5(署名を調べられなければ入らない)は「鍵を取れなければ unknown になる」「VALIDSIG が出なければ unknown になる」で確かめる。あわせて、「Maven Central が 404 を返す部品は Gradle Plugin Portal の署名を読む」のテストを作る
  - _要件: 4.1, 4.2, 4.4, 4.5_
  - _依存: 1.3_

- [x] 1.5 除外の欄に版の要素があるかを確かめるスクリプトを作る (並行可)

  Claude は、部品「cooldown-check-pnpm-exclude.sh」と、そのテスト `test-cooldown-check-pnpm-exclude.sh` を、置き場所の `place-1/.github/scripts/` と、テストを置く `place-1/.github/scripts/tests/` に作る。このスクリプトは、`frontend/pnpm-workspace.yaml` の `minimumReleaseAgeExclude` を読み、渡された npm の版ごとに、その版を指す要素があるかと、足すべき1行を返す。
  - 完了の確かめ方: Linux のコンテナで流した `test-cooldown-check-pnpm-exclude.sh` の場合が、すべて通る。このタスクで作るか変えたスクリプトとテストに流した shellcheck の指摘が0件である
  - 受入基準とテストの対応: 要件1の受入基準8(72時間待たずに入った版は、マージのあとも CI と開発者の環境と本番の組み立てで入れられる)のうち、版を指す要素を見分けることは、テストの「name@1.2.3 の要素は present になる」「name@1.2.3 || 1.2.4 の要素は present になる」「名前だけの要素とパターンの要素は present にならない」で確かめる。あわせて、「[...] の中に並べて書かれていたら終了コード 2 になる」「ファイルが無ければ終了コード 2 になる」「スコープ付きの名前と、' か \" で囲んだ要素を読む」「line に足すべき1行が入る」のテストを作る
  - _要件: 1.8_
  - _対象の部品: cooldown-check-pnpm-exclude.sh_

- [x] 1.6 記録のコメントを書き、読むスクリプトを作る (並行可)

  Claude は、部品「record-cooldown-exception.sh」と、そのテスト `test-record-cooldown-exception.sh` を、置き場所の `place-1/.github/scripts/` と、テストを置く `place-1/.github/scripts/tests/` に作る。このスクリプトは、`lib-notice-comment.sh` の `notice_post` と `notice_last_kind` を使い、design.md のデータの形の節の形の記録のコメントを head ごとに1つ書くことと、PR に記録のコメントがあるかを読むことを受け持つ。head とは、PR のブランチの最新のコミットである。
  - 完了の確かめ方: Linux のコンテナで流した `test-record-cooldown-exception.sh` の場合が、すべて通る。書いたコメントの記録の JSON の行を base64 から戻すと、渡した記録の JSON と同じになる。このタスクで作るか変えたスクリプトとテストに流した shellcheck の指摘が0件である
  - 受入基準とテストの対応: 要件5の受入基準1(記録に、部品の名前と版と公開日時と警告と PR が載る)は、テストの「書いたコメントの表と記録の JSON に、部品と版と公開日時と警告と PR の番号が入る」で確かめる。要件5の受入基準2(記録が残るときだけ入る)は「書けなかったら終了コード 1 になる」で確かめる。要件5の受入基準4(記録が残る)のうち、記録のコメントを消さないことは「同じ head で2回呼んでもコメントは1つで、消す API を呼ばない」で確かめる。要件1の受入基準2(所有者の承認を求める)のうち、記録のコメントの有無を読むことは「github-actions[bot] が書いた記録のコメントがあれば exists=true になる」「ほかの者が書いた同じ目印のコメントは数えない」「コメントの一覧を読めなければ終了コード 1 になる」で確かめる。あわせて、「部品の名前に --> が入っても HTML のコメントが途中で閉じない」のテストを作る
  - _要件: 1.2, 5.1, 5.2, 5.4_
  - _対象の部品: record-cooldown-exception.sh_

- [x] 2. 判定のスクリプトを新しい判定の順番にする
- [x] 2.1 npm の部品の公開日時を読み、警告の API を読めるかを確かめる

  Claude は、部品「check-dependency-cooldown.sh」とそのテスト `test-check-dependency-cooldown.sh` の今の版を、置き場所の `place-1/.github/scripts/` と、テストを置く `place-1/.github/scripts/tests/` に写して変える。このスクリプトは、依存グラフの比較の API の `npm` の部品も読み、npm の registry の部品の文書から公開日時を読む。このスクリプトは、前の版を、同じ名前の `removed` の部品のうち最も高い版として取り出す。このスクリプトは、警告の API を読めるかを1回確かめ、結果の1行を報告に書く。Claude は、テストを、`KP_TEST_CASE` で場合を選んで流せる形にする。
  - 完了の確かめ方: Linux のコンテナで流した `test-check-dependency-cooldown.sh` の、今ある場合と新しい場合が、すべて通る。`KP_TEST_CASE` に場合の名前を入れると、その場合だけが流れる。このタスクで作るか変えたスクリプトとテストに流した shellcheck の指摘が0件である
  - 受入基準とテストの対応: 要件1の受入基準1のうち、frontend の部品の公開日時を読むことは、テストの「npm の部品の公開日時を registry の time から読む」「スコープ付きの名前の / を %2f にして読む」で確かめる。あわせて、「npm の部品の公開日時を読めなければ赤になる」「すべての版が72時間経っていれば、警告の API を読めなくても緑になり、::warning:: の行と報告の1行が出る」「前の版は同じ名前の removed の部品のうち最も高い版になる」のテストを作る
  - _要件: 1.1_

- [x] 2.2 72時間待たずに入れてよいかを、確認のスクリプトを順に呼んで判定する

  Claude は、部品「check-dependency-cooldown.sh」を、design.md の処理の流れの図の順に、警告に照らす確認と、悪意のある部品の確認と、署名した者の確認と、除外の欄の確認と、記録と、所有者の承認の確認を行う形に変える。このスクリプトは、判定に使う確認のスクリプトを作るタスク 1.1 から 1.6 で作った6つのスクリプトを呼び、結果を組み合わせて緑か赤かを決める。
  - 完了の確かめ方: Linux のコンテナで流した `test-check-dependency-cooldown.sh` の場合が、すべて通る。結合テストは、判定に使う確認のスクリプトを作るタスク 1.1 から 1.6 で作った6つのスクリプトの本物を使い、外部のサービスだけをスタブにしてある。このタスクで作るか変えたスクリプトとテストに流した shellcheck の指摘が0件である
  - 受入基準とテストの対応: 要件1の受入基準1(本番で動く部品の high か critical の警告の最初の修正版は入る)と受入基準2(所有者が承認するまでマージされない)と要件5の受入基準2(記録が残るときだけ入る)は、テストの「確認がすべて通れば記録のコメントが書かれ、承認が無ければ赤、承認があれば緑になる」で確かめる。要件1の受入基準2のうち、承認を待つあいだにすべての版が72時間経ったときは「記録のコメントがあり公開から72時間経っていない版が無い head では、承認が無ければ赤になる」で確かめる。要件1の受入基準7(誰が作ったかによらない)は「Dependabot が作った PR でも同じ判定になる」で確かめる。要件1の受入基準8のうち除外の欄の確認は「frontend の版に除外の欄の要素が無ければ赤になる」で確かめる。要件2の受入基準2(ほかの部品の版が72時間経つまで入らない)は「72時間待たずに入れる版と一緒に、ほかの公開から72時間経っていない版があれば赤になる」で確かめる。要件3の受入基準1(変更で入るすべての部品を一覧に照らす)は「一緒に入る72時間経った部品が悪意のある部品なら赤になる」で確かめる。要件3の受入基準2(一覧に照らせなければ入らない)は「OSV に照らせなければ赤になる」で確かめる。要件4の受入基準1(署名した者が前の版と同じときだけ入る)と受入基準5(署名を調べられなければ入らない)は「署名した者が違えば赤になる」「署名を調べられなければ赤になる」で確かめる。要件5の受入基準2(記録が残るときだけ入る)は「記録のコメントを書けなかったら赤になる」で確かめる。要件5の受入基準5(すでに72時間経った最初の修正版は記録に載らない)は「すべての版が72時間経っていて記録のコメントが無ければ緑になり、警告の API を1回だけ読み、OSV と署名には問い合わせず、記録を書かない」で確かめる。要件4の受入基準1のうち、比べる前の版が無いときは「同じ名前の removed の部品が無い版は赤になる」で確かめる。要件1の受入基準8のうち除外の欄を読めないときは「除外の欄を読めなければ、frontend の公開から72時間経っていない版がすべて止まる」で確かめる。あわせて、「前の版に署名が無ければ止めない」「記録のコメントの有無を読めなければ赤になる」「最初の修正版でない版があれば OSV と署名に問い合わせない」のテストを作る
  - _要件: 1.1, 1.2, 1.3, 1.7, 1.8, 2.2, 3.1, 3.2, 4.1, 4.5, 5.2, 5.5_
  - _依存: 1.1, 1.2, 1.3, 1.4, 1.5, 1.6_

- [x] 2.3 止めた理由と入るようになる時刻を報告に出す

  Claude は、部品「check-dependency-cooldown.sh」に、design.md のデータの形の節の「検査の報告」の表と、止めた部品ごとの `::error::` の行を出す部分を足す。このスクリプトは、報告の止めた理由を、design.md の「検査の報告」の節にある止めた理由の文で書く。悪意のある部品のときは、このスクリプトは、時刻の代わりに公表の記載を書く。除外の欄の要素が無いときは、このスクリプトは、足すべき1行を書く。所有者の承認を待つときは、このスクリプトは、承認待ちの表を書く。
  - 完了の確かめ方: Linux のコンテナで流した `test-check-dependency-cooldown.sh` の場合が、すべて通る。報告の表の列が、部品、版、公開日時、止めた理由、入るようになる時刻の順である。このタスクで作るか変えたスクリプトとテストに流した shellcheck の指摘が0件である
  - 受入基準とテストの対応: 要件7の受入基準1と受入基準2(止めた部品の名前と版と理由と、入るようになる時刻が出る)は、テストの「止めた報告に、部品と版と理由と、公開日時に72時間を足した時刻が出る」「外部のサービスに問い合わせられなかったときは、その理由と時刻が出る」で確かめる。要件7の受入基準3(悪意のある部品の名前と版と公表の記載が出る)は「悪意のある部品のときは、時刻の欄が入らないになり、公表の記載の ID と要約と URL が出る」で確かめる。要件7の受入基準4(止めたすべての部品が出る)と要件2の受入基準2(ほかの部品の版が72時間経つまで入らない)は「72時間待たずに入れる版と一緒に、ほかの公開から72時間経っていない版があれば、両方の版が報告に出て、条件を満たす版は waiting-others の文になる」で確かめる。要件1の受入基準8のうち足すべき1行は「除外の欄の要素が無ければ、足すべき1行が報告に出る」で確かめる。要件7の受入基準1のうち、前の版が無いときと除外の欄を読めないときの理由は「前の版が無ければ、前の版が見つからないという理由が出る」「除外の欄を読めなければ、除外の欄を読めなかったという理由が出る」で確かめる。要件1の受入基準2のうち、所有者が PR で版と警告を読めることは「承認を待つときは、承認待ちの表に版と警告が出る」で確かめる
  - _要件: 1.2, 1.8, 2.2, 7.1, 7.2, 7.3, 7.4_

- [x] 3. PR の検査のワークフローにつなぐ
- [x] 3.1 dependency-cooldown のジョブを、Dependabot の PR でも動かし、所有者の承認を読むようにする

  Claude は、部品「dependency-review.yaml の cooldown ジョブ」の変更後のワークフローと、部品「actionlint.yaml」を、置き場所の `place-1/.github/` に作る。このジョブは、Dependabot の除外を外した条件で動き、design.md の cooldown ジョブの節に書いた、`vulnerability-alerts: read` を含む3つの権限を持ち、同じ節に書いた7本のテストを流し、所有者が今の head を承認したかを読んで `check-dependency-cooldown.sh` に渡す。
  - 完了の確かめ方: リポジトリの写しに置き場所のファイルを重ねて流した actionlint(`rhysd/actionlint:1.7.12`)の指摘が0件である。`.github/actionlint.yaml` を外して流すと、`unknown permission scope "vulnerability-alerts"` の指摘だけが出る。ジョブの条件に `dependabot[bot]` が無く、`timeout-minutes: 30` がある
  - 受入基準とテストの対応: 要件1の受入基準2(所有者が承認するまでマージされない)のうち、ジョブが所有者の承認を読むことと、要件1の受入基準7(誰が作ったかによらない)のうち、Dependabot の PR でもジョブが動くことは、ワークフローなので自動のテストで確かめられない。Claude は、この2つを、3つのやり方で確かめる。1つ目に、Claude は actionlint を流す。2つ目に、Claude は、ジョブが承認を読む jq の式を、`dependency-gate.yaml` の「Check owner approval」の式と1字ずつ比べる。3つ目に、Claude は、実装の PR の検査の結果で実際の環境を確かめるタスク 8.2 で、実装の PR の実行を確かめる。要件5の受入基準2(記録が残るときだけ入る)と要件7の受入基準1(止めた部品の名前と版と理由が出る)は、Claude が、ジョブが `check-dependency-cooldown.sh` の終了コードを無視していないことを、ワークフローを読んで確かめる。要件1の受入基準1のうち、警告を読む権限は、actionlint と、実装の PR の検査の結果で実際の環境を確かめるタスク 8.2 で確かめる
  - _要件: 1.1, 1.2, 1.7, 5.2, 7.1_
  - _依存: 2.3_

- [x] 3.2 backend の依存グラフに scope を付ける

  Claude は、部品「dependency-graph.yaml と dependency-review.yaml の generate ジョブ」の変更後のワークフローを、置き場所の `place-1/.github/workflows/` に作る。2つのワークフローは、依存グラフを作るステップに、環境変数 `DEPENDENCY_GRAPH_RUNTIME_INCLUDE_CONFIGURATIONS: productionRuntimeClasspath` を持つ。このタスクは、dependency-cooldown のジョブを変えるタスク 3.1 と同じ `dependency-review.yaml` を変えるので、3.1 のあとに行う。
  - 完了の確かめ方: 2つのワークフローの `gradle/actions/dependency-submission` のステップに同じ環境変数があり、actionlint の指摘が0件である
  - 受入基準とテストの対応: 要件1の受入基準5(開発のときだけ使う部品は入らない)と受入基準6(本番で動くかが載っていなければ入らない)のうち、backend の部品に scope が付くことは、ワークフローを自動のテストで確かめられないので、実装の PR の検査の結果で実際の環境を確かめるタスク 8.2 で、実装の PR の依存グラフの比較で確かめる
  - _要件: 1.5, 1.6_
  - _依存: 3.1_

- [x] 3.3 所有者の承認のあとの再実行と、必須チェックの期待一覧に dependency-cooldown を足す (並行可)

  Claude は、部品「rerun-approval-gated-checks.yaml」と部品「required-checks.json」の変更後のファイルを、置き場所の `place-1/.github/` に作る。再実行のワークフローは、対象の名前の一覧と冒頭のコメントに `dependency-cooldown` を持つ。期待一覧の `dependency-cooldown` の要素は、`approval_gated: true` を持つ。
  - 完了の確かめ方: 再実行の対象の一覧が `["escape-hatch","dependency-gate","pre-merge-check","dependency-cooldown"]` になっている。`perl -MJSON::PP` で読んだ期待一覧の `dependency-cooldown` の要素が、`mode: conditional`、`state: active`、`approval_gated: true` である。actionlint の指摘が0件である
  - 受入基準とテストの対応: 要件1の受入基準2のうち、所有者が承認すると dependency-cooldown が再実行されることは、ワークフローを自動のテストで確かめられないので、actionlint と完了の確かめ方の照合で確かめる
  - _要件: 1.2_
  - _対象の部品: rerun-approval-gated-checks.yaml, required-checks.json_

- [ ] 4. 週次監査に、72時間待たずに入れた版の一覧と、止まった Dependabot の PR の見分けを足す
- [ ] 4.1 72時間待たずに入れた版の一覧を報告するスクリプトを作る (並行可)

  Claude は、部品「check-audit-cooldown-exceptions.sh」と、そのテスト `test-check-audit-cooldown-exceptions.sh` を、置き場所の `place-1/.github/scripts/` と、テストを置く `place-1/.github/scripts/tests/` に作る。このスクリプトは、前の回の週次監査からの窓の中でマージされた PR を読み、マージした head の記録のコメントと、PR の本文の CI の道具の記録を、一覧にして報告する。窓とは、このスクリプトが調べる期間で、前の回の週次監査の実行の始まりから今の時刻までである。
  - 完了の確かめ方: Linux のコンテナで流した `test-check-audit-cooldown-exceptions.sh` の場合が、すべて通る。このタスクで作るか変えたスクリプトとテストに流した shellcheck の指摘が0件である
  - 受入基準とテストの対応: 要件5の受入基準6(窓の中の版を、記録に載っていることをすべて載せて報告する)は、テストの「窓の中でマージされた PR の、マージした head の記録と CI の道具の記録が、すべての欄とともに一覧に出て、終了コード 1 になる」「CI の道具の記録は PR がマージされた日時で窓に入る」で確かめる。要件5の受入基準7(版が無い回は Issue を作らない)は「窓の外でマージされた PR と、マージした head ではない head の記録は載らない」「載せる版が無ければ何も書かずに終了コード 0 になる」で確かめる。要件5の受入基準8(記録を読めなければ Issue に書く)は「記録の JSON が壊れていれば終了コード 2 になり、PR の番号が報告に出る」「検索の total_count が1000を超えたら終了コード 2 になる」で確かめる。あわせて、「github-actions[bot] 以外が書いた記録のコメントは数えない」「前の回の実行が無ければ7日前を窓の始まりにする」のテストを作る
  - _要件: 5.6, 5.7, 5.8_
  - _対象の部品: check-audit-cooldown-exceptions.sh_
  - _依存: 1.6_

- [ ] 4.2 止まっている Dependabot の PR の見分けに、記録のコメントを使う (並行可)

  Claude は、部品「check-audit-dependabot-stuck.sh」とそのテスト `test-check-audit-dependabot-stuck.sh` の今の版を、置き場所の `place-1/.github/scripts/` と、テストを置く `place-1/.github/scripts/tests/` に写して変える。このスクリプトは、`dependency-cooldown` の赤だけを、`record-cooldown-exception.sh exists` の結果で、承認待ちと滞留に分ける。Claude は、テストを、`KP_TEST_CASE` で場合を選んで流せる形にする。
  - 完了の確かめ方: Linux のコンテナで流した `test-check-audit-dependabot-stuck.sh` の、今ある場合と新しい場合が、すべて通る。このテストは、`gh` だけをスタブにし、`record-cooldown-exception.sh` の本物を呼ぶ。このタスクで作るか変えたスクリプトとテストに流した shellcheck の指摘が0件である
  - 受入基準とテストの対応: 要件1の受入基準2のうち、承認を待つ PR を滞留に数えないことは、テストの「dependency-cooldown が赤で記録のコメントがあれば、承認待ちの一覧に出て終了コード 0 になる」で確かめる。要件1の受入基準7のうち、72時間の待ちで止まった Dependabot の PR を見つけることは「dependency-cooldown が赤で記録のコメントが無ければ、滞留の一覧に出て終了コード 1 になる」で確かめる。あわせて、「記録のコメントを読めなければ終了コード 2 になる」「escape-hatch など、ほかの approval_gated の検査の赤は、記録のコメントによらず承認待ちに数える」のテストを作る
  - _要件: 1.2, 1.7_
  - _対象の部品: check-audit-dependabot-stuck.sh_
  - _依存: 1.6_

- [ ] 4.3 週次監査のワークフローに新しい項目をつなぐ

  Claude は、`audit-weekly.yaml` の変更後のワークフローを、置き場所の `place-1/.github/workflows/` に作る。このワークフローは、自己テストの一覧に `test-check-audit-cooldown-exceptions` を持ち、ほかの項目のあとに `run_check cooldown-exceptions "72時間待たずに入れた版の一覧" .github/scripts/check-audit-cooldown-exceptions.sh` を持ち、冒頭の項目の説明に1行を持つ。
  - 完了の確かめ方: actionlint の指摘が0件である。ワークフローの権限が、今の `pull-requests: read` と `issues: write` のままである
  - 受入基準とテストの対応: 要件5の受入基準6(窓の中の版を、記録に載っていることをすべて載せて報告する)と受入基準8(記録を読めなければ Issue に書く)のうち、終了コード 1 と 2 が Issue「週次監査: 逸脱あり」と「週次監査: 判定不能」になることには、今ある `run_check` と `audit-issue.sh` の受け渡しを使う。そのため、Claude は、ワークフローが項目のスクリプトの終了コードを無視していないことを、ワークフローを読んで確かめる
  - _要件: 5.6, 5.7, 5.8_
  - _依存: 4.1_

- [ ] 5. CI の道具の版を72時間待たずに変える手順を作る
- [ ] 5.1 信頼する署名した者のファイルと、gpg を動かすコンテナを作る (並行可)

  Claude は、部品「trusted-signers.json」と、`gpg` を動かす1回きりのコンテナの `Dockerfile` を、`.claude/scripts/ci-tool-signature/` に作る。`trusted-signers.json` は、design.md のデータの形の節の形で、4つの道具の信頼する署名した者と、版を書く場所を持つ。`Dockerfile` は、Debian の slim のイメージを digest で固定し、`gnupg` を入れる。digest とは、イメージの中身から計算した値で、中身が変わると値も変わる。
  - 完了の確かめ方: `perl -MJSON::PP` で読める。Node.js の `fingerprints` が、`nodejs/release-keys` の README にある今の担当者の主鍵の指紋8つと一致する。Terraform の指紋が `C874011F0AB405110D02105534365D9472D7468F` である。`locations` に書いたファイルが、どれもリポジトリにあり、その道具の版を書いている。`docker build` でイメージが作れ、そのイメージで `gpg --version` が動く
  - 受入基準とテストの対応: 要件6の受入基準3(配布元の署名で確かめる)のうち、信頼する署名した者は、完了の確かめ方の照合で確かめる。Claude は、指紋を写した README の URL と読んだ日付を、実装のメモに書く
  - _要件: 6.3_
  - _対象の部品: trusted-signers.json_

- [ ] 5.2 Node.js と Terraform の版を gpg の署名で確かめるスクリプトを作る

  Claude は、部品「verify-ci-tool.sh」のうち、引数と記録の出力と、Node.js と Terraform の確かめ方と、そのテスト `test-verify-ci-tool.sh` を、`.claude/scripts/ci-tool-signature/` に作る。このスクリプトは、JSON を `perl -MJSON::PP` で読み、`gpg` を、gpg を動かすコンテナを作るタスク 5.1 で作ったコンテナで動かし、取得したファイルを毎回新しく作る空の作業フォルダに置く。
  - 完了の確かめ方: Git Bash で流した `test-verify-ci-tool.sh` の Node.js と Terraform の場合が、すべて通る。テストは `docker` と `curl` と `gh` をスタブにしている。テストの署名は、テストの中で作った鍵で作ってある。テストは、`TRUSTED_SIGNERS_FILE` でその鍵の指紋を渡している。このタスクで作るか変えたスクリプトとテストに流した shellcheck の指摘が0件である
  - 受入基準とテストの対応: 要件6の受入基準3(配布元の署名で確かめる)と受入基準5(署名を確かめた結果を PR の本文に書く)は、テストの「Node.js の署名が合えば終了コード 0 になり、本文の文と記録の目印の行が出る」「Terraform の署名が合えば終了コード 0 になり、本文の文と記録の目印の行が出る」で確かめる。要件6の受入基準4(確かめられなければ版を変えない)は「署名が合わなければ終了コード 1 になる」「署名が無ければ終了コード 1 になる」「署名した者が信頼する者と違えば終了コード 1 になる」「取得できなければ終了コード 2 になり、理由が出る」「Node.js の詰め直しの tarball の bin/node が違えば終了コード 1 になる」で確かめる。要件5の受入基準3(CI の道具の記録に、道具と版と公開日時と所有者の指示と署名の結果と PR が載る)は「記録の目印の行の owner_instruction に3つ目の引数が入る」「3つ目の引数が無いか空なら終了コード 2 になる」「公開から72時間経っていれば記録の目印の行を出さない」で確かめる
  - _要件: 5.3, 6.3, 6.4, 6.5_

- [ ] 5.3 Trivy と Codex CLI の版を確かめる部分を足す

  Claude は、部品「verify-ci-tool.sh」に、Trivy を `cosign verify-blob` で確かめる部分と、Codex CLI を `gh attestation verify` で確かめる部分を足し、テストに2つの道具の場合を足す。このスクリプトは、`cosign` を、digest で固定した `ghcr.io/sigstore/cosign/cosign` のイメージで動かす。Claude は、その digest をスクリプトの定数に書く。
  - 完了の確かめ方: Git Bash で流した `test-verify-ci-tool.sh` の4つの道具の場合が、すべて通る。Claude は、4つの道具の、今 CI が使っている版で、`verify-ci-tool.sh` をスタブ無しで1回ずつ動かし、どれも署名を確かめられたという結果で終わることを確かめ、結果を実装のメモに書いてある。このタスクで作るか変えたスクリプトとテストに流した shellcheck の指摘が0件である
  - 受入基準とテストの対応: 要件6の受入基準3(配布元の署名で確かめる)と受入基準5(署名を確かめた結果を PR の本文に書く)は、テストの「Trivy の署名が合えば終了コード 0 になり、本文の文と記録の目印の行が出る」「Codex CLI の2つの tgz の来歴が合えば終了コード 0 になり、本文の文と記録の目印の行が出る」で確かめる。要件6の受入基準4(確かめられなければ版を変えない)は「cosign の検証が失敗したら終了コード 1 になる」「Codex CLI の2つの tgz のどちらかの来歴が合わなければ終了コード 1 になる」「Trivy の .sigstore.json を取得できなければ終了コード 2 になる」で確かめる。あわせて、「cosign に渡す身元が identity_template の {version} に版を入れたものになる」のテストを作る
  - _要件: 5.3, 6.3, 6.4, 6.5_

- [ ] 5.4 CI の道具の版を変える Claude の手順と、CLAUDE.md の1行を書く

  Claude は、部品「ci-tool-fast-update のスキル」の `.claude/skills/ci-tool-fast-update/SKILL.md` を書き、部品「CLAUDE.md の「自律動作の境界」の1行」を `CLAUDE.md` に足す。スキルの description は、4つの道具の名前と「72時間」「脆弱性」を含む。Claude は、スキルの手順を、design.md の ci-tool-fast-update のスキルの節に書いた5つの手順のとおりにする。
  - 完了の確かめ方: `bash .github/scripts/check-claude-md-size.sh` が通る。スキルの手順が、所有者の指示を確かめる手順、`verify-ci-tool.sh` を動かす手順、確かめられなければ版を変えずに理由を返事に書く手順、`locations` のすべての場所を変える手順、`/ship` で本文に結果の文と記録の目印の行を書く手順を、この順に持つ
  - 受入基準とテストの対応: 要件6の受入基準1と受入基準2(所有者が指示したときだけ版を変える)、要件6の受入基準4のうち返事に理由を書くこと、要件6の受入基準5(署名を確かめた結果を PR の本文に書く)、要件5の受入基準3のうち PR に記録を残すことは、手順の文書なので、完了の確かめ方の照合で確かめる
  - _要件: 5.3, 6.1, 6.2, 6.4, 6.5_

- [ ] 6. /ship が dependency-cooldown の赤を見分けるようにする (並行可)

  Claude は、部品「ship のスキル」の `.claude/skills/ship/SKILL.md` のうち、`approval_gated: true` の検査の赤を所有者の承認待ちに数える手順7の4の5を変える。`/ship` は、`dependency-cooldown` の赤を、`gh api --paginate .../comments --jq` で記録のコメントがあるときだけ承認待ちに数え、無いときは `::error::` の行から止めた部品と版と時刻を読んで報告し、見届けを終える。Claude は、報告の「見届けを終えた理由」の選択肢に「72時間の待ち」を足し、所有者の依頼で再実行する手順と、記録のコメントを読めなかったときの扱いを足す。
  - 完了の確かめ方: 手順7の4の5の承認待ちのゲートの検査の一覧に `dependency-cooldown` がある。記録のコメントを見分けるコマンドの `--jq` の式を、Claude が、テストの PR のコメントの一覧の形の JSON に `gh` の外の jq で当てて、github-actions[bot] の記録のコメントだけを1行出すことを確かめてある
  - 受入基準とテストの対応: 要件1の受入基準2のうち、`/ship` が承認待ちを所有者に示すことと、要件7の受入基準1のうち、`/ship` が止めた部品と版を報告に書くことは、手順の文書なので、完了の確かめ方の照合で確かめる
  - _要件: 1.2, 7.1_
  - _対象の部品: ship のスキル_
  - _依存: 1.6_

- [ ] 7. 文書を新しい判定に合わせる
- [ ] 7.1 ワークフローの一覧と設計の文書を書き直す (並行可)

  Claude は、`README.md` のワークフローの一覧の表の `dependency-review.yaml` と `audit-weekly.yaml` の行と、Mermaid の図の週次監査の節を更新する。Claude は、この spec で変えるほかの2つのワークフロー `dependency-graph.yaml` と `rerun-approval-gated-checks.yaml` の README の行と図も読み、変える要る記述があれば更新する。Claude は、`doc/インフラ設計/Github Actions設計/ワークフロー設計.md` の「自動チェックの一覧」の表の `dependency-cooldown` の行と、frontend の `minimumReleaseAge` の行と、注3を、新しい判定に合わせて書き直す。
  - 完了の確かめ方: README の Mermaid の図が、GitHub の表示と同じ Mermaid の版で描ける。ワークフロー設計.md の注3に、Dependabot の PR を `dependency-cooldown` の対象から外すという記述が残っていない。`dependency-graph.yaml` と `rerun-approval-gated-checks.yaml` の README の行を変えなかったときは、変えなかった理由を実装のメモに書いてある
  - 受入基準とテストの対応: 文書の更新なので、受入基準をテストで確かめない
  - _要件: 1.7_
  - _対象の部品: README.md, ワークフロー設計.md_

- [ ] 7.2 監査手順と steering と除外の欄のコメントを書き直す (並行可)

  Claude は、`doc/開発フロー/監査手順.md` に、週次監査の `cooldown-exceptions` の項目の読み方と、Dependabot の PR が `dependency-cooldown` で止まったときの扱いを足す。Claude は、`.kiro/steering/tech.md` の「バージョンカタログを承認境界にする」に、72時間待たずに入れる例外を足す。Claude は、`frontend/pnpm-workspace.yaml` の `minimumReleaseAgeExclude` のコメントを、72時間待たずに入れる版の要素を書く使い方に書き直し、設定の値は変えない。
  - 完了の確かめ方: `git diff frontend/pnpm-workspace.yaml` がコメントの行だけを変えている。`/verify-frontend` が成功する
  - 受入基準とテストの対応: 文書とコメントの更新なので、受入基準をテストで確かめない
  - _要件: 1.8, 5.6_
  - _対象の部品: 監査手順.md, tech.md, pnpm-workspace.yaml_

- [ ] 8. 所有者が置いたファイルで全体を確かめる
- [ ] 8.1 所有者にファイルを置いてもらい、置いた場所でテストを流す

  親のセッションは、置き場所の `place-1/` のファイルを本来の場所に写すコマンドを所有者に示し、そのコマンドでファイルを置くよう所有者に頼む。依頼には、Claude が `.github/` に書き込めないこと(`settings.json` の `deny`)を添える。所有者が置いたら、親のセッションは、本来の場所で、この spec で作るか変えたシェルのテストのすべてと、shellcheck と、actionlint を流す。親のセッションは、`test-verify-ci-tool.sh` を、Git Bash に加えて Linux のコンテナでも1回流す。
  - 完了の確かめ方: Linux のコンテナで流した `.github/scripts/tests/` の、この spec で作るか変えたテストと `test-lib-notice-comment.sh` が、すべて通る。`test-verify-ci-tool.sh` が Git Bash と Linux のコンテナの両方で通る。shellcheck と actionlint の指摘が0件である。親のセッションは、shellcheck を `koalaman/shellcheck:v0.11.0` のイメージで動かし、`git ls-files -z --cached --others --exclude-standard '*.sh'` が返すファイルに流す。親のセッションは、actionlint を `rhysd/actionlint:1.7.12` のイメージで動かす。結果を実装のメモに記録してある
  - 受入基準とテストの対応: 各タスクの受入基準とテストの対応のとおり
  - _要件: 1.1, 1.2, 3.1, 4.1, 5.1, 5.6, 6.3, 7.1_

- [ ] 8.2 実装の PR の検査の結果で、dependency-cooldown と、依存グラフの scope と、guardrails の3つを確かめる

  Claude は、`/ship` が実装の PR を作ったあとに、PR の検査の結果で、design のテストの方針の節の「Claude が実際の環境で確認すること」の3つを確かめる。このタスクは PR が要るので、Claude は、所有者が置いたファイルでテストを流すタスク 8.1 までを終えたら `/ship` に進み、`/ship` の見届けの中でこのタスクを終える。この PR は `.github/` を変えるので、所有者が承認するまでマージされない。そのため、Claude は、マージの前にこの確認を終えられる。
  - 完了の確かめ方: 実装の PR の `dependency-cooldown` が緑で、報告に「脆弱性の警告を読めた」の行がある。実装の PR の依存グラフの比較で、`org.springframework:spring-core` が `runtime`、`com.diffplug.spotless:spotless-lib` が `development` になっている。実装の PR の `guardrails` が緑である。結果を実装のメモに記録してある。どれかが違えば、Claude は、設計を見直すきっかけに当たるかを所有者に報告して止まる。依存グラフの比較に2つの部品が出ないときは、Claude は、scope を確かめられなかったと実装のメモと PR の本文に書き、合格とは書かない。そのときは、design.md の移行の節に書いた、マージのあとの警告の scope の確認が、scope を確かめる唯一の確認になる
  - 受入基準とテストの対応: 要件1の受入基準5と受入基準6のうち backend の scope と、要件1の受入基準1のうち警告を読む権限は、この確認で確かめる
  - _要件: 1.1, 1.5, 1.6_

## 実装のメモ

- 置き場所: 置き場所は、作業フォルダの中の `.claude/.state/security-fix-cooldown-exception/` である。このフォルダは `.gitignore` の `.claude/.state/` に当たるのでコミットされず、`settings.json` の `deny` にも当たらない。会話を開き直しても、作業フォルダが残る限り消えない。scratchpad は会話ごとに別のフォルダなので、所有者がファイルを置くのを待つあいだに会話を開き直すと、置く前のファイルが失われる。そのため、Claude は、`.github/` の下の完成品を scratchpad に置かない
- `.github/` の下は、Claude が書けない(`settings.json` の `deny`)。Claude は、`.github/` の下のファイルを、置き場所の `place-1/` に、リポジトリと同じ並びで作る。今あるファイルを変えるときは、Claude は、今の版を Read で読み、Write で `place-1/` に写してから変える。所有者が置くまで、Claude は `.github/` の下に書こうとしない
- `.claude/skills/` と `.claude/scripts/` と `CLAUDE.md` と文書と `frontend/pnpm-workspace.yaml` は、Claude が本来の場所に書く
- `.github/scripts/` のテストは `jq` を使うので、Claude は、Git Bash ではなく、`jq` `curl` `openssl` `gnupg` `perl` を入れた Linux のコンテナ(`ubuntu:24.04`)で流す。`perl` を入れるのは、`ubuntu:24.04` の `perl-base` に `JSON::PP` が無く、所有者が置いたファイルでテストを流すタスク 8.1 で流す `test-verify-ci-tool.sh` が `JSON::PP` を使うためである。Claude は、リポジトリの写しを scratchpad の一時フォルダに作り、`place-1/` のファイルを重ねてから、その写しをコンテナに読むだけの形で渡す。Claude は、作業フォルダに無いファイルを `docker run -v` で作業フォルダに重ねない。Docker が作業フォルダに0バイトのファイルを作るためである
- テストのスタブが返す OSV と npm の来歴と Dependabot の警告の JSON と、maven の部品の `.pom.asc` と公開鍵は、Claude が実際のサービスから1回取った答えの形をもとにする。テストはネットワークを使わない
- `place-1/.github/` には、Claude は書けない。`settings.json` の `deny` の `.github/**` が、置き場所の中の `place-1/.github/` にも当たるためである。そのため、Claude は、`.github/` の下に置くファイルを、`place-1/dot-github/` に、`.github/` と同じ並びで作る。タスクの本文の `place-1/.github/` は、`place-1/dot-github/` と読む。所有者に置いてもらうときのコマンドは、`place-1/dot-github/` の中身を `.github/` に写す形にする
- `cooldown-check-malware.sh` は、`MAL-` の ID の項目も `vulns/{id}` で読む。止めた理由の報告に、公表の記載の要約と URL を出すためである。design の失敗したときの扱いは「`vulns/{id}` が失敗したら、その ID を持つ部品を unknown にする」である。ただし、`cooldown-check-malware.sh` は、`MAL-` の項目だけは、`vulns/{id}` を読めなくても malicious のままにする。`MAL-` の ID の部品は、querybatch の答えだけで悪意のある部品と分かる。また、malicious の部品も unknown の部品も、72時間待たずには入らない。そのため、`MAL-` の項目を読めなくても malicious のままにしても、要件3の受入基準1(変更で入るすべての部品を一覧に照らす)と受入基準2(一覧に照らせなければ入らない)の結果は変わらない。`MAL-` の項目を読めなかったときは、`cooldown-check-malware.sh` は、要約を空にし、URL を osv.dev の項目のページにする
- `cooldown-check-signer.sh` は、npm の来歴の証明書を、`verificationMaterial.certificate.rawBytes` に加えて `verificationMaterial.x509CertificateChain.certificates[0].rawBytes` からも読む。2026-11-02 に registry.npmjs.org から取った `sigstore@3.0.0` と `3.1.0` の来歴は bundle の版 0.2 で、証明書は design の書いた欄ではなく後者にあったためである。`cooldown-check-signer.sh` は、証明書の拡張を、`openssl x509 -text` ではなく `openssl asn1parse` で読む。`x509 -text` は、名前の無い拡張の値を、UTF8String の頭の2バイトを含む形で出すためである。`cooldown-check-signer.sh` は、`gh attestation verify` の `--repo` に渡す、前の版の元のリポジトリを、前の版の証明書の拡張 1.3.6.1.4.1.57264.1.12(元のリポジトリの URI)から読む。3つの欄が違うときは、`cooldown-check-signer.sh` は、tgz の取得と来歴の検証を飛ばして、`different` を返す。検証できても、署名した者が違うことは変わらないためである。また、呼ぶ側のスクリプトは、`different` の版も `unknown` の版も止めるためである
- `cooldown-check-signer.sh` の maven の部分は、発行者の鍵 ID だけを持つ署名を、テストの中で作った使い捨ての鍵では確かめない。gpg 2.4.4 は、`--rfc4880` を付けても、署名にいつも発行者の指紋を入れるためである。そのため、鍵 ID で公開鍵を取る動きは、2026-11-02 に取った `org.postgresql:postgresql` 42.7.13 と 42.7.14 の本物の `.pom` と `.pom.asc` と公開鍵で確かめる。テストの curl の代わりは、`-L` を、`-sSL` のようにまとめた短い指定の中からも読む
- CI の shellcheck は、追跡されているすべての `.sh` を一度に渡す。そのため、`source` で読み込む `lib-notice-comment.sh` が入力に入り、指摘が出ない。Claude は、手元で shellcheck を流すときも、`# shellcheck source=.github/scripts/lib-notice-comment.sh` を書いたうえで、ライブラリを入力に含める。テストの期待の文字列にバッククォートが要るときは、単引用符ではなく二重引用符で書き、指摘を止める指定は使わない
- 所有者への依頼は、親のセッションが行う。実装役のサブエージェントは、所有者に依頼する手前で止まり、用意したもの(置き場所のパス)を親のセッションに返す。確認役は、置く前の成果を置き場所のパスで確かめる
- この spec が frontend で変えるのは `pnpm-workspace.yaml` のコメントだけなので、共通の完了条件の2(verify のスキル)のうち当てはまるのは、監査手順と steering と除外の欄のコメントを書き直すタスク 7.2 の `/verify-frontend` だけである。代わりに、Claude は、シェルのスクリプトを作るか変えるタスクごとに、そのタスクのスクリプトとテストに shellcheck を流す。判定に使う確認のスクリプトを作る大きなまとまり1のタスクは、並行に進む。そのため、Claude がまとまりの最後のタスクで shellcheck を流すと、まだ終わっていないタスクのスクリプトを見落とす
- Claude は、`audit-weekly.yaml` の自己テストの一覧に、design のとおり `test-check-audit-cooldown-exceptions` だけを足す。止まっている Dependabot の PR の見分けを変えるタスク 4.2 のあとの `check-audit-dependabot-stuck.sh` は、`record-cooldown-exception.sh` を呼ぶ。`test-check-audit-dependabot-stuck.sh` は、`gh` だけをスタブにして、`record-cooldown-exception.sh` の本物を呼ぶ。そのため、週次監査の自己テストでも記録のコメントの読み取りが流れる。`test-record-cooldown-exception.sh` そのものは、`dependency-cooldown` のジョブで流れる
- 共通の完了条件の1(確かめるテストの無い受入基準を残さない)には、2つの例外がある。1つ目は、ワークフローの起動と権限と承認の読み取りを変えるタスク 3.1、3.2、3.3、4.3 である。これらのタスクは、actionlint と、照合と、実装の PR の検査の結果で実際の環境を確かめるタスク 8.2 で確かめる。2つ目は、手順の文書を書くタスク 5.4 と 6 である。これらのタスクは、照合で確かめる
- マージのあとの確認: Claude は、出荷の PR の本文に、design の移行の節の2つの確認を書く。1つ目は、マージのあとの警告の `dependency.scope` が `runtime` か `development` になっていることである。2つ目は、次の Dependabot の PR の `dependency-cooldown` の報告に「脆弱性の警告を読めた」の行が出ることと、記録のコメントの一覧を読めたことである

## 完了条件(全タスク共通)

Claude は、どのタスクでも、タスクの箇条書きの欄を書いたうえで、次の4つを満たしたときにタスクを完了とする。

1. Claude は、タスクが満たす requirements.md の受入基準(要件の番号付きの項目)ごとに、それを確かめるテストのファイル名とテスト名を「受入基準とテストの対応」の行に書く。Claude は、確かめるテストの無い受入基準を残さない。
2. タスクで変えたファイルを使うテストが、すべて成功している。`1.` や `2.` の見出しのタスクを大きなまとまりと呼ぶ。大きなまとまりの最後のタスクでは、加えて、そのまとまりのタスクで変えた領域の verify のスキル(`/verify-frontend` `/verify-backend` `/verify-terraform`)が、すべて成功している。
3. Claude は、テストを飛ばす設定、アサーションの削除、カバレッジや lint の対象からの除外を足して、完了条件を満たしたように見せない。CI の escape-hatch の検査が、これらの追加を機械で見つける。
4. Claude は、新しく書いたテストについて、テストの対象のコードを一時的に壊してテストが失敗することを確かめる。Claude は、新しいテスト1件につき1か所だけを、作業フォルダの外の写しで壊し、そのテストだけを流す。壊した写しの作り方と流し方は、`.kiro/steering/tech.md` の「テストの完全性」に従う。
