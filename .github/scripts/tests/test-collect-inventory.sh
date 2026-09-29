#!/usr/bin/env bash
# =====================================================================
# collect-inventory.sh の自動テスト(audit-inventory CI の自己テストから実行)
#
# 仮のリポジトリ(一時ディレクトリ)に宣言のファイルを置き、次を確かめる。
#   - 設定ファイルの形の確認(今のリポジトリの設定ファイルと、形の違う設定)
#   - 宣言の読み取り(版と行番号、1つの対象の複数の宣言、ファイルが無い、
#     一致しない、正規表現の誤り、複数行にまたがる正規表現)
#   - 表の行の組み立て(複数の宣言を1行にまとめる、同じ版の場所の「ほかNか所」、
#     「読み取れず」、サポート期限の公表が無い対象の「公表なし」、
#     表に入れる値からの `|` と改行の除去、良し悪しの記号を付けないこと)
#   - 版から系列を取り出す正規表現
# 外部への問い合わせを行わないため、実行にネットワークを必要としない。
#
# 今のリポジトリの宣言を読む検査:
#   環境変数 INVENTORY_CHECK_REPO=1 のときだけ動かす。設定ファイルの書き誤り
#   (場所や正規表現の誤り)を出荷前に見つけるためのもの。月1回の実行の自己
#   テストでは動かさない。後で宣言の書き方が変わっても、表は「読み取れず」の
#   欄つきで届けるため(要件2-6)。
# =====================================================================
set -uo pipefail

SCRIPT="$(cd "$(dirname "$0")/.." && pwd)/collect-inventory.sh"
REPO_ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
REAL_TARGETS="${REPO_ROOT}/.github/audit/inventory-targets.json"
WORK=$(mktemp -d) || exit 1
[ -n "$WORK" ] && [ -d "$WORK" ] || exit 1
trap 'rm -rf "$WORK"' EXIT
FAILED=0

if [ ! -f "$SCRIPT" ]; then
    echo "FAIL: ${SCRIPT} がありません"
    exit 1
fi
# shellcheck source=.github/scripts/collect-inventory.sh
source "$SCRIPT"

pass() { echo "PASS: $1"; }
fail() {
    echo "FAIL: $1"
    FAILED=1
}

# 使い方: check_eq <期待> <実際> <説明>
check_eq() {
    if [ "$1" = "$2" ]; then
        pass "$3"
    else
        fail "$3"
        echo "     期待: $1"
        echo "     実際: $2"
    fi
}

# 使い方: check_rc <期待する戻り値> <実際の戻り値> <説明>
check_rc() {
    if [ "$1" -eq "$2" ]; then
        pass "$3"
    else
        fail "$3 (期待 $1 / 実際 $2)"
    fi
}

# --- 仮のリポジトリ ------------------------------------------------------------
ROOT="$WORK/repo"
mkdir -p "$ROOT/docker/frontend" "$ROOT/docker/terraform" "$ROOT/wf" "$ROOT/tf"

cat >"$ROOT/docker/frontend/Dockerfile" <<'TXT'
FROM node:24.21.0-bookworm-slim@sha256:0000
RUN echo
TXT
# 1本のファイルに2か所、別のファイルに1か所、同じ版がある。別の版も1か所ある
cat >"$ROOT/wf/a.yaml" <<'TXT'
jobs:
  a:
    node-version: '24.16.0'
  b:
    x: 1
    y: 2
    node-version: '24.16.0'
TXT
cat >"$ROOT/wf/b.yaml" <<'TXT'
steps:
  node-version: "24.16.0"
TXT
cat >"$ROOT/wf/c.yaml" <<'TXT'
a
b
c
d
  node-version: 22.1.0
TXT
cat >"$ROOT/docker/terraform/Dockerfile" <<'TXT'
# comment

FROM hashicorp/terraform:1.16.4@sha256:1111
TXT
cat >"$ROOT/wf/plan.yaml" <<'TXT'
env:
  TF_VERSION: '1.9.0'
TXT
cat >"$ROOT/wf/apply.yaml" <<'TXT'
on: push

env:
  TF_VERSION: '1.9.0'
TXT
cat >"$ROOT/wf/nomatch.txt" <<'TXT'
FROM alpine
TXT
# 複数行にまたがる正規表現と、前の行の日本語(文字の位置と行番号の対応を確かめる)
cat >"$ROOT/tf/.tflint.hcl" <<'TXT'
# 日本語の説明
plugin "terraform" {
  enabled = true
}

plugin "aws" {
  enabled = true
  version = "0.44.0"
}
TXT
# 表を崩す文字を含む値
cat >"$ROOT/wf/pipe.txt" <<'TXT'
ver: 1.0|evil
TXT

cat >"$WORK/targets.json" <<'JSON'
{
  "targets": [
    {
      "name": "Node.js",
      "declarations": [
        { "files": ["docker/frontend/Dockerfile"], "pattern": "(?m)^FROM node:(?<version>[0-9]+\\.[0-9]+\\.[0-9]+)" },
        { "files": ["wf/a.yaml", "wf/b.yaml", "wf/c.yaml"], "pattern": "(?m)^[ \\t]*node-version:[ \\t]*['\"]?(?<version>[0-9][0-9.]*)" }
      ],
      "latest": { "type": "endoflife", "product": "nodejs" },
      "support": { "type": "endoflife", "product": "nodejs", "cycle_pattern": "^(?<cycle>[0-9]+)" }
    },
    {
      "name": "Terraform",
      "declarations": [
        { "files": ["docker/terraform/Dockerfile"], "pattern": "(?m)^FROM hashicorp/terraform:(?<version>[0-9]+(?:\\.[0-9]+)*)" },
        { "files": ["wf/plan.yaml", "wf/apply.yaml"], "pattern": "(?m)^[ \\t]*TF_VERSION:[ \\t]*['\"]?(?<version>[0-9][0-9.]*)" }
      ],
      "latest": { "type": "endoflife", "product": "terraform" },
      "support": { "type": "endoflife", "product": "terraform", "cycle_pattern": "^(?<cycle>[0-9]+\\.[0-9]+)" }
    },
    {
      "name": "tflint",
      "declarations": [
        { "files": ["missing/Dockerfile", "wf/nomatch.txt", "wf/a.yaml"], "pattern": "(?m)^FROM ghcr\\.io/terraform-linters/tflint:(?<version>v[0-9.]+)" }
      ],
      "latest": { "type": "github-release", "repo": "terraform-linters/tflint" },
      "support": null
    },
    {
      "name": "ルールセット",
      "declarations": [
        { "files": ["tf/.tflint.hcl"], "pattern": "plugin \"aws\" \\{[^}]*?\\bversion[ \\t]*=[ \\t]*\"(?<version>[0-9][^\"]*)\"" }
      ],
      "latest": { "type": "github-release", "repo": "terraform-linters/tflint-ruleset-aws" },
      "support": null
    },
    {
      "name": "正規表現の誤り",
      "declarations": [
        { "files": ["wf/a.yaml"], "pattern": "(?<version>[0-9]" }
      ],
      "latest": { "type": "pypi", "package": "x" },
      "support": null
    },
    {
      "name": "名前付きグループなし",
      "declarations": [
        { "files": ["wf/a.yaml"], "pattern": "node-version" }
      ],
      "latest": { "type": "pypi", "package": "x" },
      "support": null
    },
    {
      "name": "区切り|を含む",
      "declarations": [
        { "files": ["wf/pipe.txt"], "pattern": "ver: (?<version>[^\\n]*)" }
      ],
      "latest": { "type": "dockerhub-tags", "repository": "a/b", "tag_pattern": "^[0-9]+$" },
      "support": { "type": "endoflife", "product": "x", "cycle_pattern": "^(?<cycle>[0-9]+)" }
    }
  ]
}
JSON

# 使い方: target_of <名前>  仮の設定の中の対象を1つ JSON で出す
target_of() {
    jq -c --arg n "$1" '.targets[] | select(.name == $n)' "$WORK/targets.json"
}

# 使い方: row_of <名前> <最新のリリースの欄(JSON)> <サポートの3列(JSON または null)>
# 宣言を読み、外から渡した欄と合わせて表の行を組み立てる
row_of() {
    local record
    record=$(inv_read_target "$ROOT" "$(target_of "$1")") || return 1
    record=$(jq -c --argjson latest "$2" --argjson support "$3" \
        '. + {latest: $latest, support: $support}' <<<"$record") || return 1
    inv_table_row "$record"
}

# ---------------------------------------------------------------------------
echo "--- 設定ファイルの形 ---"

inv_validate_targets "$REAL_TARGETS" >/dev/null 2>&1
check_rc 0 $? "今のリポジトリの設定ファイルは形が正しい"

count=$(jq '.targets | length' "$REAL_TARGETS" 2>/dev/null)
check_eq "13" "$count" "今のリポジトリの設定ファイルの対象は13件"

names=$(jq -r '[.targets[].name] | join(",")' "$REAL_TARGETS" 2>/dev/null)
check_eq "tflint,tflint の AWS 用ルールセット,checkov,Trivy,Java,Node.js,PostgreSQL(開発),PostgreSQL(本番),Redis(開発),Valkey(本番),Terraform,Docker(dind),LocalStack" \
    "$names" "対象は設計の一覧のとおり(要件1-1)"

got=$(jq -r '.targets[] | select(.name == "LocalStack") | .latest.tag_pattern' "$REAL_TARGETS" 2>/dev/null)
check_eq '^[0-9]{4}\.[1-9][0-9]?\.[0-9]+$' "$got" "LocalStack のタグの正規表現は月の先頭の0を許さない"

got=$(jq -r '[.targets[] | select(.support == null) | .name] | join(",")' "$REAL_TARGETS" 2>/dev/null)
check_eq "tflint,tflint の AWS 用ルールセット,checkov,Trivy,LocalStack" "$got" \
    "サポート期限の公表が無い対象は support が null(要件1-5)"

inv_validate_targets "$WORK/targets.json" >/dev/null 2>&1
check_rc 0 $? "仮の設定ファイルは形が正しい"

# 使い方: check_invalid <jq の変換> <説明>
# 仮の設定ファイルを変換したものが、形の違反として見分けられること
check_invalid() {
    jq "$1" "$WORK/targets.json" >"$WORK/bad.json"
    inv_validate_targets "$WORK/bad.json" >/dev/null 2>&1
    check_rc 1 $? "形の違反: $2"
}
check_invalid '.targets = {}' "targets が配列でない"
check_invalid '.targets = []' "targets が空"
check_invalid 'del(.targets[0].name)' "name が無い"
check_invalid '.targets[0].declarations = []' "declarations が空"
check_invalid '.targets[0].declarations[0].files = []' "files が空"
check_invalid 'del(.targets[0].declarations[0].pattern)' "pattern が無い"
check_invalid 'del(.targets[0].latest)' "latest が無い"
check_invalid '.targets[0].latest = {"type": "npm", "package": "x"}' "latest の種類が不明"
check_invalid 'del(.targets[2].latest.repo)' "github-release に repo が無い"
check_invalid 'del(.targets[4].latest.package)' "pypi に package が無い"
check_invalid 'del(.targets[6].latest.tag_pattern)' "dockerhub-tags に tag_pattern が無い"
check_invalid 'del(.targets[0].latest.product)' "endoflife に product が無い"
check_invalid 'del(.targets[2].support)' "support が無い(null と区別する)"
check_invalid 'del(.targets[0].support.cycle_pattern)' "support に cycle_pattern が無い"
check_invalid '.targets[0].support.type = "other"' "support の種類が不明"
printf '{"targets": [' >"$WORK/broken.json"
inv_validate_targets "$WORK/broken.json" >/dev/null 2>&1
check_rc 1 $? "形の違反: JSON として読めない"
inv_validate_targets "$WORK/none.json" >/dev/null 2>&1
check_rc 1 $? "形の違反: ファイルが無い"

# ---------------------------------------------------------------------------
echo "--- 宣言の読み取り ---"

got=$(inv_read_target "$ROOT" "$(target_of "Node.js")" | jq -c '.used')
check_eq '[{"file":"docker/frontend/Dockerfile","line":1,"version":"24.21.0"},{"file":"wf/a.yaml","line":3,"version":"24.16.0"},{"file":"wf/a.yaml","line":7,"version":"24.16.0"},{"file":"wf/b.yaml","line":2,"version":"24.16.0"},{"file":"wf/c.yaml","line":5,"version":"22.1.0"}]' \
    "$got" "複数の宣言の全ての場所と版を、宣言とファイルの順に読む(要件1-2)"

got=$(inv_read_target "$ROOT" "$(target_of "ルールセット")" | jq -c '.used')
check_eq '[{"file":"tf/.tflint.hcl","line":8,"version":"0.44.0"}]' \
    "$got" "複数行にまたがる正規表現でも、版の行番号を出す(前の行に日本語があっても)"

got=$(inv_read_target "$ROOT" "$(target_of "tflint")" | jq -c '.used')
check_eq '[{"file":"missing/Dockerfile","line":null,"version":null},{"file":"wf/nomatch.txt","line":null,"version":null},{"file":"wf/a.yaml","line":null,"version":null}]' \
    "$got" "ファイルが無い・一致しない場所を、読めなかった場所として残す(要件2-6)"

got=$(inv_read_target "$ROOT" "$(target_of "正規表現の誤り")" 2>/dev/null | jq -c '.used')
check_eq '[{"file":"wf/a.yaml","line":null,"version":null}]' \
    "$got" "正規表現の誤りは止まらずに読めなかった場所になる"

got=$(inv_read_target "$ROOT" "$(target_of "名前付きグループなし")" | jq -c '.used')
check_eq '[{"file":"wf/a.yaml","line":null,"version":null}]' \
    "$got" "名前付きグループ version が無い正規表現は読めなかった場所になる"

got=$(inv_read_target "$ROOT" "$(target_of "Node.js")" | jq -r '.name')
check_eq "Node.js" "$got" "読み取りの結果に対象の名前を持つ"

# 1行目の先頭の版(文字の位置が0)も1行目として数える
got=$(inv_read_target "$ROOT" '{"name": "先頭", "declarations": [{"files": ["wf/c.yaml"], "pattern": "(?<version>a)"}], "support": null}' | jq -c '.used')
check_eq '[{"file":"wf/c.yaml","line":1,"version":"a"}]' "$got" "ファイルの先頭の版を1行目として数える"

# ---------------------------------------------------------------------------
echo "--- 表の行 ---"

got=$(inv_table_header)
check_eq "$(printf '%s\n%s' '| 対象 | 使っている版(書いてある場所) | 最新のリリース | 使っている系列のサポート期限 | 期限切れ | 最新の系列 |' '|---|---|---|---|---|---|')" \
    "$got" "表の見出しは設計の6列(要件2-1)"

got=$(row_of "Node.js" '["26.1.0"]' '{"deadline": ["24: 2028-04-30", "22: 2027-04-30"], "eol": ["24: いいえ", "22: いいえ"], "latest_cycle": ["26(LTS ではない)"]}')
check_eq '| Node.js | 24.21.0(docker/frontend/Dockerfile:1)<br>24.16.0(wf/a.yaml:3 ほか2か所)<br>22.1.0(wf/c.yaml:5) | 26.1.0 | 24: 2028-04-30<br>22: 2027-04-30 | 24: いいえ<br>22: いいえ | 26(LTS ではない) |' \
    "$got" "Node.js の複数の宣言を1行にまとめ、同じ版の場所を「ほかNか所」にする(要件1-2・2-1)"

got=$(row_of "Terraform" '"1.16.4"' '{"deadline": "1.16: 未定", "eol": "1.16: いいえ", "latest_cycle": "1.16"}')
check_eq '| Terraform | 1.16.4(docker/terraform/Dockerfile:3)<br>1.9.0(wf/plan.yaml:2 ほか1か所) | 1.16.4 | 1.16: 未定 | 1.16: いいえ | 1.16 |' \
    "$got" "Terraform の複数の宣言を1行にまとめる(要件1-2・2-1)"

got=$(row_of "tflint" '["v0.64.0"]' 'null')
check_eq '| tflint | 読み取れず(missing/Dockerfile)<br>読み取れず(wf/nomatch.txt)<br>読み取れず(wf/a.yaml) | v0.64.0 | 公表なし | 公表なし | 公表なし |' \
    "$got" "読めない場所は「読み取れず」と場所を出し、公表の無い3列は「公表なし」(要件1-5・2-6)"

# 読める場所と読めない場所が混ざるとき
mixed=$(jq -c '.targets[0] | .declarations += [{"files": ["missing/a.yaml"], "pattern": "x(?<version>y)"}]' "$WORK/targets.json")
record=$(inv_read_target "$ROOT" "$mixed" | jq -c '. + {latest: "26.1.0", support: {deadline: "24: 2028-04-30", eol: "24: いいえ", latest_cycle: "26"}}')
got=$(inv_table_row "$record")
check_eq '| Node.js | 24.21.0(docker/frontend/Dockerfile:1)<br>24.16.0(wf/a.yaml:3 ほか2か所)<br>22.1.0(wf/c.yaml:5)<br>読み取れず(missing/a.yaml) | 26.1.0 | 24: 2028-04-30 | 24: いいえ | 26 |' \
    "$got" "読める場所の版に続けて、読めない場所を「読み取れず」で出す(要件2-6)"

# 「公表なし」は設定ファイルの support が null の対象だけに出す
got=$(inv_read_target "$ROOT" "$(target_of "tflint")" | jq -c '.support_published')
check_eq "false" "$got" "support が null の対象は、公表が無いものとして読む"
got=$(inv_read_target "$ROOT" "$(target_of "Node.js")" | jq -c '.support_published')
check_eq "true" "$got" "support がある対象は、公表があるものとして読む"
got=$(row_of "tflint" '"v0.64.0"' '{"deadline": "x", "eol": "y", "latest_cycle": "z"}')
check_eq '| tflint | 読み取れず(missing/Dockerfile)<br>読み取れず(wf/nomatch.txt)<br>読み取れず(wf/a.yaml) | v0.64.0 | 公表なし | 公表なし | 公表なし |' \
    "$got" "support が null の対象は、渡された値があっても3列を「公表なし」にする(要件1-5)"
record=$(inv_read_target "$ROOT" "$(target_of "Node.js")" | jq -c '. + {latest: "26.1.0", support: null}')
inv_table_row "$record" >/dev/null 2>&1
check_rc 1 $? "公表がある対象で3列の値が無い記録は、「公表なし」にせず失敗にする"
record=$(inv_read_target "$ROOT" "$(target_of "Node.js")" | jq -c '. + {latest: "26.1.0", support: {deadline: "a", eol: "b"}}')
inv_table_row "$record" >/dev/null 2>&1
check_rc 1 $? "公表がある対象で3列のどれかが欠けた記録は失敗にする"

# 表に入れる値から | と改行を除く
got=$(row_of "区切り|を含む" '"v1|2\r\nx"' '{"deadline": ["a|b"], "eol": "は\nい", "latest_cycle": "|"}')
check_eq '| 区切りを含む | 1.0evil(wf/pipe.txt:1) | v12x | ab | はい |  |' \
    "$got" "表に入れる値から | と改行を取り除く(表の崩れを防ぐ)"
lines=$(printf '%s\n' "$got" | wc -l | tr -d ' ')
check_eq "1" "$lines" "値に改行があっても表の行は1行"
pipes=$(printf '%s' "$got" | tr -cd '|' | wc -c | tr -d ' ')
check_eq "7" "$pipes" "値に | があっても列は6つのまま"

# 最新のリリースの欄が無い記録は組み立てない(空欄で届けない)。
# support の3列はそろえ、latest だけが無い形にする(別の理由で失敗しないように)
record=$(inv_read_target "$ROOT" "$(target_of "Terraform")" | jq -c '. + {support: {deadline: "a", eol: "b", latest_cycle: "c"}}')
inv_table_row "$record" >/dev/null 2>&1
check_rc 1 $? "最新のリリースの欄が無い記録は失敗にする(公表がある対象)"
record=$(inv_read_target "$ROOT" "$(target_of "tflint")")
inv_table_row "$record" >/dev/null 2>&1
check_rc 1 $? "最新のリリースの欄が無い記録は失敗にする(公表が無い対象)"

# 良し悪しの記号を付けない(食い違いのある Node.js の行と「読み取れず」の行で確かめる)
rows="$(row_of "Node.js" '"26.1.0"' '{"deadline": "24: 2028-04-30", "eol": "24: はい", "latest_cycle": "26"}')
$(row_of "tflint" '"v0.64.0"' 'null')"
if printf '%s' "$rows" | grep -qE '⚠|❌|✅|✔|✖|:warning:|:x:|:white_check_mark:|要対応|古い|OK|NG'; then
    fail "良し悪しの記号や判定の言葉を付けない(要件1-7)"
else
    pass "良し悪しの記号や判定の言葉を付けない(要件1-7)"
fi

# ---------------------------------------------------------------------------
echo "--- 版から系列を取り出す ---"

# 使い方: check_cycle <cycle_pattern> <版> <期待する系列>
check_cycle() {
    local got
    got=$(inv_cycle_of "$1" "$2")
    check_eq "$3" "$got" "系列: $2 → $3"
}
check_cycle '^(?<cycle>[0-9]+)' '24.21.0' '24'
check_cycle '^(?<cycle>[0-9]+)' '21-jdk' '21'
check_cycle '^(?<cycle>[0-9]+)' '27-dind' '27'
check_cycle '^(?<cycle>[0-9]+)' '17.4' '17'
check_cycle '^(?<cycle>[0-9]+\.[0-9]+)' '1.16.4' '1.16'
check_cycle '^(?<cycle>[0-9]+\.[0-9]+)' '8.0' '8.0'
check_cycle '^(?<cycle>[0-9]+\.[0-9]+)' '7.4.11' '7.4'
inv_cycle_of '^(?<cycle>[0-9]+\.[0-9]+)' '21-jdk' >/dev/null 2>&1
check_rc 1 $? "系列を取り出せない版は失敗にする"
inv_cycle_of '(?<cycle>[0-9]' '21' >/dev/null 2>&1
check_rc 1 $? "系列の正規表現の誤りは失敗にする"

# ---------------------------------------------------------------------------
if [ "${INVENTORY_CHECK_REPO:-}" = "1" ]; then
    echo "--- 今のリポジトリの宣言(INVENTORY_CHECK_REPO=1) ---"
    while IFS= read -r target; do
        name=$(jq -r '.name' <<<"$target")
        record=$(inv_read_target "$REPO_ROOT" "$target")
        readable=$(jq '[.used[] | select(.version != null)] | length' <<<"$record")
        if [ "${readable:-0}" -ge 1 ]; then
            pass "${name}: 宣言から版が1件以上読める(要件1-2)"
        else
            fail "${name}: 宣言から版が1件も読めない"
        fi
        unreadable=$(jq -r '[.used[] | select(.version == null) | .file] | join(", ")' <<<"$record")
        check_eq "" "$unreadable" "${name}: 読めない宣言の場所が無い"
        cycle_pattern=$(jq -r '.support.cycle_pattern // empty' <<<"$target")
        if [ -n "$cycle_pattern" ]; then
            while IFS= read -r version; do
                if inv_cycle_of "$cycle_pattern" "$version" >/dev/null 2>&1; then
                    pass "${name}: ${version} から系列を取り出せる"
                else
                    fail "${name}: ${version} から系列を取り出せない"
                fi
            done < <(jq -r '.used[] | select(.version != null) | .version' <<<"$record" | sort -u)
        fi
        # 読めた版を目で確かめるための表示(外部の欄は取得しないため「-」を入れる)
        echo "     $(inv_table_row "$(jq -c '. + {latest: "-", support: {deadline: "-", eol: "-", latest_cycle: "-"}}' <<<"$record")")"
    done < <(jq -c '.targets[]' "$REAL_TARGETS")
else
    echo "--- 今のリポジトリの宣言: INVENTORY_CHECK_REPO=1 のときだけ確かめる(今回は飛ばす) ---"
fi

echo ""
if [ "$FAILED" -ne 0 ]; then
    echo "テストに失敗しました"
    exit 1
fi
echo "すべてのテストに成功しました"
