# 承認を残して直した前の段階の記録

## 1. requirements を承認を残して直した(2026-11-22T01:59:45Z)

- 直した段階: requirements
- 見つけたレビュー: design のサイクル8 往復1
- もとになった穴: D8-1-3
- 直しをレビューする往復: design のサイクル8 往復2

### requirements.md「決めた方式」

直す前:

> - 本番で動いているイメージに脆弱性が見つかり、仕組みがラベル `container-vuln` の Issue を起票したときは、修正版がある脆弱性について、Claude が脆弱性を消す PR を作る。修正版がまだ無いときは、Claude は PR を作らず、Issue はそのまま残る。(AIの提案を了承)
> - Dependabot の PR が、脆弱性ではない理由で赤のまま止まり、週次監査がその PR を見つけたときは、Claude が、止まった原因を直す PR を別に作る。Claude は Dependabot の PR を閉じず、Dependabot へのコマンドも打たない。(AIの提案を了承)
> - 仕組みが GitHub Actions の中で動かす Claude の費用は、所有者の Claude の契約で払う。API キーは使わない。

直した後:

> - 本番で動いているイメージに脆弱性が見つかり、仕組みがラベル `container-vuln` の Issue を起票したときは、修正版がある脆弱性について、Claude が脆弱性を消す PR を作る。修正版がまだ無いときは、Claude は PR を作らず、Issue はそのまま残る。(AIの提案を了承)
> - Dependabot の PR が、脆弱性ではない理由で赤のまま止まり、週次監査がその PR を見つけたときは、Claude が、止まった原因を直す PR を別に作る。Claude は Dependabot の PR を閉じず、Dependabot へのコマンドも打たない。(AIの提案を了承)
> - 仕組みが GitHub Actions の中で動かす Claude の費用は、所有者の Claude の契約で払う。API キーは使わない。
> - 仕組みは、Claude と、Claude が変えたコードを動かすワークフローの実行を、main とは別の専用のブランチで起動する。その実行が作るキャッシュを、main のワークフローが読まないようにするためである。(AIの提案を了承)

### 差分

```diff
diff --git a/.claude/.state/spec-review/claude-auto-fix-unresolved-alerts__requirements.kept-fix-before.md b/.kiro/specs/claude-auto-fix-unresolved-alerts/requirements.md
index 08e7679b..6287d344 100644
--- a/.claude/.state/spec-review/claude-auto-fix-unresolved-alerts__requirements.kept-fix-before.md
+++ b/.kiro/specs/claude-auto-fix-unresolved-alerts/requirements.md
@@ -32,6 +32,7 @@ frontend-vuln-fix と backend-vuln-fix が警告を消す PR を作れずに実
 - 本番で動いているイメージに脆弱性が見つかり、仕組みがラベル `container-vuln` の Issue を起票したときは、修正版がある脆弱性について、Claude が脆弱性を消す PR を作る。修正版がまだ無いときは、Claude は PR を作らず、Issue はそのまま残る。(AIの提案を了承)
 - Dependabot の PR が、脆弱性ではない理由で赤のまま止まり、週次監査がその PR を見つけたときは、Claude が、止まった原因を直す PR を別に作る。Claude は Dependabot の PR を閉じず、Dependabot へのコマンドも打たない。(AIの提案を了承)
 - 仕組みが GitHub Actions の中で動かす Claude の費用は、所有者の Claude の契約で払う。API キーは使わない。
+- 仕組みは、Claude と、Claude が変えたコードを動かすワークフローの実行を、main とは別の専用のブランチで起動する。その実行が作るキャッシュを、main のワークフローが読まないようにするためである。(AIの提案を了承)
 
 ## はじめに
 
```
