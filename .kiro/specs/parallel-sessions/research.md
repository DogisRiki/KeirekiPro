# 調査と設計の判断(parallel-sessions)

## まとめ

- **機能**: `parallel-sessions`
- **調査の範囲**: 既存の仕組みの拡張(Complex Integration)。開発環境(Docker Compose)、Claude Code のフック、スキル、Git の worktree にまたがる
- **主な発見**:
  - 今の品質チェックは、本体フォルダを読み込んだ常駐コンテナ(`spring` `react` `terraform`)の中でコマンドを動かす。worktree から `docker compose exec` を打つと、git の管理外の `docker/localstack/.env.local` が無いため、compose の読み込みで失敗する(2026-10-04 実測)。誤合格は、AIがこの失敗を避けて本体フォルダから実行したときに出る
  - `docker compose run` は、サービスの `container_name` を使わず `keirekipro-<サービス>-run-<ID>` の名前でコンテナを作り、プロジェクトのネットワーク(`keirekipro_my-network`)に入る(実測)。`-v` で同じ行き先のボリュームを渡すと、サービスに書かれたボリュームを置き換える(実測)。そのため、セッションの作業フォルダから `-p keirekipro` で `run` すれば、そのフォルダを読み込み、共有の `dind` にもつながる1回きりのコンテナを作れる
  - backend の `./gradlew check` は、1回で約8分かかり、1回きりのコンテナで動かすと、チェック本体とテスト用のデータベースで最大約4.2GBのメモリを使う(2026-10-04 実測)。2つ同時では Docker の割り当て(約7.6GB)を超えるので、所有者は同時に走らせる数の初期値を1にすると決めた(下の「メモリの測り直し」)

## 調べたこと

### worktree のセッションの品質チェックが何を検査するか

- **きっかけ**: Issue #481。worktree のセッションで品質チェックが合格と出たが、検査したのは本体フォルダだった
- **見たもの**: `compose.yaml`、`.claude/skills/verify-*/SKILL.md`、worktree `.claude/worktrees/spec-readable-writing` からの `docker compose ps` `docker compose exec`(実測)
- **分かったこと**:
  - compose のプロジェクト名は、`name:` も `.env` も無いため、compose.yaml のあるフォルダの名前になる。worktree ではフォルダ名(例 `spec-readable-writing`)になり、本体の `keirekipro` と別になる
  - `compose.yaml` の localstack は `env_file: ./docker/localstack/.env.local` を必須で読む。このファイルは `.gitignore` の `.env*` で git の管理外になり、worktree には無い。そのため、worktree からの compose の操作は、どのサービスに対するものでも読み込みで失敗する
  - 常駐コンテナは名前が固定(`container_name`)なので、`docker exec react ...` のように名前で直接叩くと、どこからでも本体フォルダを読み込んだコンテナに届く
  - Git Bash から `docker compose exec -w /home/node/app` を打つと、`/home/node/app` が Windows のパスに書き換えられて失敗する(`Cwd must be an absolute path`)。`MSYS_NO_PATHCONV=1` を付けると通る(実測)。`start-dev.sh` も同じ理由で `MSYS_NO_PATHCONV=1` を付けている
- **設計への影響**: 品質チェックは、そのセッションの作業フォルダを読み込んだコンテナで動かす必要がある。常駐コンテナへの `exec` をやめ、作業フォルダごとに1回きりのコンテナを `run` で作る

### `docker compose run` の振る舞い

- **きっかけ**: 1回きりのコンテナで、作業フォルダごとの読み込みと、共有の `dind` へのつながりを両立できるかを確かめる
- **見たもの**: [docker compose run](https://docs.docker.com/reference/cli/docker/compose/run/)、[Compose のサービスの定義](https://docs.docker.com/reference/compose-file/services/)、[変数の置き換え](https://docs.docker.com/reference/compose-file/interpolation/)、実測(Docker Compose v5.1.4)
- **分かったこと**:
  - `run` は、サービスの `ports` を公開しない。公開するのは `--service-ports` か `-p` を付けたときだけである
  - `--no-deps` を付けると、依存するサービスを起動しない
  - `run -d --no-deps terraform` で作ったコンテナの名前は `keirekipro-terraform-run-9eba36fba567` で、ネットワークは `keirekipro_my-network` だった(実測)。`container_name` は使われない
  - `run -v kp-probe-nm:/home/node/app/node_modules` を渡すと、サービスに書かれた `named-node_modules` の代わりに、渡したボリュームが同じ場所に入った(実測)
  - `env_file` は長い書き方で `required: false` を付けると、ファイルが無くても無視される(Compose 2.24.0 から。最初の調べでは 2.20.0 と書いたが、それは `depends_on` の `required` の版で、取り違えだった。公式の文書の `data/summary.yaml` の「Compose required」で確かめた)
  - 変数の置き換えは compose.yaml のすべての値に効く
- **設計への影響**: セッションの作業フォルダの最上位で `docker compose -p keirekipro run --rm --no-deps` を打つと、相対パスの読み込み(`./frontend` など)はその作業フォルダを指し、コンテナは本体のプロジェクトのネットワークに入る。localstack の `env_file` に `required: false` を付ければ、worktree でも compose の読み込みが通る

### Claude Code の worktree とフック

- **きっかけ**: セッションごとの記録(作業中かどうか、どのIssueを進めているか)を、何で付けるかを決める
- **見たもの**: [worktrees](https://code.claude.com/docs/en/worktrees.md)、[hooks](https://code.claude.com/docs/en/hooks.md)、[hooks-guide](https://code.claude.com/docs/en/hooks-guide.md)
- **分かったこと**:
  - デスクトップアプリで worktree を選ぶと、`.claude/worktrees/<名前>/` に作業フォルダができ、セッションの作業フォルダになる。worktree は git の管理下のファイルだけを持つ
  - `.worktreeinclude`(リポジトリの最上位に置く)に書いた、git の管理外のファイルは、Claude Code が作る worktree に写される。デスクトップアプリの並行セッションも対象になる
  - フックの `${CLAUDE_PROJECT_DIR}` は「セッションを始めたプロジェクトの最上位」のままで、セッションが worktree に入っても動かない。フックの入力の `cwd` は worktree を指す。デスクトップアプリで worktree を選んで始めたセッションで `CLAUDE_PROJECT_DIR` がどちらを指すかは、公式に書かれていない
  - SessionStart の入力には `session_id` `cwd` `source`(`startup` `resume` `clear` `compact` `fork`)がある。SessionEnd の入力には `session_id` `cwd` `reason` がある。アプリを閉じたときやプロセスが落ちたときに SessionEnd が届くかは、公式に書かれていない
  - セッションのIDを Bash のコマンドに渡す環境変数は、公式に書かれていない。`CLAUDE_ENV_FILE` は SessionStart などで使えるが、Windows で動くかは書かれていない
  - SessionStart のフックは、`additionalContext` でセッションに文を渡せる
  - worktree を消すと、その中の `.claude/.state/` も消える
- **設計への影響**:
  - フックは、作業フォルダを `CLAUDE_PROJECT_DIR` ではなく、入力の `cwd` の git の最上位(`git -C <cwd> rev-parse --show-toplevel`)で決める
  - セッションが作業中かどうかは、SessionStart と SessionEnd のフックで記録する。SessionEnd が届かずに残った記録は、要件どおり所有者に「やめたか」を尋ねて片付ける
  - セッションのIDは、SessionStart のフックが `additionalContext` でセッションに伝える。Bash のコマンドには、Claude がそのIDを引数で渡す

### 設定の置き場所と共有の記録の置き場所

- **きっかけ**: 同時に走らせる数の設定と、セッションをまたぐ記録(順番待ち、作業中のセッション、Issueと作業フォルダの対応)を、すべての作業フォルダから同じものとして読める場所に置く
- **見たもの**: `git rev-parse --git-common-dir`、`git config` の仕組み、`.git/config`(`extensions.worktreeconfig true`)
- **分かったこと**:
  - worktree は `.git` のディレクトリを本体と共有する。`git rev-parse --path-format=absolute --git-common-dir` は、どの作業フォルダから打っても本体の `.git` を返す
  - `git config --local` の値は、共有の `.git/config` に入り、すべての worktree から読める。git の管理下に入らないので、作業PCごとに違う値を持てる
- **設計への影響**: 同時に走らせる数は `git config keirekipro.parallelSlots` に置く(無ければ1。所有者が初期値を1と決めた。下の「メモリの測り直し」)。セッションをまたぐ記録は、本体の `.git` の下の `keirekipro-parallel/` に置く。どちらもコミットされず、どの作業フォルダからも同じものが見える

### 品質チェックにかかる時間とメモリ

- **きっかけ**: 要件3.5 は、待ちの上限の時間を、実際にかかる時間を測って決めるとしている。同時に走らせる数の初期値2で失敗しないかも確かめる
- **見たもの**: 本体フォルダで、今の手順のとおり常駐コンテナで1つずつ測った(2026-10-04、`MSYS_NO_PATHCONV=1` 付き)。メモリは `docker stats` で20秒ごとに見た
- **分かったこと**:

  | 領域 | コマンド | かかった時間 |
  |---|---|---|
  | frontend | `pnpm run format` | 13秒 |
  | frontend | `pnpm run lint` | 48秒 |
  | frontend | `pnpm run typecheck` | 9秒 |
  | frontend | `pnpm test` | 34秒 |
  | frontend | `pnpm run coverage` | 47秒 |
  | backend | `./gradlew spotlessCheck` | 13秒 |
  | backend | `./gradlew check` | 486秒 |
  | terraform | `terraform fmt -check -recursive` | 1秒 |
  | terraform | `terraform validate` | 16秒 |
  | terraform | `tflint --recursive` | 2秒 |
  | terraform | `checkov -d .` | 10秒 |

  - backend の `check` の間、`spring` コンテナのメモリは約3.0〜3.2GBだった。終わったあとも、Gradle のデーモンが約1.1GBを持ち続けた
  - Docker に割り当てられたメモリは約7.6GB(作業PCの約15.7GBの半分。`.wslconfig` は無い)
- **設計への影響**: 待ちの上限は、いちばん長い1回(backend の `check`、約8分)が前に2回並んでも足りる長さとして、30分にする。メモリは下の「メモリの測り直し」の結果で判断する

### メモリの測り直し(1回きりのコンテナでの backend の check)

- **きっかけ**: 常駐コンテナでの測定には、前から動いていた Gradle のデーモンの分が混ざる。設計どおりの1回きりのコンテナで、1回の `check` が使うメモリを測る
- **見たもの**: 本体フォルダで `docker compose run --rm --no-deps -T -v kp-probe-gradle-home:/root/.gradle -v kp-probe-gradle-proj:/home/spring/app/.gradle backend ./gradlew check` を動かし、`docker stats` で5秒ごとに見た
- **分かったこと**:
  - 1回きりのコンテナでの `check` は通った(`BUILD SUCCESSFUL in 10m 6s`。ライブラリの最初の取得を含む)。Testcontainers は、`run` のコンテナから共有の `dind` につながって動いた。設計の作り方で backend の品質チェックが動くことを確かめた
  - コンテナのメモリの最大は3.74GBだった。テストの間、`dind` は最大439MBだった(テスト用の PostgreSQL と Valkey を含む)
  - テストの最中のコンテナの中のプロセスは、Gradle のデーモン約1.6GB、テストのプロセス約0.7GB、Checkstyle と PMD のプロセス約0.36GBと約0.31GB、Gradle のラッパー約0.17GBだった
- **設計への影響**: backend の `check` を2つ同時に動かすと、約(3.74 + 0.44)× 2 ≒ 8.4GB になり、Docker の割り当て(約7.6GB)を超える。同時に走らせる数の初期値2のままでは、要件3.4(同時に走っても失敗しない)を、この作業PCで満たせない。設定の初期値か数え方を、所有者に決めてもらう必要がある。所有者は 2026-10-04 に、数え方は変えずに初期値を1にすると決めた

## 比べた作り方

| 作り方 | 中身 | よいところ | 弱いところ | 判断 |
|---|---|---|---|---|
| 作業フォルダごとに環境を丸ごと分ける(worktree-compose、Docktree の型) | worktree ごとに compose のプロジェクトを分け、DB・Redis・localstack・dind まで別に立てる | 実行環境が完全に分かれる | メモリを作業フォルダの数だけ使う。8GBでは2組が苦しい。ポートの割り当ても要る | 採らない |
| 1回きりのコンテナを作業フォルダごとに作る | 品質チェックと画面確認のたびに `docker compose -p keirekipro run` で、その作業フォルダを読み込んだコンテナを作る。DB・Redis・localstack・dind は本体の1組を共有する | メモリは走っている数の分だけで済む。同時に走らせる数を数で抑えられる。既存の `terraform-plan.yaml` も同じ型(`docker run -v "$PWD/terraform:/workspace"`) | ライブラリのキャッシュ(node_modules、Gradle)をコンテナの外に持たせる工夫が要る | 採る |
| 常駐コンテナの読み込み先を切り替える | 1組の常駐コンテナの読み込み先を、チェックのたびに作業フォルダへ付け替える | 変更が小さい | 付け替えのたびにコンテナを作り直すので、ほかのセッションの開発サーバやチェックを止める。同時に2つ走らせられない | 採らない |
| 1つのフォルダで複数のブランチを扱う(GitButler の仮想ブランチ) | worktree を使わない | 環境が1つで済む | 要件の「やらないこと」(同じ作業フォルダで複数のセッション)に当たる | 採らない |

## 設計の判断

### 判断: 品質チェックと画面確認を、作業フォルダごとの1回きりのコンテナで動かす

- **きっかけ**: 要件2(チェックはそのセッションの変更を検査する)と要件3(同時に走らせる数を設定で抑える)
- **比べた案**: 上の表のとおり
- **選んだ作り方**: 品質チェックのコマンド1つごとに、セッションの作業フォルダの最上位で `docker compose -p keirekipro run --rm --no-deps -T <サービス> <コマンド>` を動かす。node_modules と Gradle のプロジェクトのキャッシュは作業フォルダごとのボリュームに、Gradle のユーザーのキャッシュと pnpm のストアと terraform のプラグインのキャッシュは枠ごとのボリュームに置く
- **理由**: メモリは走っている数の分だけになる。本体の `dind` と DB を共有できるので、Testcontainers も開発用の DB もそのまま使える
- **引き換え**: 最初の1回は、作業フォルダごとに `pnpm install` が、枠ごとに Gradle のライブラリの取得が走る
- **あとで確かめること**: 枠ごとの Gradle のユーザーのキャッシュを、同時に2つのコンテナが使わないこと(枠は同時に1つのチェックしか持たない)

### 判断: キャッシュを作業フォルダごとと枠ごとに分ける

- **きっかけ**: Gradle のユーザーのキャッシュを、同時に動く別々のコンテナで共有すると、「Timeout waiting to lock … It is currently in use by another Gradle instance」で失敗する報告がある([gradle/gradle#851](https://github.com/gradle/gradle/issues/851)、[Gradle Forums](https://discuss.gradle.org/t/timeout-waiting-to-lock-checksums-cache-in-kubernetes-pods/44169))。回避策として挙がっているのは、コンテナごとにユーザーのキャッシュを分けることである
- **比べた案**:
  1. すべての作業フォルダで1つのキャッシュを共有する
  2. 作業フォルダごとにキャッシュを持つ
  3. 枠ごとにキャッシュを持つ
- **選んだ作り方**: 同時に使われると壊れうるもの(Gradle のユーザーのキャッシュ、pnpm のストア、terraform のプラグインのキャッシュ)は枠ごとに持つ。作業フォルダの中身に合わせるもの(node_modules、Gradle のプロジェクトのキャッシュ、DB)は作業フォルダごとに持つ
- **理由**: 枠は同時に1つのチェックしか持たないので、枠ごとのキャッシュは同時に使われない。キャッシュの数は設定の数で止まる
- **引き換え**: 設定の数を増やすと、そのぶん最初の取得が増える

### 判断: 同時に走らせる数の設定を `git config` に置く

- **比べた案**:
  1. git の管理下のファイル(PRで変える)
  2. git の管理外のファイルを本体フォルダに置く
  3. `git config --local keirekipro.parallelSlots`
- **選んだ作り方**: 3
- **理由**: 作業PCのメモリに合わせる値なので、PRを通さずに変えられ、作業PCごとに違ってよい。共有の `.git/config` に入るので、どの作業フォルダからも同じ値が読める。所有者は `git config keirekipro.parallelSlots 3` の1行で変えられる

### 判断: 順番待ちを、共有の `.git` の下のディレクトリの作成で数える

- **比べた案**:
  1. `flock` などのファイルロック(Git Bash の Windows では使えないことがある)
  2. 枠ごとのディレクトリを `mkdir` で作る(作れた枠を持つ。すでにあれば作れない)
- **選んだ作り方**: 2。`mkdir` はディレクトリが既にあれば失敗するので、2つのセッションが同時に同じ枠を取ることは無い
- **引き換え**: セッションが落ちると枠が残る。残った枠は、枠を持つコンテナが動いていないことで見分けて取り戻す

### 判断: セッションの記録をフックで付ける

- **比べた案**:
  1. Claude が `/start` のときだけ記録する(閉じたことが分からない)
  2. SessionStart と SessionEnd のフックで記録する
- **選んだ作り方**: 2。加えて、UserPromptSubmit のフックが最後に操作された時刻を記録する
- **理由**: 閉じたセッションの記録が消えるので、作業中のセッションを数えられる。SessionEnd が届かなかった記録は、要件どおり所有者に尋ねて片付ける。尋ねるときに最後に操作された時刻を添えられる

### 判断: 引き継ぎを、作りかけの写しで行い、前の作業フォルダを消さない

- **比べた案**:
  1. 前の worktree へこのセッションが移る(EnterWorktree。デスクトップアプリで使えるかは公式に書かれていない。このセッションの作業フォルダが空のまま残る)
  2. 前の作業フォルダの作りかけを、このセッションの作業フォルダに写す
- **選んだ作り方**: 2。前の作業フォルダの作りかけは、一時的な索引(`GIT_INDEX_FILE`)で1つのコミットの形にまとめ、前の作業フォルダの索引と中身を変えずに取り出す。前の作業フォルダがブランチを持っていれば、そのブランチを手放させて(`git -C <前> switch --detach`)、このセッションの作業フォルダで同じブランチに切り替える
- **理由**: 前の作業フォルダの中身を消さないので、引き継ぎに失敗しても作りかけが失われない

## 危うい点と手当て

- 2つの backend の `check` を同時に動かすと、Docker のメモリの割り当て(約7.6GB)を超えるおそれがある — 「メモリの測り直し」の結果で判断する
- SessionEnd がアプリの終了で届かず、閉じたセッションが作業中のまま残る — 所有者に尋ねるときに最後に操作された時刻を添え、所有者が「やめた」と答えたら記録を消す
- worktree を消すと、その作業フォルダ用のボリュームと DB が残る — `parallel-session.sh` が、作業フォルダが無くなった記録とボリュームと DB を片付ける
- 開発用の DB は作業フォルダごとに分けるが、Redis と localstack は共有する。画面確認でアップロードしたファイルなどは混ざる — 画面確認の結果(画面に出る変更)には影響しないので受け入れる

## 参考

- [Run parallel sessions with worktrees](https://code.claude.com/docs/en/worktrees.md) — worktree の作られ方、`.worktreeinclude`、`CLAUDE_PROJECT_DIR` と `cwd`
- [Hooks reference](https://code.claude.com/docs/en/hooks.md) — SessionStart・SessionEnd の入力と `additionalContext`
- [docker compose run](https://docs.docker.com/reference/cli/docker/compose/run/) — 1回きりのコンテナの作り方
- [Compose のサービスの定義](https://docs.docker.com/reference/compose-file/services/) — `env_file` の `required`、`container_name`
- [worktree-compose](https://www.worktree-compose.com/)、[Docktree](https://docktree.dev/) — worktree ごとに環境を分ける既存の道具
- [trigger.dev の記事](https://trigger.dev/blog/parallel-agents-gitbutler) — worktree の代わりに仮想ブランチを使う例と、その限界
