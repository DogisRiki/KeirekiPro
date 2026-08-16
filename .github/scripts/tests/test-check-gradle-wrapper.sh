#!/usr/bin/env bash
# =====================================================================
# check-gradle-wrapper.sh の自動テスト(guardrails CI から実行)
#
# 一時gitリポジトリにbase/headを作り、curl をスタブして終了コードを検証する。
#   0 = 緑(通過) / 1 = 赤
#
# 外部への問い合わせを行わないため、実行にネットワークを必要としない。
# 併せて、対象外の差分で問い合わせが発生しないことも検証する。
#
# 各ケースは「seed → 変更を加える関数 → run_check」の3行で書く。変更を加える関数を
# 引数で渡す形にしないのは、静的解析が引数位置の関数名を参照と数えず、
# 未使用の関数として報告してしまうため。コマンド位置で呼べば抑制指示が要らない。
# =====================================================================
set -uo pipefail

SCRIPT="$(cd "$(dirname "$0")/.." && pwd)/check-gradle-wrapper.sh"
WORK=$(mktemp -d) || exit 1
[ -n "$WORK" ] && [ -d "$WORK" ] || exit 1
trap 'rm -rf "$WORK"' EXIT
export GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@example.com
export GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@example.com
FAILED=0

# 公式値として返すチェックサム(64桁)
OFFICIAL="6f74b601422d6d6fc4e1f9a1ab6522f642c2fdcbc15ae33ebd30ba3d7198e854"
OTHER="0000000000000000000000000000000000000000000000000000000000000000"
HOST="dist.invalid"

mkdir -p "$WORK/bin"
# curl のスタブ。呼ばれた事実を記録し、$STUB_SHA の内容を返す。
cat >"$WORK/bin/curl" <<'STUB'
#!/usr/bin/env bash
url=""
for a in "$@"; do case "$a" in http*) url="$a" ;; esac; done
echo "$url" >>"${STUB_CALLS:?}"
cat "${STUB_SHA:?}"
STUB
chmod +x "$WORK/bin/curl"

seed() {
    rm -rf "$WORK/repo"
    mkdir -p "$WORK/repo/backend/gradle/wrapper" "$WORK/repo/src"
    cd "$WORK/repo" || exit 1
    git init -q .
    {
        echo "distributionBase=GRADLE_USER_HOME"
        echo "distributionUrl=https\\://${HOST}/distributions/gradle-8.14.5-bin.zip"
        echo "distributionSha256Sum=${OFFICIAL}"
        echo "networkTimeout=10000"
    } >backend/gradle/wrapper/gradle-wrapper.properties
    echo "placeholder" >src/main.txt
    git add -A && git commit -qm base
    BASE=$(git rev-parse HEAD)
}

# 使い方: seed し、変更を加えてから run_check <期待exit> <説明> <curlが返す値>
run_check() {
    local want="$1" name="$2" sha="$3" got
    git add -A && git commit -qm head --allow-empty
    : >"$WORK/calls.log"
    : >"$WORK/summary.md"
    printf '%s\n' "$sha" >"$WORK/sha.txt"
    PATH="$WORK/bin:$PATH" \
        STUB_CALLS="$WORK/calls.log" STUB_SHA="$WORK/sha.txt" \
        GRADLE_DIST_HOST="$HOST" GITHUB_STEP_SUMMARY="$WORK/summary.md" \
        bash "$SCRIPT" "$BASE" "$(git rev-parse HEAD)" >/dev/null 2>&1
    got=$?
    if [ "$got" -eq "$want" ]; then
        echo "PASS: $name"
    else
        echo "FAIL: $name (expected exit $want, got $got)"
        FAILED=1
    fi
}

check_summary() {
    if grep -qF "$1" "$WORK/summary.md"; then
        echo "PASS: $2"
    else
        echo "FAIL: $2 (Summaryに '$1' が現れない)"
        FAILED=1
    fi
}

check_no_calls() {
    if [ ! -s "$WORK/calls.log" ]; then
        echo "PASS: $1"
    else
        echo "FAIL: $1 (外部への問い合わせが発生した)"
        FAILED=1
    fi
}

check_calls() {
    if [ -s "$WORK/calls.log" ]; then
        echo "PASS: $1"
    else
        echo "FAIL: $1 (外部への問い合わせが発生していない)"
        FAILED=1
    fi
}

# --- 変更を加える関数 -----------------------------------------------------------
touch_unrelated() { echo "changed" >src/main.txt; }
touch_wrapper_noop() { printf '\n# comment\n' >>backend/gradle/wrapper/gradle-wrapper.properties; }
add_jar_outside() { mkdir -p tools && echo "binary" >tools/gradle-wrapper.jar; }
break_host() {
    sed -i "s#distributionUrl=.*#distributionUrl=https\\\\://evil.invalid/distributions/gradle-8.14.5-bin.zip#" \
        backend/gradle/wrapper/gradle-wrapper.properties
}
drop_sum() {
    sed -i "/^distributionSha256Sum=/d" backend/gradle/wrapper/gradle-wrapper.properties
}
tamper_sum() {
    sed -i "s#^distributionSha256Sum=.*#distributionSha256Sum=${OTHER}#" \
        backend/gradle/wrapper/gradle-wrapper.properties
}
delete_properties() {
    rm -f backend/gradle/wrapper/gradle-wrapper.properties
}

echo "--- 実行条件 ---"
seed
touch_unrelated
run_check 0 "wrapper 関連の変更がなければ成功する" "$OFFICIAL"
check_no_calls "対象外の差分では外部へ問い合わせない"

seed
touch_wrapper_noop
run_check 0 "wrapper ディレクトリの変更があれば検査して通す" "$OFFICIAL"
check_calls "wrapper の変更で外部へ問い合わせる"

seed
add_jar_outside
run_check 0 "wrapper ディレクトリ外の jar 追加でも検査が走る" "$OFFICIAL"
check_calls "ディレクトリ外の jar でも外部へ問い合わせる"

echo "--- 検査1: 配布元のホスト ---"
seed
break_host
run_check 1 "公式でないホストを指す設定は落とす" "$OFFICIAL"
check_summary "配布元のホストが公式ではありません" "ホスト不一致が報告される"

echo "--- 検査2: チェックサムの存在 ---"
seed
drop_sum
run_check 1 "チェックサムの項目が無ければ落とす" "$OFFICIAL"
check_summary "distributionSha256Sum がありません" "項目の欠落が報告される"

echo "--- 検査3: 公表値との一致 ---"
seed
tamper_sum
run_check 1 "チェックサムが公表値と異なれば落とす" "$OFFICIAL"
check_summary "チェックサムが公表値と一致しません" "不一致が報告される"

seed
touch_wrapper_noop
run_check 1 "公表値を取得できなければ落とす" "not-a-checksum"
check_summary "公表チェックサムを取得できません" "取得失敗が報告される"
check_summary "外部要因による失敗です" "外部要因である旨が出る"

echo "--- 検査対象の消失 ---"
seed
delete_properties
run_check 1 "設定ファイルが削除されたら落とす" "$OFFICIAL"
check_summary "1つも見つかりません" "対象消失が報告される"

echo "--- 報告の性質 ---"
seed
tamper_sum
run_check 1 "失敗は時間では解消しない旨を出す" "$OFFICIAL"
check_summary "時間の経過では解消しません" "時間で解消しない旨が出る"

if [ "$FAILED" -eq 0 ]; then
    echo "すべてのテストがPASSしました。"
else
    echo "失敗したテストがあります。"
fi
exit "$FAILED"
