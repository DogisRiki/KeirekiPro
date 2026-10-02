# design の観点

## 前提

design は「どう作るか」を決める。requirements が「何を」しか言わないため、要件が縛らない部分は design が決めている。

requirements と違い、**照合できる相手がある**(requirements.md)。ただし厳密化した中身は照合できない。

生成側には書く前の自己点検(`.claude/skills/kiro-spec-design/rules/design-review-gate.md`)がある。**その点検は `KeirekiPro Compliance Check` のセクションに一切言及していない。** ここが最も空いている。

spec.json の `spec_format` が2の spec では、見出しと目印を `.kiro/settings/rules/spec-writing.md` の対応表の新しい名前で読む。`KeirekiPro Compliance Check` は `## プロジェクトの決まりを守っているか`、`File Structure Plan` は `## ファイルの構成` である。`Boundary Commitments` は `## 作るものと作らないもの`・`## 使う既存の仕組み`・`## 設計を見直すきっかけ` の3つの節に分かれる。`This Spec Owns` は `## 作るものと作らないもの` の節の `### 作るもの`、`Out of Boundary` と `Non-Goals` は同じ節の `### 作らないもの` である。`spec_format` の欄が無い spec では、今の名前のまま読む。

## 観点

### 1. 申告

`common.md` の申告の規則に従う。design で申告するのは次の3種類。

- 人間の承認が要る領域に触れる決定(マイグレーション、新しいライブラリ、ゲート設定の変更)
- 運用から見える振る舞いの決定(失敗したときの扱い、再試行、通知)
- 後から変えにくい決定(データの持ち方、外部サービスへの依存)

**申告しないもの**: リポジトリの規約で決まっているもの(backend の層配置、frontend の feature 境界、server state は TanStack Query、client state は Zustand)。選ぶ余地が無いため。

### 2. 要件カバレッジ

すべての要件が design に現れ、具体的なコンポーネント・契約・フロー・データモデル・運用上の決定のいずれかで裏付けられているか。ID が出てくるだけで実現する要素が無いものを探す。

### 3. KeirekiPro Compliance Check と本文の矛盾

審査の基準にする雛形は、`spec_format` の欄が無い spec では `.kiro/settings/templates/specs-v1/design.md`、`spec_format` が2の spec では `.kiro/settings/templates/specs/design.md` である。その雛形が定める7項目について、次を見る。

- 7項目すべてにチェックが入っているか。該当しない項目に N/A と理由が書かれているか
- `spec_format` が2の spec では、7項目の名前が「backend のコードを置く層」「frontend の機能ごとの境界」「frontend の状態の持ち方」「データベースの表の形」「新しいライブラリの追加」「品質チェックの設定」「使う外部の機能がこのリポジトリで使えるか」に変わる。この spec では、チェックと N/A の代わりに、関係のある項目に中身が書かれていること、関係のない項目が「関係のない項目:」の1行に名前だけで並んでいること、7つの項目のすべてがどちらかに出ていることを確かめる
- **チェックの記載と設計本文が矛盾していないか。** 例: 「ゲート設定の変更を必要としない」と書きながら File Structure Plan に `.github/` のファイルが並んでいる。「依存追加なし」と書きながら新しいライブラリが出てくる
- 7項目目「前提機能の利用可否」について、**実測したという主張に、いつ何をどう確かめたかが書かれているか。** 「実測済み」の一言で済ませていないか

### 4. 境界と本文の食い違い

`Boundary Commitments` の `This Spec Owns` と `Out of Boundary` に書いたことを、設計本文が破っていないか。`Non-Goals` に挙げたものを実質的に扱っていないか。

### 5. 設計内の矛盾

ある節と別の節が違うことを言っていないか。

### 6. 実現できない設計

前提にした外部サービスの機能が、このリポジトリの条件(アカウントの種別、プラン、リポジトリの可視性、地域、有効化の要否)で実際に使えるか。**設定項目が何かではなく、そもそも使えるかを見る。** ここを外すと、実装して初めて分かり、設計からやり直しになる。

### 7. 前の段階への指摘

設計に落とそうとして初めて分かった、requirements の不足・曖昧さ・矛盾。`common.md` の規則に従い、別の節に書く。

### 8. 誤字脱字

`common.md` の分類に従う。
