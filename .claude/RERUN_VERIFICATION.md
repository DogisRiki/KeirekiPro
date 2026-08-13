# 検証用の一時ファイル

`.github/workflows/rerun-approval-gated-checks.yaml`(#147)の動作確認のために作成した。

`.claude/` はCODEOWNERS保護対象のため、このファイルを含むPRでは `escape-hatch` が
所有者の承認まで赤になる。承認後に再実行が自動で行われ緑に変わることを確認する。

確認が済んだらPRごとクローズし、このファイルはmainへ入れない。
