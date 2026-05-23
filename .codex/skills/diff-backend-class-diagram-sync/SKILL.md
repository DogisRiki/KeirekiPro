---
name: diff-backend-class-diagram-sync
description: Git差分に含まれるバックエンドJavaソースの変更を正として、doc/クラス図 配下のPlantUMLクラス図へ同期する。Javaコード変更後に実行し、全Javaソース走査ではなく差分ベースで対象を絞る。
---

# Diff Backend Class Diagram Sync

## Job

Git差分に含まれるバックエンド Java ソースの変更を基準に、該当する PlantUML クラス図を同期する。

## Inputs

- Git diff
- Java source: `backend/src/main/java/com/example/keirekipro`
- Class diagrams: `doc/クラス図/*.pu`

## Outputs

- 修正した `.pu` ファイル
- 各ファイルの変更内容
- 反映元の Java package / class
- 差分判定に使った Java ファイル

## Rules

- Git差分に含まれる Java ファイルを同期対象の起点にする。
- Java ソースを唯一の正とする。
- `.java` は変更しない。
- `.pu` だけを変更する。
- 必要な `.pu` だけ最小差分で修正する。
- Git差分に関係しないクラス図は変更しない。
- ソースに根拠のない型、field、method、依存関係を追加しない。
- 既存クラス図の表記に合わせる。

## Target detection

まず Git 差分から変更された Java ファイルを取得する。

確認対象:

- staged diff
- unstaged diff
- untracked Java files

対象は以下配下に限定する。

```text
backend/src/main/java/com/example/keirekipro
```

Java ファイル以外は同期対象にしない。

## Diagram style

既存図の形式を維持する。

- `@startuml xxxクラス図`
- `title xxxクラス図`
- `skinparam classAttributeIconSize 0`
- `skinparam linetype ortho`
- package ごとの区切りコメント
- 完全修飾 package block
- field: `- Type name`
- method: `+ ReturnType name(...)`
- field と method の区切り: `--`
- record: `class Xxx <<record>>`
- Value Object: `<<Value Object>>`
- Aggregate Root: `<<Aggregate Root>>`
- nested type: `"Outer.Inner" as Inner`

関係線は既存図に合わせる。

- 継承: `Child --|> Parent`
- interface実装: `Class ..|> Interface`
- 依存: `A ..> B`
- 関連: `A --> B`
- 集約内の所有: `A "1" *-- "0..*" B : name`

## Layer mapping

| package | diagram |
|---|---|
| `domain` | `クラス図_ドメイン層.pu` |
| `usecase` | `クラス図_ユースケース層.pu` |
| `infrastructure` | `クラス図_インフラストラクチャ層.pu` |
| `presentation` | `クラス図_プレゼンテーション層.pu` |
| top-level `shared` | `クラス図_シェア.pu` |

レイヤー配下の `shared` は、そのレイヤーの図に置く。

## Steps

1. Git差分に含まれる Java ファイルを確認する。
2. 変更された Java ファイルの package から、更新対象の `.pu` ファイルを特定する。
3. 対象 Java ファイルについて、以下を確認する。

確認対象:

- 型の追加・削除
- package 移動
- rename
- class / interface / enum / record の種別
- field
- public method
- extends / implements
- constructor injection / field / method parameter / return type から分かる主要依存

4. 対応する `.pu` ファイルだけを確認する。
5. Java ソースとクラス図に不一致があれば `.pu` だけ修正する。
6. 修正後、Java ファイルを変更していないことを確認する。
7. 修正後、Git差分に関係しない `.pu` ファイルを変更していないことを確認する。

## Report

```text
Changed files:
- doc/クラス図/...
    - 変更内容: ...
    - 反映元: backend/src/main/java/com/example/keirekipro/...
    - 判定元: git diff

Notes:
- ...
```
