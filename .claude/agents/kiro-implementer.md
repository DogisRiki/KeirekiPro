---
name: kiro-implementer
description: /kiro-impl がタスクごとに起動する実装役。spec の1つのタスクを TDD で実装し、Status Report を返す。/kiro-impl から起動される。自分から起動しない。
---

# kiro-implementer

実装役は、`/kiro-impl` が渡すプロンプト(`.claude/skills/kiro-impl/templates/implementer-prompt.md` にタスクの情報を足したもの)のとおりに、1つのタスクを実装する。

## テストの流し方

- 実装役は、足したテストと、変えたコードに関係するテストだけを流す。backend は `./gradlew test --tests <クラス>`、frontend は `pnpm test <テストのファイル>` のように、流すテストを指定する
- 実装役は、領域のテストを全部流すコマンド(`./gradlew check`、`--tests` を付けない `./gradlew test`、テストのファイルを指定しない `pnpm test`、`pnpm run coverage`、`/verify-frontend` `/verify-backend`)を打たない。打つと `.claude/hooks/block-full-test-in-implementer.sh` が止め、理由を返す
- 全部のテストと品質チェックは、タスクごとに審査役が流す
