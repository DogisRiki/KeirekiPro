#!/usr/bin/env bash
# =====================================================================
# check-dependency-snapshot.sh の自動テスト(CIから実行)
#
# 一時ディレクトリにスナップショットを置いて終了コードを検証する。
#   0 = 緑(通過) / 1 = 赤
#
# 各ケースは「seed → 内容を作る関数 → run_check」の3行で書く。内容を作る関数を
# 引数で渡す形にしないのは、静的解析が引数位置の関数名を参照と数えず、
# 未使用の関数として報告してしまうため。コマンド位置で呼べば抑制指示が要らない。
# =====================================================================
set -uo pipefail

SCRIPT="$(cd "$(dirname "$0")/.." && pwd)/check-dependency-snapshot.sh"
WORK=$(mktemp -d) || exit 1
[ -n "$WORK" ] && [ -d "$WORK" ] || exit 1
trap 'rm -rf "$WORK"' EXIT
FAILED=0

# jq が無いと正常系が全て赤になり、原因が「テストの失敗」に見えてしまう。
# 先に切り分けて止める(CIのランナーには入っている)。
if ! command -v jq >/dev/null 2>&1; then
    echo "FAIL: jq が見つかりません。この検査には jq が要ります。"
    exit 1
fi

REPORTS="$WORK/reports"

seed() {
    rm -rf "$REPORTS"
    mkdir -p "$REPORTS"
}

run_check() {
    local want="$1" name="$2" got
    : >"$WORK/summary.md"
    GITHUB_STEP_SUMMARY="$WORK/summary.md" bash "$SCRIPT" "$REPORTS" >"$WORK/out.txt" 2>&1
    got=$?
    if [ "$got" -eq "$want" ]; then
        echo "PASS: $name"
    else
        echo "FAIL: $name (expected exit $want, got $got)"
        FAILED=1
    fi
}

check_output() {
    if grep -qF "$1" "$WORK/out.txt"; then
        echo "PASS: $2"
    else
        echo "FAIL: $2 (出力に '$1' が現れない)"
        FAILED=1
    fi
}

# --- 内容を作る関数 -------------------------------------------------------------
write_populated() {
    cat >"$REPORTS/backend.json" <<'JSON'
{
  "version": 0,
  "manifests": {
    "backend": {
      "name": "backend",
      "resolved": {
        "pkg:maven/org.example/a@1.0.0": { "package_url": "pkg:maven/org.example/a@1.0.0" },
        "pkg:maven/org.example/b@2.0.0": { "package_url": "pkg:maven/org.example/b@2.0.0" }
      }
    }
  }
}
JSON
}

write_second_file() {
    cat >"$REPORTS/extra.json" <<'JSON'
{
  "version": 0,
  "manifests": {
    "other": {
      "name": "other",
      "resolved": {
        "pkg:maven/org.example/c@3.0.0": { "package_url": "pkg:maven/org.example/c@3.0.0" }
      }
    }
  }
}
JSON
}

write_empty_resolved() {
    cat >"$REPORTS/backend.json" <<'JSON'
{
  "version": 0,
  "manifests": {
    "backend": { "name": "backend", "resolved": {} }
  }
}
JSON
}

write_no_manifests() {
    cat >"$REPORTS/backend.json" <<'JSON'
{ "version": 0, "manifests": {} }
JSON
}

write_missing_manifests_key() {
    cat >"$REPORTS/backend.json" <<'JSON'
{ "version": 0 }
JSON
}

write_broken_json() {
    printf '{ "manifests": { "backend": ' >"$REPORTS/backend.json"
}

write_non_json_file() {
    echo "not json" >"$REPORTS/notes.txt"
}

remove_reports_dir() {
    rm -rf "$REPORTS"
}

echo "--- 正常系 ---"
seed
write_populated
run_check 0 "解決済みパッケージがあれば通す"
check_output "解決されたパッケージ数: 2" "件数が出力される"

seed
write_populated
write_second_file
run_check 0 "複数のJSONを合算して通す"
check_output "解決されたパッケージ数: 3" "合算した件数が出力される"

seed
write_populated
write_non_json_file
run_check 0 "JSON以外のファイルは無視する"

echo "--- 空 ---"
seed
write_empty_resolved
run_check 1 "resolved が空なら落とす"
check_output "依存グラフが空です" "空である旨が出る"

seed
write_no_manifests
run_check 1 "manifests が空なら落とす"

seed
write_missing_manifests_key
run_check 1 "manifests キーが無ければ落とす"

echo "--- 解析できない入力 ---"
seed
write_broken_json
run_check 1 "壊れたJSONは0件扱いにせず落とす"
check_output "スナップショットを解析できません" "解析失敗が報告される"

echo "--- 出力先の異常 ---"
seed
run_check 1 "JSONが1件も無ければ落とす"
check_output "JSONが1件もありません" "JSON不在が報告される"

seed
remove_reports_dir
run_check 1 "出力先が存在しなければ落とす"
check_output "出力先が存在しません" "出力先不在が報告される"

if [ "$FAILED" -eq 0 ]; then
    echo "すべてのテストがPASSしました。"
else
    echo "失敗したテストがあります。"
fi
exit "$FAILED"
