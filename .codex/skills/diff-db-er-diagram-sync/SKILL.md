---
name: diff-db-er-diagram-sync
description: Git差分に含まれるバックエンドDBマイグレーションSQLの変更を正として、doc/DB設計/ER図.pu へ同期する。SQL変更後に実行し、全SQL走査ではなく差分ベースで対象を絞る。
---

# Diff Backend ER Diagram Sync

## Job

Git差分に含まれる DB マイグレーション SQL の変更を基準に、PlantUML ER図を同期する。

## Inputs

- Git diff
- DB migration SQL: `backend/src/main/resources/db/migration/*.sql`
- ER diagram: `doc/DB設計/ER図.pu`

## Outputs

- 修正した `doc/DB設計/ER図.pu`
- 変更内容
- 反映元の migration SQL ファイル
- 差分判定に使った SQL ファイル

## Rules

- Git差分に含まれる migration SQL を同期対象の起点にする。
- migration SQL を唯一の正とする。
- `.sql` は変更しない。
- `doc/DB設計/ER図.pu` だけを変更する。
- 必要な差分だけ最小差分で修正する。
- Git差分に関係しないER図変更をしない。
- SQLに根拠のないテーブル、カラム、制約、リレーションを追加しない。
- 既存ER図の表記に合わせる。

## Target detection

まず Git 差分から変更された SQL ファイルを取得する。

確認対象:

- staged diff
- unstaged diff
- untracked SQL files

対象は以下配下に限定する。

```text
backend/src/main/resources/db/migration
```

SQL ファイル以外は同期対象にしない。

## Diagram style

既存ER図の形式を維持する。

- `@startuml ER図`
- `title ER図`
- `entity "論理名(physical_table_name)" as Alias`
- PK: `+ column : <color:#1E90FF>TYPE</color> -- 説明 (PK)`
- 通常カラム: `column : <color:#1E90FF>TYPE</color> -- 説明`
- 制約: `<color:#32CD32>[NOT NULL]</color>` など既存表記に合わせる
- PK と通常カラムの区切り: `--`
- リレーション定義は既存の `||--o{` などの表記に合わせる
- 既存の日本語論理名・コメント表記を維持する

## Check targets

差分に含まれる migration SQL から以下を確認する。

- テーブル追加・削除
- カラム追加・削除
- カラム名変更
- データ型
- nullable / not null
- default
- primary key
- unique
- foreign key
- join table
- relation cardinality
- master table
- index はER図に既存表現がある場合のみ反映する

## Steps

1. Git差分に含まれる SQL ファイルを確認する。
2. 対象が `backend/src/main/resources/db/migration` 配下の `.sql` であることを確認する。
3. 差分に含まれる SQL の変更内容を確認する。
4. `doc/DB設計/ER図.pu` を確認する。
5. SQL差分と `doc/DB設計/ER図.pu` に不一致があれば、`doc/DB設計/ER図.pu` だけ修正する。
6. 修正後、SQLファイルを変更していないことを確認する。
7. 修正後、`doc/DB設計/ER図.pu` 以外のファイルを変更していないことを確認する。

## Report

```text
Changed files:
- doc/DB設計/ER図.pu
    - 変更内容: ...
    - 反映元: backend/src/main/resources/db/migration/...
    - 判定元: git diff

Notes:
- ...
```
