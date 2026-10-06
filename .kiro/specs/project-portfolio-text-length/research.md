# 調査と設計の判断の記録

## まとめ
- **Feature**: `project-portfolio-text-length`
- **Discovery Scope**: Extension(既存の保存先の列の型を変える。調べ方は light)
- **分かったこと**:
  - 入力の検査(`Project.java` L287・L299、`Portfolio.java` L147)とドメインモデル(`doc/モデル図/ドメインモデル.pu` L215・L217・L233)は、3つの欄を1000文字までとしている。保存先の列(`V1__create_tables.sql` L117・L119・L262)だけが `VARCHAR(255)` で、ER図(`doc/DB設計/ER図.pu` L73・L75・L139)もこの列の形を写している。所有者は 2026-10-06 に、ドメインモデルの1000文字を正とする前提を了承した
  - 同じ1000文字の上限を持つ「成果」(`projects.achievement`)と「技術スタック」(`portfolios.tech_stack`)の列は、すでに `TEXT` である
  - 5つの保存のしかた(足す・直す・自動保存・コピー・復元)は、どれも `ResumeRepository.save` から `MyBatisResumeRepository` を通り、`ResumeMapper.insertProject` と `ResumeMapper.insertPortfolio` で書き込む。直す列は3つで足り、保存の経路のコードは変えなくてよい

## 調べたこと

### PostgreSQL で列の型を広げるときの動き
- **きっかけ**: 本番の表に入っているデータを書き換えずに、列の型だけを変えられるかを確かめる
- **見た資料**: PostgreSQL 17 の ALTER TABLE と文字型の公式文書(下の参考)
- **分かったこと**:
  - 列の型を変えると、ふつうは表と索引を書き直す。ただし、`USING` で中身を変えず、元の型が新しい型へ binary coercible(中身の並びを変えずにそのまま読み替えられること)なら、表を書き直さない。`text` と `varchar` は並び順が同じなので、照合順序を変えなければ索引も作り直さない
  - ALTER TABLE は、文書に別の定めが無い限り `ACCESS EXCLUSIVE` のロックを取る。表を書き直さないので、ロックを持つ時間は型の情報を書き換える間だけになる
  - `varchar(n)` の n は文字数で数え、バイト数ではない。`text` と `varchar` に性能の差は無く、`varchar(n)` は長さを確かめる分だけ処理が増える
  - `varchar(n)` に n を超える文字列を入れると、エラーになる(今回の不具合の原因)
- **設計への影響**: `VARCHAR(255)` から `TEXT` への変更は、表を書き直さずに終わる。既存の行の中身は変わらない

### 本番でアプリだけを前の版に戻したときの Flyway の動き
- **きっかけ**: マイグレーションを含むので、アプリを前の版に戻したときに起動できるかを確かめる
- **見た資料**: Flyway の `ignoreMigrationPatterns` の設定と `MigrationState` の公式の記述(下の参考)
- **分かったこと**:
  - Flyway は、既定で `future` のマイグレーションを無視する。`future` は、データベースに適用済みで、手元に無く、手元のどの版より新しいマイグレーションを指す
  - このリポジトリの `application.yaml` は `ignoreMigrationPatterns` を変えていない(L17〜L20 は `enabled` `baseline-on-migrate` `baseline-version` だけ)
- **設計への影響**: V6 を適用したあとでアプリを V6 の無い版に戻しても、Flyway の検証は V6 を `future` として無視し、アプリは起動する。前の版のアプリは `TEXT` の列にも文字列を読み書きできる

### 既存のテストの形
- **きっかけ**: 要件3の受入基準1(すでに保存してある文章を変えない)を確かめる方法を決める
- **分かったこと**:
  - `ResumeMapperTest` は `spring.flyway.target=5` で版を固定している。V5 を足したとき(コミット 3f4b6cc2)は、target を5に上げて NULL の保存のテストを足した
  - 版を途中で進めるテストの前例は無い。テストの依存には `org.testcontainers:postgresql` と `org.testcontainers:junit-jupiter` と `flyway-core` がすでにあり、`build.gradle` を変えずに Flyway の API で版を進めるテストを書ける
  - ArchUnit の検査(`BackendArchitectureTest`)は `ImportOption.DoNotIncludeTests` でテストのクラスを外しているので、テストの置き場所はこの検査の対象にならない
  - 1000文字を超えるとエラーにする入力の検査のテストは、`ProjectTest`(L266・L268)と `PortfolioTest`(L130)にすでにある

## 比べた案

| 案 | 中身 | よいところ | 弱いところ |
|---|---|---|---|
| A. `TEXT` にする | 3つの列を `TEXT` に変える | 同じ1000文字の上限を持つ「成果」「技術スタック」の列と形が揃う。上限の文字数を変えるときに、保存先を変えずに入力の検査だけを直せばよい。表を書き直さない | 保存先の側に長さの歯止めが無くなり、上限の決まりは入力の検査だけが持つ |
| B. `VARCHAR(1000)` にする | 3つの列を `VARCHAR(1000)` に変える | 保存先の側にも歯止めが残る。表を書き直さない | 上限の決まりが入力の検査と保存先の2か所に分かれ、上限を変えるたびにマイグレーションが要る。「成果」「技術スタック」と形が揃わない。入力の検査は Java の `String.length()`(UTF-16 の数)で数え、保存先は文字数で数えるので、2か所の数え方が違う |

## 設計の判断

### 判断: 3つの列を `TEXT` に変える
- **きっかけ**: 要件1(1000文字までの文章を保存できる)
- **比べた案**: 上の表の A と B
- **選んだ案**: A。V6 のマイグレーションで `projects.overview` `projects.role` `portfolios.overview` を `TEXT` に変える
- **理由**: このリポジトリは、上限の文字数をドメイン層の入力の検査で決め(`doc/モデル図/ドメインモデル.pu` L11)、同じ上限の「成果」「技術スタック」の列を `TEXT` にしている。A はこの形に揃い、上限の決まりを1か所に保てる
- **引き換え**: 保存先が長さを止めなくなる。入力の検査を通らずに保存先へ書き込む経路は無い(5つの保存のしかたは、どれもドメインのオブジェクトを作ってから `ResumeRepository.save` を呼ぶ)ので、この引き換えで今の動きは変わらない
- **あとで確かめること**: マイグレーションのテストで、V5 の時点で入れた行の文章が V6 のあとも同じであること

### 判断: マイグレーションを1段で行う
- **きっかけ**: backend の決まりの expand-contract(`backend/CLAUDE.md` の「DBスキーマ変更」)
- **選んだ案**: 型を広げる変更だけを V6 の1つで行い、contract の段階を作らない
- **理由**: 型を広げる変更は、古い版のアプリと新しい版のアプリのどちらでも動く。古い形を消す段階(contract)に当たる変更が無い

## 危うい点と備え
- 本番で V6 を適用したあとに保存先を `VARCHAR(255)` に戻すと、256文字以上の行があれば戻せない。備え: 保存先の型は戻さず、アプリだけを戻す。アプリを戻しても動くことは、上の Flyway の調べで確かめた
- `ACCESS EXCLUSIVE` のロックを取る間、`projects` と `portfolios` の読み書きが待たされる。備え: 表を書き直さないので、待たされる時間は型の情報を書き換える間だけになる

## 参考
- [PostgreSQL 17: ALTER TABLE](https://www.postgresql.org/docs/17/sql-altertable.html) — 型を変えるときに表を書き直さない条件と、取るロック
- [PostgreSQL 17: Character Types](https://www.postgresql.org/docs/17/datatype-character.html) — `varchar(n)` の数え方、`text` との性能の差、長すぎる文字列のエラー
- [Flyway: Ignore Migration Patterns Setting](https://github.com/flyway/flyway/blob/main/documentation/Reference/Configuration/Flyway%20Namespace/Flyway%20Ignore%20Migration%20Patterns%20Setting.md) — 既定で `future` のマイグレーションを無視すること
- [Flyway: MigrationState.java](https://github.com/flyway/flyway/blob/main/flyway-core/src/main/java/org/flywaydb/core/api/MigrationState.java) — `FUTURE_SUCCESS` の意味
