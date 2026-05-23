---
name: full-backend-class-diagram-sync
description: 現在のバックエンドJavaソース全体を正として、doc/クラス図 配下のPlantUMLクラス図を同期する。Git差分ではなく、Javaソース全体とクラス図の不一致を確認して修正する。
---

# Full Backend Class Diagram Sync

## Job

現在の Java ソース全体を基準に、バックエンドの PlantUML クラス図を同期する。

## Inputs

- Java source: `backend/src/main/java/com/example/keirekipro`
- Class diagrams: `doc/クラス図/*.pu`

## Outputs

- 修正した `.pu` ファイル
- 各ファイルの変更内容
- 反映元の Java package / class

## Rules

- Git差分の有無で同期対象を判断しない。
- 現在存在する Java ファイルと `.pu` ファイルを比較する。
- Java ソースを唯一の正とする。
- `.java` は変更しない。
- 必要な `.pu` だけ最小差分で修正する。
- ソースに根拠のない型、field、method、依存関係を追加しない。
- 既存クラス図の表記に合わせる。

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

1. `backend/src/main/java/com/example/keirekipro` 配下の現在存在する Java ファイルを確認する。
2. `doc/クラス図` 配下の現在存在する `.pu` ファイルを確認する。
3. Java ソースとクラス図を比較する。

確認対象:

- 型の追加・削除
- package 移動
- rename
- class / interface / enum / record の種別
- field
- public method
- extends / implements
- constructor injection / field / method parameter / return type から分かる主要依存

4. 不一致があれば `.pu` だけ修正する。
5. 修正後、クラス図以外のファイルを変更していないことを確認する。

## Report

```text
Changed files:
- doc/クラス図/...
    - 変更内容: ...
    - 反映元: backend/src/main/java/com/example/keirekipro/...

Notes:
- ...
```
