---
name: full-db-er-diagram-sync
description: 現在のバックエンドDBマイグレーションSQL全体を正として、doc/DB設計/ER図.pu を同期する。Git差分ではなく、migration SQL全体とER図の不一致を確認して修正する。
---

# Full Backend ER Diagram Sync

## Job

現在の DB マイグレーション SQL 全体を基準に、PlantUML ER図を同期する。

## Inputs

- DB migration SQL: `backend/src/main/resources/db/migration/*.sql`
- ER diagram: `doc/DB設計/ER図.pu`

## Outputs

- 修正した `doc/DB設計/ER図.pu`
- 変更内容
- 反映元の migration SQL ファイル

## Rules

- Git差分の有無で同期対象を判断しない。
- 現在存在する migration SQL 全体と `doc/DB設計/ER図.pu` を比較する。
- migration SQL を唯一の正とする。
- `.sql` は変更しない。
- `doc/DB設計/ER図.pu` だけを変更する。
- 必要な差分だけ最小差分で修正する。
- SQLに根拠のないテーブル、カラム、制約、リレーションを追加しない。
- 既存ER図の表記に合わせる。

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

migration SQL から以下を確認する。

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

1. `backend/src/main/resources/db/migration` 配下の現在存在する SQL ファイルを確認する。
2. `doc/DB設計/ER図.pu` を確認する。
3. migration SQL 全体と `doc/DB設計/ER図.pu` を比較する。
4. 不一致があれば `doc/DB設計/ER図.pu` だけ修正する。
5. 修正後、`doc/DB設計/ER図.pu` 以外のファイルを変更していないことを確認する。

## Report

```text
Changed files:
- doc/DB設計/ER図.pu
    - 変更内容: ...
    - 反映元: backend/src/main/resources/db/migration/...

Notes:
- ...
```
