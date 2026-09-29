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
#   - 外部の取得元(GitHub のリリース、endoflife.date、PyPI、Docker Hub)からの
#     最新版とサポート期限の取得。curl と gh は PATH の先頭の偽物に置き換える
#     (応答の値の変換、複数の系列、タグの選び方、取得の失敗の「取得できず」と
#     表の下の理由、curl の呼び出しに認証ヘッダが無いこと)
#   - 実行の全体。スクリプトを仮のリポジトリに写して実行し、振り返りのIssueの
#     件数、台帳のIssueの探し方と作成、コメントの本文の形(先頭行のメンション)、
#     終了コード(書けたら 0、書けない・設定や環境変数の不足は 2)を確かめる
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

# 使い方: check_has <探す文字列> <対象の文字列> <説明>
check_has() {
    if printf '%s' "$2" | grep -qF -- "$1"; then
        pass "$3"
    else
        fail "$3"
        echo "     含むはず: $1"
        echo "     実際: $2"
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
echo "--- 外部の取得元(偽の curl と gh) ---"

# 偽の curl と gh を PATH の先頭に置く。応答は $STUB_RESP の下のファイルで決める。
#   名前: URL のホストより後ろのパス(? より前)の / を _ にしたもの
#     例 https://eol.invalid/products/nodejs/releases/24 → products_nodejs_releases_24
#     gh api repos/o/r/releases/latest → gh_repos_o_r_releases_latest
#   <名前>.code が状態コード、<名前>.body が本文。ファイルが無いときは 404 を返す
#   (curl は HTML の本文、gh は JSON の本文と標準エラーの「(HTTP 404)」)。
#   状態コード 000 は応答が無い場合で、curl はタイムアウトの終了コード 28 で終わる。
# curl は -w の書式の %{http_code} を状態コードに置き換えて本文の後ろに出す。
# 呼び出しの引数は1回1行で $STUB_CALLS に残す(認証ヘッダが無いことを確かめる)。
mkdir -p "$WORK/bin" "$WORK/resp"
cat >"$WORK/bin/curl" <<'STUB'
#!/usr/bin/env bash
printf 'curl %s\n' "$*" >>"${STUB_CALLS:?}"
url=""
fmt=""
want=""
for a in "$@"; do
    if [ "$want" = "w" ]; then
        fmt="$a"
        want=""
        continue
    fi
    case "$a" in
    -w) want="w" ;;
    http*) url="$a" ;;
    esac
done
path="${url#*://}"
path="${path#*/}"
path="${path%%\?*}"
key=$(printf '%s' "$path" | tr '/' '_')
code=404
body='<!DOCTYPE html><html><head><title>Page not Found</title></head><body><h1>404</h1></body></html>'
if [ -f "${STUB_RESP:?}/${key}.code" ]; then
    code=$(cat "${STUB_RESP}/${key}.code")
    body=$(cat "${STUB_RESP}/${key}.body")
fi
if [ "$code" = "000" ]; then
    echo "curl: (28) Operation timed out after 20000 milliseconds" >&2
    exit 28
fi
printf '%s' "$body"
if [ -n "$fmt" ]; then
    pat='%{http_code}'
    printf '%b' "${fmt//"$pat"/$code}"
fi
STUB
cat >"$WORK/bin/gh" <<'STUB'
#!/usr/bin/env bash
printf 'gh %s\n' "$*" >>"${STUB_CALLS:?}"
if [ "${1:-}" != "api" ]; then
    echo "stub: 想定していない呼び出し: $*" >&2
    exit 1
fi
key="gh_$(printf '%s' "${2:-}" | tr '/' '_')"
code=404
body='{"message":"Not Found","status":"404"}'
if [ -f "${STUB_RESP:?}/${key}.code" ]; then
    code=$(cat "${STUB_RESP}/${key}.code")
    body=$(cat "${STUB_RESP}/${key}.body")
fi
printf '%s\n' "$body"
if [ "$code" != "200" ]; then
    echo "gh: Not Found (HTTP ${code})" >&2
    exit 1
fi
STUB
chmod +x "$WORK/bin/curl" "$WORK/bin/gh"

PATH="$WORK/bin:$PATH"
export STUB_CALLS="$WORK/calls.log" STUB_RESP="$WORK/resp"
export ENDOFLIFE_BASE="https://eol.invalid"
export PYPI_BASE="https://pypi.invalid/pypi"
export DOCKERHUB_BASE="https://hub.invalid/v2"
# curl に渡らないことを確かめるための値
export GH_TOKEN="stub-token-must-not-be-sent"

# 使い方: resp <名前> <状態コード> <本文>
resp() {
    printf '%s' "$2" >"$WORK/resp/$1.code"
    printf '%s' "$3" >"$WORK/resp/$1.body"
}
# 応答と呼び出しの記録を空にする
reset_stub() {
    rm -f "$WORK/resp/"*
    : >"$WORK/calls.log"
}
# 使い方: calls_of <URL の一部>  その文字列を含む curl の呼び出しの回数
calls_of() {
    grep -cF -- "$1" "$WORK/calls.log"
}
# 使い方: collected <対象の JSON>  宣言を読み、外部の取得元に問い合わせた記録を出す
collected() {
    local record
    record=$(inv_read_target "$ROOT" "$1") || return 1
    inv_collect_external "$record" "$1"
}
# 使い方: collected_row <対象の JSON>  上の記録から表の行を出す
collected_row() {
    local record
    record=$(collected "$1") || return 1
    inv_table_row "$record"
}
# 使い方: eol <系列> <isEol> <eolFrom(JSON)> <isLts> <最新の版>  endoflife.date の応答
eol() {
    printf '{"schema_version":"1.2.1","generated_at":"2026-09-29T00:00:00+00:00","result":{"name":"%s","codename":null,"label":"%s","isLts":%s,"isEol":%s,"eolFrom":%s,"isMaintained":true,"latest":{"name":"%s","date":"2026-09-01"},"custom":null}}' \
        "$1" "$1" "$4" "$2" "$3" "$5"
}

# 仮のリポジトリに、取得元ごとの対象の宣言を足す
printf 'checkov==3.2.0\n' >"$ROOT/wf/requirements.txt"
printf 'FROM localstack/localstack:2026.8.3@sha256:2222\n' >"$ROOT/wf/localstack"
printf 'v: 21-jdk\nv: abc\n' >"$ROOT/wf/java.txt"
T_CHECKOV='{"name": "checkov", "declarations": [{"files": ["wf/requirements.txt"], "pattern": "(?m)^checkov==(?<version>[0-9][0-9A-Za-z.]*)"}], "latest": {"type": "pypi", "package": "checkov"}, "support": null}'
LS_PATTERN=$(jq -r '.targets[] | select(.name == "LocalStack") | .latest.tag_pattern' "$REAL_TARGETS")
T_LOCALSTACK=$(jq -n -c --arg p "$LS_PATTERN" \
    '{name: "LocalStack", declarations: [{files: ["wf/localstack"], pattern: "localstack:(?<version>[0-9][^@]*)"}], latest: {type: "dockerhub-tags", repository: "localstack/localstack", tag_pattern: $p}, support: null}')
T_JAVA='{"name": "Java", "declarations": [{"files": ["wf/java.txt"], "pattern": "(?m)^v: (?<version>[^\\n]+)"}], "latest": {"type": "endoflife", "product": "eclipse-temurin"}, "support": {"type": "endoflife", "product": "eclipse-temurin", "cycle_pattern": "^(?<cycle>[0-9]+)"}}'
T_NOVERSION='{"name": "版なし", "declarations": [{"files": ["missing/Dockerfile"], "pattern": "(?<version>x)"}], "latest": {"type": "endoflife", "product": "nodejs"}, "support": {"type": "endoflife", "product": "nodejs", "cycle_pattern": "^(?<cycle>[0-9]+)"}}'
NODE_ROW_USED='24.21.0(docker/frontend/Dockerfile:1)<br>24.16.0(wf/a.yaml:3 ほか2か所)<br>22.1.0(wf/c.yaml:5)'

# --- endoflife.date ---
reset_stub
resp products_nodejs_releases_24 200 "$(eol 24 false '"2028-04-30"' true 24.21.0)"
resp products_nodejs_releases_22 200 "$(eol 22 true '"2027-04-30"' true 22.22.0)"
resp products_nodejs_releases_latest 200 "$(eol 26 false '"2029-04-30"' false 26.10.0)"
record=$(collected "$(target_of "Node.js")")
got=$(inv_table_row "$record")
check_eq "| Node.js | ${NODE_ROW_USED} | 26.10.0 | 24: 2028-04-30<br>22: 2027-04-30 | 24: いいえ<br>22: はい | 26(LTS ではない) |" \
    "$got" "endoflife.date: 使っている系列ごとの期限と期限切れ、最新の系列の latest.name を最新のリリースにする(要件1-3・1-4)"
check_eq "[]" "$(jq -c '.failures' <<<"$record")" "全て取得できたときは、取得できなかった理由が無い"
check_eq "1" "$(calls_of "/products/nodejs/releases/24")" "同じ系列の版が複数あっても、系列ごとに1回だけ問い合わせる"
check_eq "1" "$(calls_of "/products/nodejs/releases/latest")" "最新の系列と最新のリリースは、1回の問い合わせから取る"
check_eq "https://eol.invalid/products/nodejs/releases/latest" \
    "$(grep -oE 'https://eol\.invalid/[^ ]*latest' "$WORK/calls.log")" "接続先を ENDOFLIFE_BASE で差し替えられる"

# 使っている版から系列が複数できる(Terraform の 1.16 と 1.9)。eolFrom が null は「未定」
reset_stub
resp products_terraform_releases_1.16 200 "$(eol 1.16 false null false 1.16.4)"
resp products_terraform_releases_1.9 200 "$(eol 1.9 true '"2025-02-27"' false 1.9.8)"
resp products_terraform_releases_latest 200 "$(eol 1.16 false null false 1.16.4)"
got=$(collected_row "$(target_of "Terraform")")
check_eq '| Terraform | 1.16.4(docker/terraform/Dockerfile:3)<br>1.9.0(wf/plan.yaml:2 ほか1か所) | 1.16.4 | 1.16: 未定<br>1.9: 2025-02-27 | 1.16: いいえ<br>1.9: はい | 1.16(LTS ではない) |' \
    "$got" "系列が複数できたときは系列ごとに問い合わせ、eolFrom が null の期限は「未定」にする(要件1-4)"
check_eq "1" "$(calls_of "/products/terraform/releases/1.9")" "2つ目の系列(1.9)も問い合わせる"

# 最新の系列が LTS なら「(LTS ではない)」を付けない
reset_stub
resp products_nodejs_releases_24 200 "$(eol 24 false '"2028-04-30"' true 24.21.0)"
resp products_nodejs_releases_22 200 "$(eol 22 false '"2027-04-30"' true 22.22.0)"
resp products_nodejs_releases_latest 200 "$(eol 24 false '"2028-04-30"' true 24.21.0)"
got=$(collected "$(target_of "Node.js")" | jq -r '.support.latest_cycle | if type == "array" then join(",") else . end')
check_eq "24" "$got" "LTS の最新の系列には「(LTS ではない)」を付けない"

# --- GitHub のリリース ---
reset_stub
resp gh_repos_terraform-linters_tflint_releases_latest 200 '{"tag_name":"v0.64.0","name":"v0.64.0","published_at":"2026-09-01T00:00:00Z"}'
got=$(collected_row "$(target_of "tflint")")
check_eq '| tflint | 読み取れず(missing/Dockerfile)<br>読み取れず(wf/nomatch.txt)<br>読み取れず(wf/a.yaml) | v0.64.0 | 公表なし | 公表なし | 公表なし |' \
    "$got" "GitHub のリリース: gh api の releases/latest の tag_name を最新のリリースにする(要件1-3)"
check_eq "1" "$(grep -cxF 'gh api repos/terraform-linters/tflint/releases/latest' "$WORK/calls.log")" "GitHub のリリースは gh api で問い合わせる"
check_eq "0" "$(grep -c '^curl' "$WORK/calls.log")" "サポート期限の公表が無い対象では endoflife.date に問い合わせない"

# --- PyPI ---
reset_stub
resp pypi_checkov_json 200 '{"info":{"name":"checkov","version":"3.3.20"},"releases":{}}'
got=$(collected_row "$T_CHECKOV")
check_eq '| checkov | 3.2.0(wf/requirements.txt:1) | 3.3.20 | 公表なし | 公表なし | 公表なし |' \
    "$got" "PyPI: info.version を最新のリリースにする(要件1-3)"
check_eq "1" "$(calls_of "https://pypi.invalid/pypi/checkov/json")" "接続先を PYPI_BASE で差し替えられる"

# --- Docker Hub ---
reset_stub
resp v2_namespaces_localstack_repositories_localstack_tags 200 \
    '{"count":12,"next":null,"previous":null,"results":[{"name":"latest"},{"name":"2026.11.0-arm64"},{"name":"2026.11.0-amd64"},{"name":"2026.11"},{"name":"2026.10.0"},{"name":"2026.10"},{"name":"2026.9.1"},{"name":"2026.9.1-arm64"},{"name":"2026.09.1"},{"name":"stable"},{"name":"2026.8.10"},{"name":"2026.11.0-bigdata"}]}'
got=$(collected_row "$T_LOCALSTACK")
check_eq '| LocalStack | 2026.8.3(wf/localstack:1) | 2026.10.0 | 公表なし | 公表なし | 公表なし |' \
    "$got" "Docker Hub: tag_pattern に一致するタグの最大の版を最新にする(-arm64 などと別名を除き、版として比べる)"
check_eq "1" "$(calls_of "https://hub.invalid/v2/namespaces/localstack/repositories/localstack/tags?page_size=100&ordering=last_updated")" \
    "Docker Hub のタグは DOCKERHUB_BASE の namespaces/.../tags に page_size=100 と ordering=last_updated で問い合わせる"
# 別名(月の先頭が0)は、版として大きくても選ばない
reset_stub
resp v2_namespaces_localstack_repositories_localstack_tags 200 \
    '{"results":[{"name":"2026.08.4"},{"name":"2026.08.4-arm64"},{"name":"2026.8.3"},{"name":"2026.8.3-arm64"},{"name":"latest"}]}'
got=$(collected "$T_LOCALSTACK" | jq -r '.latest')
check_eq "2026.8.3" "$got" "Docker Hub: 月の先頭が0の別名(2026.08.4)は選ばない"

# --- 取得の失敗 ---
# 使っている系列の1つが 500: その系列だけ「取得できず」
reset_stub
resp products_nodejs_releases_24 200 "$(eol 24 false '"2028-04-30"' true 24.21.0)"
resp products_nodejs_releases_22 500 '{"error":"internal"}'
resp products_nodejs_releases_latest 200 "$(eol 26 false '"2029-04-30"' false 26.10.0)"
record=$(collected "$(target_of "Node.js")")
got=$(inv_table_row "$record")
check_eq "| Node.js | ${NODE_ROW_USED} | 26.10.0 | 24: 2028-04-30<br>22: 取得できず | 24: いいえ<br>22: 取得できず | 26(LTS ではない) |" \
    "$got" "500: 失敗した系列の欄だけを「取得できず」にする(要件2-5)"
check_eq '["Node.js の 22 系列のサポート期限と期限切れ: HTTP 500"]' "$(jq -c '.failures' <<<"$record")" \
    "500: 理由に対象・欄・状態コードを書く"

# 最新の系列が 404(本文は HTML): 最新のリリースと最新の系列が「取得できず」
reset_stub
resp products_nodejs_releases_24 200 "$(eol 24 false '"2028-04-30"' true 24.21.0)"
resp products_nodejs_releases_22 200 "$(eol 22 false '"2027-04-30"' true 22.22.0)"
record=$(collected "$(target_of "Node.js")")
got=$(inv_table_row "$record")
check_eq "| Node.js | ${NODE_ROW_USED} | 取得できず | 24: 2028-04-30<br>22: 2027-04-30 | 24: いいえ<br>22: いいえ | 取得できず |" \
    "$got" "404(HTML の本文): 最新のリリースと最新の系列だけを「取得できず」にする"
check_eq '["Node.js の最新のリリース: HTTP 404","Node.js の最新の系列: HTTP 404"]' "$(jq -c '.failures' <<<"$record")" \
    "404: 最新のリリースと最新の系列の理由を1つずつ書く"

# 429
reset_stub
resp pypi_checkov_json 429 '{"message":"Too Many Requests"}'
record=$(collected "$T_CHECKOV")
check_eq '| checkov | 3.2.0(wf/requirements.txt:1) | 取得できず | 公表なし | 公表なし | 公表なし |' \
    "$(inv_table_row "$record")" "429: 最新のリリースを「取得できず」にする"
check_eq '["checkov の最新のリリース: HTTP 429"]' "$(jq -c '.failures' <<<"$record")" "429: 理由に状態コードを書く"

# タイムアウト(応答が無い)
reset_stub
resp pypi_checkov_json 000 ''
record=$(collected "$T_CHECKOV")
check_eq "取得できず" "$(jq -r '.latest' <<<"$record")" "タイムアウト: 最新のリリースを「取得できず」にする"
check_has "curl の終了コード 28" "$(jq -r '.failures[0]' <<<"$record")" "タイムアウト: 理由に curl の終了コードを書く"

# 不正な JSON(200 でも読めない)
reset_stub
resp pypi_checkov_json 200 '{"info": {"version": '
record=$(collected "$T_CHECKOV")
check_eq "取得できず" "$(jq -r '.latest' <<<"$record")" "不正な JSON: 最新のリリースを「取得できず」にする"
check_eq '["checkov の最新のリリース: 形式が想定と違う(JSON として読めない)"]' "$(jq -c '.failures' <<<"$record")" \
    "不正な JSON: 理由を「形式が想定と違う」にする"

# 200 で HTML の本文
reset_stub
resp products_nodejs_releases_24 200 '<!DOCTYPE html><html><body>maintenance</body></html>'
resp products_nodejs_releases_22 200 "$(eol 22 false '"2027-04-30"' true 22.22.0)"
resp products_nodejs_releases_latest 200 "$(eol 26 false '"2029-04-30"' false 26.10.0)"
record=$(collected "$(target_of "Node.js")")
check_eq "24: 取得できず,22: 2027-04-30" "$(jq -r '.support.deadline | join(",")' <<<"$record")" \
    "200 で HTML の本文: その系列だけを「取得できず」にする"
check_has "JSON として読めない" "$(jq -r '.failures[0]' <<<"$record")" "200 で HTML の本文: 理由を書く"

# 期待のキーが無い
reset_stub
resp pypi_checkov_json 200 '{"info":{"name":"checkov"}}'
record=$(collected "$T_CHECKOV")
check_eq "取得できず" "$(jq -r '.latest' <<<"$record")" "キーが無い(PyPI の info.version): 「取得できず」にする"
check_has "形式が想定と違う" "$(jq -r '.failures[0]' <<<"$record")" "キーが無い: 理由を「形式が想定と違う」にする"

reset_stub
resp products_nodejs_releases_24 200 '{"result":{"name":"24","isLts":true,"eolFrom":"2028-04-30","latest":{"name":"24.21.0"}}}'
resp products_nodejs_releases_22 200 "$(eol 22 false '"2027-04-30"' true 22.22.0)"
resp products_nodejs_releases_latest 200 '{"result":{"name":"26","isLts":false,"isEol":false,"eolFrom":null}}'
record=$(collected "$(target_of "Node.js")")
got=$(inv_table_row "$record")
check_eq "| Node.js | ${NODE_ROW_USED} | 取得できず | 24: 取得できず<br>22: 2027-04-30 | 24: 取得できず<br>22: いいえ | 26(LTS ではない) |" \
    "$got" "キーが無い(endoflife.date の isEol と latest.name): その欄だけを「取得できず」にする"
check_eq "2" "$(jq '.failures | length' <<<"$record")" "キーが無い: 欠けた欄ごとに理由を書く"

reset_stub
resp products_nodejs_releases_24 200 "$(eol 24 false '"2028-04-30"' true 24.21.0)"
resp products_nodejs_releases_22 200 "$(eol 22 false '"2027-04-30"' true 22.22.0)"
resp products_nodejs_releases_latest 200 '{"result":{"name":"26","latest":{"name":"26.10.0"}}}'
record=$(collected "$(target_of "Node.js")")
check_eq "26.10.0" "$(jq -r '.latest' <<<"$record")" "最新の系列の isLts が無くても、最新のリリースは出す"
check_eq "取得できず" "$(jq -r '.support.latest_cycle | if type == "array" then join(",") else . end' <<<"$record")" \
    "キーが無い(endoflife.date の isLts): 最新の系列を「取得できず」にする"

# GitHub のリリースの失敗
reset_stub
record=$(collected "$(target_of "tflint")")
check_eq "取得できず" "$(jq -r '.latest' <<<"$record")" "GitHub のリリースが 404: 「取得できず」にする"
check_eq '["tflint の最新のリリース: HTTP 404"]' "$(jq -c '.failures' <<<"$record")" "GitHub のリリースが 404: 理由に状態コードを書く"
reset_stub
resp gh_repos_terraform-linters_tflint_releases_latest 200 '{"name":"v0.64.0"}'
record=$(collected "$(target_of "tflint")")
check_eq "取得できず" "$(jq -r '.latest' <<<"$record")" "GitHub のリリースに tag_name が無い: 「取得できず」にする"
check_has "形式が想定と違う" "$(jq -r '.failures[0]' <<<"$record")" "GitHub のリリースに tag_name が無い: 理由を書く"

# Docker Hub の失敗
reset_stub
resp v2_namespaces_localstack_repositories_localstack_tags 200 '{"results":[{"name":"latest"},{"name":"2026.08.4"},{"name":"2026.8.3-arm64"}]}'
record=$(collected "$T_LOCALSTACK")
check_eq "取得できず" "$(jq -r '.latest' <<<"$record")" "Docker Hub で一致するタグが無い: 「取得できず」にする"
check_has "tag_pattern に一致するタグが無い" "$(jq -r '.failures[0]' <<<"$record")" "Docker Hub で一致するタグが無い: 理由を書く"
reset_stub
resp v2_namespaces_localstack_repositories_localstack_tags 200 '{"message":"ok"}'
record=$(collected "$T_LOCALSTACK")
check_eq "取得できず" "$(jq -r '.latest' <<<"$record")" "Docker Hub の応答に results が無い: 「取得できず」にする"
check_has "形式が想定と違う" "$(jq -r '.failures[0]' <<<"$record")" "Docker Hub の応答に results が無い: 理由を書く"

# 系列を決められない版
reset_stub
resp products_eclipse-temurin_releases_21 200 "$(eol 21 false '"2029-12-31"' true 21.0.8+9)"
resp products_eclipse-temurin_releases_latest 200 "$(eol 25 false '"2031-09-30"' true 25.0.1+8)"
record=$(collected "$T_JAVA")
got=$(inv_table_row "$record")
check_eq '| Java | 21-jdk(wf/java.txt:1)<br>abc(wf/java.txt:2) | 25.0.1+8 | 21: 2029-12-31<br>abc: 取得できず | 21: いいえ<br>abc: 取得できず | 25 |' \
    "$got" "系列を取り出せない版は、その版の欄だけを「取得できず」にする"
check_eq '["Java のサポート期限と期限切れ: 版 abc から系列を取り出せない"]' "$(jq -c '.failures' <<<"$record")" \
    "系列を取り出せない版: 理由を書く"
reset_stub
resp products_nodejs_releases_latest 200 "$(eol 26 false '"2029-04-30"' false 26.10.0)"
record=$(collected "$T_NOVERSION")
got=$(inv_table_row "$record")
check_eq '| 版なし | 読み取れず(missing/Dockerfile) | 26.10.0 | 取得できず | 取得できず | 26(LTS ではない) |' \
    "$got" "使っている版が1つも読めないときは、期限と期限切れを「取得できず」にする"
check_eq "1" "$(jq '.failures | length' <<<"$record")" "使っている版が1つも読めない: 理由を書く"

# 外部の値の | と改行は表に入れる前に取り除く
reset_stub
resp pypi_checkov_json 200 '{"info":{"version":"3.3|<b>x</b>\ny"}}'
got=$(collected_row "$T_CHECKOV")
check_eq '| checkov | 3.2.0(wf/requirements.txt:1) | 3.3<b>x</b>y | 公表なし | 公表なし | 公表なし |' \
    "$got" "外部の値から | と改行を取り除いて表に入れる"

# --- 表の組み立て(全ての対象) ---
# Node.js は取得でき、他の対象は取得の失敗(500・429・不正な JSON・404)を含む
reset_stub
resp products_nodejs_releases_24 200 "$(eol 24 false '"2028-04-30"' true 24.21.0)"
resp products_nodejs_releases_22 200 "$(eol 22 false '"2027-04-30"' true 22.22.0)"
resp products_nodejs_releases_latest 200 "$(eol 26 false '"2029-04-30"' false 26.10.0)"
resp products_terraform_releases_1.16 500 'error'
resp products_terraform_releases_latest 429 'slow down'
resp gh_repos_terraform-linters_tflint-ruleset-aws_releases_latest 200 '{"tag_name":"v0.49.0"}'
resp pypi_x_json 200 'not json'
resp v2_namespaces_a_repositories_b_tags 200 '{"results":[{"name":"1"},{"name":"10"},{"name":"9"},{"name":"x"}]}'
report=$(inv_build_table "$ROOT" "$WORK/targets.json")
check_rc 0 $? "取得の失敗があっても表を最後まで作る(要件2-5・5-3)"
check_eq "9" "$(printf '%s\n' "$report" | grep -c '^|')" "表は見出しの2行と、対象ごとの1行(7行)"
check_eq "$(inv_table_header)" "$(printf '%s\n' "$report" | head -2)" "表は見出しから始まる"
check_eq "| Node.js | ${NODE_ROW_USED} | 26.10.0 | 24: 2028-04-30<br>22: 2027-04-30 | 24: いいえ<br>22: いいえ | 26(LTS ではない) |" \
    "$(printf '%s\n' "$report" | grep -F '| Node.js |')" "他の対象の失敗があっても、取得できた対象の行は欠けない"
check_eq '| ルールセット | 0.44.0(tf/.tflint.hcl:8) | v0.49.0 | 公表なし | 公表なし | 公表なし |' \
    "$(printf '%s\n' "$report" | grep -F '| ルールセット |')" "失敗した対象の後の対象も取得する"
check_eq '| 区切りを含む | 1.0evil(wf/pipe.txt:1) | 10 | 1: 取得できず | 1: 取得できず | 取得できず |' \
    "$(printf '%s\n' "$report" | grep -F '| 区切りを含む |')" "取得できなかった欄は「取得できず」"
check_eq "$(printf '\n取得できなかった欄の理由:')" "$(printf '%s\n' "$report" | sed -n '10,11p')" \
    "表の下に空行を置き、取得できなかった欄の理由の見出しを置く"
check_has "- Terraform の 1.16 系列のサポート期限と期限切れ: HTTP 500" "$report" "表の下の理由: 500"
check_has "- Terraform の最新の系列: HTTP 429" "$report" "表の下の理由: 429"
check_has "- tflint の最新のリリース: HTTP 404" "$report" "表の下の理由: GitHub の 404"
check_has "- 正規表現の誤り の最新のリリース: 形式が想定と違う(JSON として読めない)" "$report" "表の下の理由: 不正な JSON"
check_has "- 区切りを含む の 1 系列のサポート期限と期限切れ: HTTP 404" "$report" "表の下の理由から | を取り除く"
bad=$(printf '%s\n' "$report" | sed -n '/^取得できなかった欄の理由:$/,$p' | tail -n +2 | grep -cv '^- ')
check_eq "0" "$bad" "理由は1件1行の箇条書き"

# 全て取得できたときは、理由の見出しを出さない
reset_stub
resp gh_repos_terraform-linters_tflint_releases_latest 200 '{"tag_name":"v0.64.0"}'
jq '{targets: [.targets[] | select(.name == "tflint")]}' "$WORK/targets.json" >"$WORK/one.json"
report=$(inv_build_table "$ROOT" "$WORK/one.json")
check_eq "3" "$(printf '%s\n' "$report" | grep -c .)" "全て取得できたときは表だけを出す"

# --- 認証ヘッダ ---
# ここまでの全ての curl の呼び出しを記録し直して確かめる(上の表の組み立てで全種類を通る)
reset_stub
inv_build_table "$ROOT" "$WORK/targets.json" >/dev/null 2>&1
inv_collect_external "$(inv_read_target "$ROOT" "$T_CHECKOV")" "$T_CHECKOV" >/dev/null 2>&1
inv_collect_external "$(inv_read_target "$ROOT" "$T_LOCALSTACK")" "$T_LOCALSTACK" >/dev/null 2>&1
curl_calls=$(grep '^curl ' "$WORK/calls.log")
for host in eol pypi hub; do
    if printf '%s\n' "$curl_calls" | grep -qF " https://${host}.invalid/"; then
        pass "curl の呼び出しが記録されている(${host}.invalid)"
    else
        fail "curl の呼び出しが記録されている(${host}.invalid)"
    fi
done
if printf '%s\n' "$curl_calls" | grep -qiE 'authorization|(^| )(-H|--header|-u|--user|--oauth2-bearer|-b|--cookie)( |$)|stub-token'; then
    fail "curl の呼び出しに認証ヘッダや認証情報を付けない(要件6-1)"
    printf '%s\n' "$curl_calls" | sed 's/^/     /'
else
    pass "curl の呼び出しに認証ヘッダや認証情報を付けない(要件6-1)"
fi
check_eq "0" "$(printf '%s\n' "$curl_calls" | awk '!/ -sS / || !/ --max-time 20 /' | grep -c .)" "curl は全て -sS --max-time 20 で呼ぶ"
check_eq "0" "$(printf '%s\n' "$curl_calls" | grep -cvE ' https://(eol|pypi|hub)\.invalid/')" "curl の接続先は差し替えた取得元だけ"

# ---------------------------------------------------------------------------
echo "--- 実行の全体(台帳へのコメントと終了コード) ---"

# スクリプトとライブラリを仮のリポジトリの .github/scripts に写し、別のディレクトリ
# から実行する(スクリプトは自分の置き場所の2つ上をリポジトリのルートとして読む)。
LIB="$(dirname "$SCRIPT")/lib-ledger-issue.sh"
if [ ! -f "$LIB" ]; then
    echo "FAIL: ${LIB} がありません"
    exit 1
fi
mkdir -p "$ROOT/.github/scripts" "$WORK/mainbin" "$WORK/posted"
cp "$SCRIPT" "$LIB" "$ROOT/.github/scripts/" || exit 1
MAIN_SCRIPT="$ROOT/.github/scripts/collect-inventory.sh"
LEDGER_TITLE="棚卸し台帳: 版とサポート期限"
RUN_URL="https://github.example/owner/repo/actions/runs/12345"
jq '{targets: [.targets[] | select(.name == "Node.js" or .name == "tflint")]}' "$WORK/targets.json" >"$WORK/main-targets.json"

# 実行の全体で使う偽の gh。上の偽の gh と同じ応答のファイルを使い、次を足す。
#   api のパスは、オプションとその値を飛ばした最初の引数。名前は / ? & = を _ にしたもの
#     例 gh api --paginate "repos/o/r/issues?state=all&per_page=100"
#        → gh_repos_o_r_issues_state_all_per_page_100
#   issue create / issue comment / label create は成功し、--body-file の本文を
#   $STUB_POSTED の下に create.txt / comment.txt として写す。issue create は
#   作ったIssueのURL(番号 100)を出す。$STUB_FAIL_ON に create / comment / label を
#   入れると、その操作だけ失敗させる。
cat >"$WORK/mainbin/gh" <<'STUB'
#!/usr/bin/env bash
printf 'gh %s\n' "$*" >>"${STUB_CALLS:?}"
kind=""
case "${1:-} ${2:-}" in
"issue create") kind=create ;;
"issue comment") kind=comment ;;
"label create") kind=label ;;
esac
if [ -n "$kind" ]; then
    body_file=""
    prev=""
    for a in "$@"; do
        [ "$prev" = "--body-file" ] && body_file="$a"
        prev="$a"
    done
    if [ -n "$body_file" ]; then
        cp "$body_file" "${STUB_POSTED:?}/${kind}.txt" || exit 1
    fi
    if [ "${STUB_FAIL_ON:-}" = "$kind" ]; then
        echo "gh: 失敗をシミュレート" >&2
        exit 1
    fi
    if [ "$kind" = "create" ]; then
        echo "https://github.com/owner/repo/issues/100"
    fi
    exit 0
fi
if [ "${1:-}" != "api" ]; then
    echo "stub: 想定していない呼び出し: $*" >&2
    exit 1
fi
shift
path=""
skip=""
for a in "$@"; do
    if [ -n "$skip" ]; then
        skip=""
        continue
    fi
    case "$a" in
    -X | -f | -F | -H | --jq) skip=1 ;;
    -*) ;;
    *) [ -n "$path" ] || path="$a" ;;
    esac
done
key="gh_$(printf '%s' "$path" | tr '/?&=' '____')"
code=404
body='{"message":"Not Found","status":"404"}'
if [ -f "${STUB_RESP:?}/${key}.code" ]; then
    code=$(cat "${STUB_RESP}/${key}.code")
    body=$(cat "${STUB_RESP}/${key}.body")
fi
printf '%s\n' "$body"
if [ "$code" != "200" ]; then
    echo "gh: Not Found (HTTP ${code})" >&2
    exit 1
fi
STUB
chmod +x "$WORK/mainbin/gh"

# 応答の名前
R_LEDGER_LIST="gh_repos_owner_repo_issues_state_all_per_page_100"
R_RETRO_LABEL="gh_repos_owner_repo_labels_retrospective"
R_RETRO_LIST="gh_repos_owner_repo_issues_labels_retrospective_state_all_per_page_100"

# 呼び出しの記録と写した本文を空にし、台帳のIssue(#7)がある状態にする。
# 外部の取得元と振り返りのIssueの応答は置かない(置かなければ 404)
reset_main() {
    reset_stub
    rm -f "$WORK/posted/"*
    unset STUB_FAIL_ON
    MAIN_UNSET=""
    resp "$R_LEDGER_LIST" 200 "[{\"number\": 3, \"title\": \"別のIssue\"}, {\"number\": 7, \"title\": \"${LEDGER_TITLE}\"}]"
    resp gh_repos_owner_repo_issues_7_assignees 200 '{"number":7,"assignees":[{"login":"owner"}]}'
    resp gh_repos_owner_repo_issues_100_assignees 200 '{"number":100,"assignees":[{"login":"owner"}]}'
}
# 外部の取得元が全て答える状態にする
ok_externals() {
    resp products_nodejs_releases_24 200 "$(eol 24 false '"2028-04-30"' true 24.21.0)"
    resp products_nodejs_releases_22 200 "$(eol 22 false '"2027-04-30"' true 22.22.0)"
    resp products_nodejs_releases_latest 200 "$(eol 26 false '"2029-04-30"' false 26.10.0)"
    resp gh_repos_terraform-linters_tflint_releases_latest 200 '{"tag_name":"v0.64.0"}'
}

# 使い方: run_main <引数...>
# 写したスクリプトを、必須の環境変数をそろえて実行する。MAIN_UNSET に名前を
# 入れると、その環境変数だけを渡さない(CI の実行環境の値も消してから渡す)。
MAIN_EXIT=0
MAIN_UNSET=""
run_main() {
    local v
    local -a envs=()
    for v in "GH_TOKEN=${GH_TOKEN}" "GITHUB_REPOSITORY=owner/repo" "GITHUB_REPOSITORY_OWNER=owner" \
        "GITHUB_SERVER_URL=https://github.example" "GITHUB_RUN_ID=12345"; do
        [ "${v%%=*}" = "$MAIN_UNSET" ] || envs+=("$v")
    done
    (cd "$WORK" && env -u GH_TOKEN -u GITHUB_REPOSITORY -u GITHUB_REPOSITORY_OWNER \
        -u GITHUB_SERVER_URL -u GITHUB_RUN_ID "${envs[@]}" \
        PATH="$WORK/mainbin:$PATH" STUB_POSTED="$WORK/posted" \
        bash "$MAIN_SCRIPT" "$@") >"$WORK/main.out" 2>"$WORK/main.err"
    MAIN_EXIT=$?
}
# 使い方: gh_calls <正規表現>  その正規表現に一致する gh の呼び出しの回数
gh_calls() {
    grep -cE -- "$1" "$WORK/calls.log"
}
# 使い方: line_of <探す文字列> <ファイル>  最初に一致した行の番号(無ければ 0)
line_of() {
    local n
    n=$(grep -nF -- "$1" "$2" | head -n 1 | cut -d: -f1)
    printf '%s' "${n:-0}"
}
# 使い方: line_before <行の番号> <ファイル>  その前の行(前の行が無ければ「(前の行が無い)」)
line_before() {
    if [ "$1" -le 1 ]; then
        printf '(前の行が無い)'
        return
    fi
    sed -n "$(($1 - 1))p" "$2"
}
# 台帳の操作と読み取り以外の gh の呼び出しの回数(要件6-3)
other_gh_calls() {
    grep '^gh ' "$WORK/calls.log" |
        grep -cvE '^gh (api (repos/[^ ]+/releases/latest|repos/owner/repo/labels/retrospective|--paginate repos/owner/repo/issues\?[^ ]+|-X POST repos/owner/repo/issues/[0-9]+/assignees -f assignees\[\]=owner)|issue create --repo owner/repo |issue comment [0-9]+ --repo owner/repo |label create audit --repo owner/repo)'
}

# --- 台帳があり、振り返りのラベルがあり、PR が混ざる ---
reset_main
ok_externals
resp "$R_RETRO_LABEL" 200 '{"name":"retrospective"}'
resp "$R_RETRO_LIST" 200 '[{"number":1,"state":"open"},{"number":2,"state":"closed"},{"number":3,"state":"open","pull_request":{}}]
[{"number":4,"state":"closed"},{"number":5,"state":"open","pull_request":{}},{"number":6,"state":"open"}]'
run_main "$WORK/main-targets.json"
check_rc 0 "$MAIN_EXIT" "台帳にコメントを書けたら終了コード 0(要件2-8)"
check_eq "1" "$(gh_calls '^gh issue comment 7 ')" "既存の台帳のIssue(#7)に1回コメントする(要件2-2)"
check_eq "0" "$(gh_calls '^gh (issue create|label create)')" "台帳があるときは作らない"
check_eq "1" "$(gh_calls '^gh api -X POST repos/owner/repo/issues/7/assignees ')" "所有者を台帳の担当者に割り当てる(要件2-3)"
COMMENT="$WORK/posted/comment.txt"
first=$(sed -n 1p "$COMMENT" 2>/dev/null)
case "$first" in
"@owner "*) pass "コメントの先頭行で所有者にメンションする(要件2-3)" ;;
*) fail "コメントの先頭行で所有者にメンションする(要件2-3) 実際: ${first}" ;;
esac
case "$first" in
"@owner |"* | "@owner " | "") fail "コメントの先頭行は表ではなく1行の説明にする(実際: ${first})" ;;
*) pass "コメントの先頭行は表ではなく1行の説明にする" ;;
esac
check_eq "" "$(sed -n 2p "$COMMENT" 2>/dev/null)" "説明の次は空行"
check_eq "$(inv_table_header)" "$(sed -n 3,4p "$COMMENT" 2>/dev/null)" "空行の次から表を置く(要件2-1)"
check_eq "| Node.js | ${NODE_ROW_USED} | 26.10.0 | 24: 2028-04-30<br>22: 2027-04-30 | 24: いいえ<br>22: いいえ | 26(LTS ではない) |" \
    "$(sed -n 5p "$COMMENT" 2>/dev/null)" "表の行は設定ファイルの対象の順"
check_eq "4" "$(grep -c '^|' "$COMMENT" 2>/dev/null)" "表は見出しの2行と対象ごとの1行"
check_eq "0" "$(grep -c '^取得できなかった欄の理由:' "$COMMENT" 2>/dev/null)" "全て取得できたときは理由の見出しを出さない"
check_has "振り返りのIssue: 全4件(未完了2件)" "$(cat "$COMMENT" 2>/dev/null)" \
    "振り返りのIssueの件数は PR を除き、ページをまたいで全件と未完了を数える(要件1-6)"
check_has "$RUN_URL" "$(cat "$COMMENT" 2>/dev/null)" "コメントに実行へのリンクを載せる"
table_end=$(grep -n '^|' "$COMMENT" 2>/dev/null | tail -n 1 | cut -d: -f1)
retro_at=$(line_of "振り返りのIssue:" "$COMMENT")
link_at=$(line_of "$RUN_URL" "$COMMENT")
if [ "${table_end:-0}" -gt 0 ] && [ "$retro_at" -gt "$((table_end + 1))" ] && [ "$link_at" -gt "$retro_at" ]; then
    pass "表の下に空行を置いてから振り返りの件数、その後に実行へのリンクを置く"
else
    fail "表の下に空行を置いてから振り返りの件数、その後に実行へのリンクを置く(表の終わり ${table_end:-なし} / 振り返り ${retro_at} / リンク ${link_at})"
fi
check_eq "" "$(line_before "$retro_at" "$COMMENT")" "表と振り返りの件数の間に空行を置く"
check_eq "" "$(line_before "$link_at" "$COMMENT")" "振り返りの件数と実行へのリンクの間に空行を置く(1つの段落にしない)"
check_eq "0" "$(other_gh_calls)" "gh の呼び出しは読み取りと台帳の操作だけ(要件6-3)"
check_eq "0" "$(grep '^curl ' "$WORK/calls.log" | grep -c 'stub-token')" "実行の全体でも curl に認証情報を渡さない(要件6-1)"

# --- 振り返りのラベルが無い ---
reset_main
ok_externals
run_main "$WORK/main-targets.json"
check_rc 0 "$MAIN_EXIT" "振り返りのラベルが無くても終了コード 0"
check_has "振り返りのIssue: 0件(retrospective ラベルが存在しない)" "$(cat "$WORK/posted/comment.txt" 2>/dev/null)" \
    "振り返りのラベルが無いときは0件とし、ラベルが無いことを書く(要件1-6)"
check_eq "0" "$(gh_calls 'labels=retrospective')" "ラベルが無いときは Issue の一覧を問い合わせない"

# --- 振り返りの件数を取れない(ラベルの確認と一覧の失敗) ---
reset_main
ok_externals
resp "$R_RETRO_LABEL" 500 '{"message":"Server Error"}'
run_main "$WORK/main-targets.json"
check_rc 0 "$MAIN_EXIT" "振り返りのラベルを確かめられなくても終了コード 0"
check_has "振り返りのIssue: 取得できず(HTTP 500)" "$(cat "$WORK/posted/comment.txt" 2>/dev/null)" \
    "振り返りのラベルを確かめられないときは「取得できず」と理由を書く(0件にしない)"
reset_main
ok_externals
resp "$R_RETRO_LABEL" 200 '{"name":"retrospective"}'
resp "$R_RETRO_LIST" 502 '{"message":"Bad Gateway"}'
run_main "$WORK/main-targets.json"
check_rc 0 "$MAIN_EXIT" "振り返りのIssueの一覧を取れなくても終了コード 0"
check_has "振り返りのIssue: 取得できず(HTTP 502)" "$(cat "$WORK/posted/comment.txt" 2>/dev/null)" \
    "振り返りのIssueの一覧を取れないときは「取得できず」と理由を書く"
reset_main
ok_externals
resp "$R_RETRO_LABEL" 200 '{"name":"retrospective"}'
resp "$R_RETRO_LIST" 200 '{"message":"not a list"}'
run_main "$WORK/main-targets.json"
check_has "振り返りのIssue: 取得できず(形式が想定と違う" "$(cat "$WORK/posted/comment.txt" 2>/dev/null)" \
    "振り返りのIssueの一覧が配列でないときは「取得できず」と理由を書く"

# --- 台帳のIssueが無い ---
reset_main
ok_externals
resp "$R_LEDGER_LIST" 200 "[{\"number\": 3, \"title\": \"別のIssue\"}, {\"number\": 4, \"title\": \"${LEDGER_TITLE}(旧)\"}, {\"number\": 5, \"title\": \"${LEDGER_TITLE}\", \"pull_request\": {}}]"
run_main "$WORK/main-targets.json"
check_rc 0 "$MAIN_EXIT" "台帳を作ってコメントできたら終了コード 0"
check_eq "1" "$(gh_calls "^gh issue create --repo owner/repo --title ${LEDGER_TITLE} --label audit --body-file ")" \
    "台帳が無いときは決まったタイトルとラベル audit で作る(要件2-4)"
check_eq "1" "$(gh_calls '^gh label create audit ')" "台帳を作るときはラベル audit を用意する"
check_has "audit-inventory.yaml がコメントで表を届ける" "$(cat "$WORK/posted/create.txt" 2>/dev/null)" \
    "台帳の本文に、コメントで表が届くことと人が編集しないことを書く"
check_has "人が編集しない" "$(cat "$WORK/posted/create.txt" 2>/dev/null)" "台帳の本文に、人が編集しないことを書く"
check_eq "1" "$(gh_calls '^gh issue comment 100 ')" "作った台帳のIssue(#100)にコメントする"
check_eq "0" "$(gh_calls '^gh issue comment (3|4|5) ')" "タイトルが違うIssueと PR にはコメントしない(要件6-4)"
check_eq "0" "$(other_gh_calls)" "台帳を作るときも、gh の呼び出しは読み取りと台帳の操作だけ(要件6-3)"

# --- 外部の取得元が全て失敗する ---
reset_main
run_main "$WORK/main-targets.json"
check_rc 0 "$MAIN_EXIT" "外部の取得元が全て失敗しても、台帳に書けたら終了コード 0(要件2-8)"
COMMENT="$WORK/posted/comment.txt"
check_eq "1" "$(gh_calls '^gh issue comment 7 ')" "外部の取得元が全て失敗してもコメントする"
check_has "| Node.js | ${NODE_ROW_USED} | 取得できず | 24: 取得できず<br>22: 取得できず | 24: 取得できず<br>22: 取得できず | 取得できず |" \
    "$(cat "$COMMENT" 2>/dev/null)" "取得できなかった欄は「取得できず」で届ける(要件2-5)"
reasons_at=$(line_of "取得できなかった欄の理由:" "$COMMENT")
retro_at=$(line_of "振り返りのIssue:" "$COMMENT")
link_at=$(line_of "$RUN_URL" "$COMMENT")
if [ "$reasons_at" -gt 4 ] && [ "$retro_at" -gt "$reasons_at" ] && [ "$link_at" -gt "$retro_at" ]; then
    pass "表の下に、取得できなかった欄の理由、振り返りの件数、実行へのリンクの順に置く"
else
    fail "表の下に、取得できなかった欄の理由、振り返りの件数、実行へのリンクの順に置く(理由 ${reasons_at} / 振り返り ${retro_at} / リンク ${link_at})"
fi
check_eq "" "$(line_before "$retro_at" "$COMMENT")" "理由の箇条書きと振り返りの件数の間に空行を置く(箇条書きに続けない)"
check_has "- tflint の最新のリリース: HTTP 404" "$(cat "$COMMENT" 2>/dev/null)" "取得できなかった理由をコメントに載せる"

# --- 台帳に書けない ---
reset_main
ok_externals
export STUB_FAIL_ON=comment
run_main "$WORK/main-targets.json"
check_rc 2 "$MAIN_EXIT" "コメントに失敗したら終了コード 2(要件2-7)"
reset_main
ok_externals
resp "$R_LEDGER_LIST" 200 '[]'
export STUB_FAIL_ON=create
run_main "$WORK/main-targets.json"
check_rc 2 "$MAIN_EXIT" "台帳の作成に失敗したら終了コード 2(要件2-7)"
check_eq "0" "$(gh_calls '^gh issue comment ')" "台帳を作れなかったときはコメントしない"
reset_main
ok_externals
resp "$R_LEDGER_LIST" 500 '{"message":"Server Error"}'
run_main "$WORK/main-targets.json"
check_rc 2 "$MAIN_EXIT" "台帳を探せなかったら終了コード 2(要件2-7)"
check_eq "0" "$(gh_calls '^gh (issue create|issue comment|label create) ')" "台帳を探せなかったときは作らず、コメントもしない"
reset_main
ok_externals
export STUB_FAIL_ON=label
resp "$R_LEDGER_LIST" 200 '[]'
run_main "$WORK/main-targets.json"
check_rc 0 "$MAIN_EXIT" "ラベルの作成の失敗(既にある場合を含む)だけでは止めない"

# --- 環境変数の不足 ---
for v in GH_TOKEN GITHUB_REPOSITORY GITHUB_REPOSITORY_OWNER GITHUB_SERVER_URL GITHUB_RUN_ID; do
    reset_main
    ok_externals
    MAIN_UNSET="$v"
    run_main "$WORK/main-targets.json"
    check_rc 2 "$MAIN_EXIT" "環境変数 ${v} が無いと終了コード 2"
    check_eq "0" "$(grep -cE '^(gh|curl) ' "$WORK/calls.log")" "環境変数 ${v} が無いときは gh も curl も呼ばない"
done

# --- 引数と設定ファイルの誤り ---
reset_main
run_main
check_rc 2 "$MAIN_EXIT" "引数が無いと終了コード 2"
reset_main
run_main "$WORK/main-targets.json" extra
check_rc 2 "$MAIN_EXIT" "引数が2つ以上だと終了コード 2"
reset_main
run_main "$WORK/none.json"
check_rc 2 "$MAIN_EXIT" "設定ファイルが無いと終了コード 2"
reset_main
jq '.targets[0].latest = {"type": "npm", "package": "x"}' "$WORK/main-targets.json" >"$WORK/main-bad.json"
run_main "$WORK/main-bad.json"
check_rc 2 "$MAIN_EXIT" "設定ファイルの形が違うと終了コード 2"
check_eq "0" "$(grep -cE '^(gh|curl) ' "$WORK/calls.log")" "設定ファイルの形が違うときは gh も curl も呼ばない"

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
