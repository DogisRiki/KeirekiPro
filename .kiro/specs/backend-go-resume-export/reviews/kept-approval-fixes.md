# 承認を残して直した前の段階の記録

## 1. design を承認を残して直した(2026-11-23T08:04:24Z)

- 直した段階: design
- 見つけたレビュー: tasks のサイクル1 往復1
- もとになった穴: T1-1-7
- 直しをレビューする往復: tasks のサイクル1 往復2

### design.md「テストの方針」

直す前:

> - `pdfcmp.go`: 今の6つのテストを保ち、次の10の場合を足す。テストの PDF は、`pdf_helper_test.go` の作り方でテストの中で作る

直した後:

> - `pdfcmp.go`: 今の6つのテストは、確かめる場合を保ち、期待する違いの種類と説明を、PDF を比べる部品の節の違いの種類に替える。次の10の場合を足す。テストの PDF は、`pdf_helper_test.go` の作り方でテストの中で作る

### 差分

```diff
diff --git a/.claude/.state/spec-review/backend-go-resume-export__design.kept-fix-before.md b/.kiro/specs/backend-go-resume-export/design.md
index 481468c8..a7446478 100644
--- a/.claude/.state/spec-review/backend-go-resume-export__design.kept-fix-before.md
+++ b/.kiro/specs/backend-go-resume-export/design.md
@@ -620,7 +620,7 @@ Java 版と Go 版を比べる検査は、この spec の PR の必須のチェ
     - `httpapi.New` に `ResumeHandlers` を渡すと、28の操作の要求が受け口に届くこと
     - 応答の型の数を確かめるテストが28を確かめること
   - `auth.go`: `authRequestMiddleware` が、`ExportResume` のときに Accept の行を context に入れ、ほかの経歴書の操作では入れないこと
-  - `pdfcmp.go`: 今の6つのテストを保ち、次の10の場合を足す。テストの PDF は、`pdf_helper_test.go` の作り方でテストの中で作る
+  - `pdfcmp.go`: 今の6つのテストは、確かめる場合を保ち、期待する違いの種類と説明を、PDF を比べる部品の節の違いの種類に替える。次の10の場合を足す。テストの PDF は、`pdf_helper_test.go` の作り方でテストの中で作る
     - 頁の大きさの違いを 0.3pt なら許し、0.6pt なら違いとすること
     - 字の直し方が、互換漢字と U+2011 と U+FF5E を直し、空白を除くこと。CJK の字は Type1 の標準フォントで作れないので、この場合のテストは、PDF を作らずに `normalizeText` を直接呼ぶ
     - 同じ字の段落を、Go 版で1行少なく折り返した PDF を許すこと
```
