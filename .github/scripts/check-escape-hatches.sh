#!/usr/bin/env bash
# =====================================================================
# 逃げ道封鎖チェック(guardrails CI から実行)
#
# 「見かけの合格」を作る変更を機械的に拒否する。
#   1. 品質ゲート配線の改変
#      - build.gradle の apply from は gradle/quality.gradle の1本のみ
#      - build.gradle 以外の backend 配下 *.gradle / *.gradle.kts での apply from は0本
#        (apply from は拡張子を問わず任意のファイルを読み込めるため、
#         読み込み先の拡張子には依存せず「apply from の存在」自体を検査する)
#      - violationRules / jacocoTestCoverageVerification の build.gradle への記述禁止
#   2. テストの skip/only/@Disabled 追加
#   3. @ts-ignore / @ts-expect-error / @ts-nocheck の追加
#   4. eslint-disable インラインコメントの追加
#   5. 既存テストのアサーション変更・削除(PR本文に Test-Change-Justification: が無ければ赤。
#      ユニットテスト .test. とE2E .spec. の両方が対象)
#   6. ゲート隣接ファイルの変更(リポジトリ所有者のApproveが無ければ赤。
#      CODEOWNERSの必須レビューと二重の防御)
#
# 差分の読み方について:
#   ファイル名は `git diff -z --name-only` でNUL区切りの生のパスとして取得し、
#   行の抽出はファイルごとに `git diff` を回して行う。
#
#   `diff --git a/X b/X` のヘッダ行を空白で分割してファイル名を取り出す方式は使わない。
#   その方式では、空白を含むパスでフィールドがずれ、非ASCIIを含むパスでは
#   Gitの既定(core.quotepath=true)によりパスが引用符と8進エスケープに変換されるため、
#   どちらもパスの正規表現に一致せず「検知0件」のまま緑になる。エラーは出ない。
#   検査が静かに素通りする形になるため、ファイル名を解析しない形にしてある。
#
#   -z はこの引用そのものを無効にする。開発機に core.quotepath=false が設定されていると
#   手元では正しく動いて見えるため、この違いはCIでのみ現れる。
#
#   リネームの扱い: 変更ファイルの一覧は新しいパスだけを返し、ファイル単位の diff では
#   リネームの検出が効かないため、純リネームでも全行が追加行として現れる。つまり
#   「既にハッチを含むファイル」を動かすと、内容を変えていなくても赤になる。
#   これは意図した挙動として受け入れる。ハッチが残ったままのファイルを動かすときに
#   精算を求めるのは、この検査の趣旨に沿うため。ハッチを含まないファイルの
#   リネームは通る。
#
# 環境変数:
#   PR_BODY        : PR本文(5の理由記載チェックに使用)
#   OWNER_APPROVED : "true" なら所有者Approve済み(6の判定に使用)
#
# テスト: .github/scripts/tests/test-check-escape-hatches.sh
# 使い方: check-escape-hatches.sh <base_sha> <head_sha>
# =====================================================================
set -euo pipefail

BASE_SHA="${1:?base sha required}"
HEAD_SHA="${2:?head sha required}"
PR_BODY="${PR_BODY:-}"
OWNER_APPROVED="${OWNER_APPROVED:-false}"

MERGE_BASE=$(git merge-base "$BASE_SHA" "$HEAD_SHA")

# 変更ファイルの一覧。NUL区切りで受けるため、空白も非ASCIIもそのまま扱える。
#
# プロセス置換の中のコマンドの失敗は set -e に拾われず、mapfile は空配列のまま
# 正常終了する。そのままだと「変更ファイル0件 = 検知0件 = 緑」になり、
# この検査が塞ごうとしている fail-open そのものを作ってしまう。
# 末尾に番兵を付けて、git diff が最後まで成功したことをこの場で確認する。
CHANGED_FILES=()
mapfile -d '' -t CHANGED_FILES < <(
    git diff -z --name-only "$MERGE_BASE" "$HEAD_SHA" && printf '__GIT_DIFF_OK__\0'
)
if [ "${#CHANGED_FILES[@]}" -eq 0 ] || [ "${CHANGED_FILES[-1]}" != "__GIT_DIFF_OK__" ]; then
    echo "::error::git diff --name-only が失敗しました。検査が素通りするのを防ぐため停止します。"
    exit 1
fi
unset 'CHANGED_FILES[-1]'

violations=0

report() {
    violations=$((violations + 1))
    echo "::error::[$1] $2"
    {
        echo "### :no_entry: $1"
        echo ""
        echo '```'
        echo "$2"
        echo '```'
    } >>"${GITHUB_STEP_SUMMARY:-/dev/null}"
}

# 指定した符号の行を「ファイル名: 行」形式で抽出する。
# sign が + なら追加行、- なら削除行。
#
# ヘッダ行(--- a/x, +++ b/x)は最初のハンク(@@)より必ず前に出るため、
# @@ 以降だけを走査すれば除外できる。符号の重なりで判定すると、
# 中身が -- や ++ で始まる行(例: 削除された `--i;`)を取りこぼす。
#
# pathspec に :(literal) を付けるのは、ファイル名に * や [ が含まれる場合に
# Gitがグロブとして解釈するのを防ぐため。
diff_lines_for() {
    local sign="$1" pat="$2" f
    for f in ${CHANGED_FILES[@]+"${CHANGED_FILES[@]}"}; do
        [[ "$f" =~ $pat ]] || continue
        git diff --unified=0 "$MERGE_BASE" "$HEAD_SHA" -- ":(literal)$f" |
            SIGN="$sign" FNAME="$f" awk '
                BEGIN { sign = ENVIRON["SIGN"]; name = ENVIRON["FNAME"] }
                /^@@/ { inhunk = 1; next }
                inhunk && substr($0, 1, 1) == sign {
                    print name ": " substr($0, 2)
                }
            '
    done
}

added_lines_for() {
    diff_lines_for '+' "$1"
}

removed_lines_for() {
    diff_lines_for '-' "$1"
}

changed_files=$(printf '%s\n' ${CHANGED_FILES[@]+"${CHANGED_FILES[@]}"})

# --- 1. 品質ゲート配線(差分の有無に関係なく常時検証) ---
# Groovy形式(apply from: 'x')とKotlin形式(apply(from = "x"))の両方を捕捉する
apply_pattern='apply[[:space:]]*\(?[[:space:]]*from'

# build.gradle: apply from は gradle/quality.gradle の1本のみ
build_applies=$(APPLY_PAT="$apply_pattern" awk '
    BEGIN { pat = ENVIRON["APPLY_PAT"] }
    /^[[:space:]]*\/\// { next }
    $0 ~ pat { print FILENAME ":" FNR ": " $0 }
' backend/build.gradle || true)
build_apply_count=$(printf '%s\n' "$build_applies" | grep -c . || true)
quality_apply_count=$(printf '%s\n' "$build_applies" | grep -c "gradle/quality.gradle" || true)
if [ "$build_apply_count" -ne 1 ] || [ "$quality_apply_count" -ne 1 ]; then
    report "品質ゲート配線の改変" "backend/build.gradle の apply from は gradle/quality.gradle の1本のみ許可です(現在 ${build_apply_count} 本)。別ファイルの読み込みは依存追加検査・ゲート保護の迂回になるため禁止します。
${build_applies:-（apply from がありません = 品質ゲート定義が無効化されています）}"
fi

# build.gradle 以外の backend 配下 *.gradle / *.gradle.kts: apply from は0本
# awkのプログラム中の $0 はawkの変数であり、シェルに展開させてはならない。
# パターンは ENVIRON 経由で渡しているため、シングルクォートは意図どおり。
# shellcheck disable=SC2016
other_applies=$(find backend -type f \( -name '*.gradle' -o -name '*.gradle.kts' \) \
    ! -path 'backend/build.gradle' ! -path '*/build/*' ! -path '*/.gradle/*' -print0 |
    APPLY_PAT="$apply_pattern" xargs -0 -r awk '
        BEGIN { pat = ENVIRON["APPLY_PAT"] }
        /^[[:space:]]*\/\// { next }
        $0 ~ pat { print FILENAME ":" FNR ": " $0 }
    ' 2>/dev/null || true)
if [ -n "$other_applies" ]; then
    report "build.gradle以外でのapply from" "backend 配下のGradleファイルで apply from を使えるのは build.gradle(quality.gradleの読み込み)だけです。
$other_applies"
fi

if grep -qE 'violationRules|jacocoTestCoverageVerification' backend/build.gradle; then
    report "カバレッジ閾値の上書き" "backend/build.gradle に violationRules / jacocoTestCoverageVerification の記述があります。閾値定義は gradle/quality.gradle のみで行ってください。"
fi

# --- 2. テストの skip/only 追加(TS/JS) ---
found=$(added_lines_for '^frontend/.*\.(ts|tsx|js|jsx)$' | grep -E '\.(skip|only)\s*\(|\b(xit|xdescribe|xtest)\s*\(' || true)
if [ -n "$found" ]; then
    report "テストの skip/only 追加" "$found"
fi

# --- 2b. @Disabled の追加(Java) ---
found=$(added_lines_for '^backend/src/test/.*\.java$' | grep -E '@Disabled' || true)
if [ -n "$found" ]; then
    report "Javaテストの @Disabled 追加" "$found"
fi

# --- 3. TypeScript 型チェック抑止の追加 ---
found=$(added_lines_for '^frontend/.*\.(ts|tsx)$' | grep -E '@ts-ignore|@ts-expect-error|@ts-nocheck' || true)
if [ -n "$found" ]; then
    report "TypeScript 型チェック抑止の追加" "$found"
fi

# --- 4. eslint-disable インラインの追加 ---
found=$(added_lines_for '^frontend/src/.*\.(ts|tsx|js|jsx)$' | grep -E 'eslint-disable' || true)
if [ -n "$found" ]; then
    report "eslint-disable インライン追加" "$found
例外が必要な場合はインラインではなく eslint.config.js(所有者承認必須)へ理由付きで定義してください。"
fi

# --- 5. 既存テストのアサーション変更・削除(.test. と .spec. の両方) ---
ts_asserts=$(removed_lines_for '^frontend/.*\.(test|spec)\.(ts|tsx)$' | grep -E '\bexpect\s*\(' || true)
java_asserts=$(removed_lines_for '^backend/src/test/.*\.java$' | grep -E '\bassert[A-Za-z]*\s*\(|\bverify\s*\(|\bassertThatThrownBy' || true)
if [ -n "$ts_asserts$java_asserts" ]; then
    if ! echo "$PR_BODY" | grep -q 'Test-Change-Justification:'; then
        report "既存テストのアサーション変更・削除" "アサーションを含む行の変更・削除が検出されました。意図的な変更であれば PR 本文に「Test-Change-Justification: <理由>」を記載してください。
${ts_asserts}
${java_asserts}"
    else
        echo "アサーション変更を検出しましたが、PR本文に Test-Change-Justification: の記載があるため通過します。" >>"${GITHUB_STEP_SUMMARY:-/dev/null}"
    fi
fi

# --- 6. ゲート隣接ファイルの変更(所有者Approveが必要) ---
gate_files=$(echo "$changed_files" | grep -E '^(\.github/|\.claude/|frontend/eslint\.config\.js|frontend/vite\.config\.ts|frontend/playwright\.config\.ts|backend/gradle/quality\.gradle|backend/config/|backend/src/test/java/com/example/keirekipro/unit/architecture/)' || true)
if [ -n "$gate_files" ]; then
    if [ "$OWNER_APPROVED" != "true" ]; then
        report "ゲート設定ファイルの変更(所有者未承認)" "以下のゲート設定ファイルが変更されています。リポジトリ所有者のApproveレビュー後にこのチェックは緑になります。
$gate_files"
    else
        echo "ゲート設定ファイルの変更は所有者Approve済みのため通過します。" >>"${GITHUB_STEP_SUMMARY:-/dev/null}"
    fi
fi

if [ "$violations" -gt 0 ]; then
    echo ""
    echo "逃げ道封鎖チェック: ${violations} 件の違反を検出しました。"
    exit 1
fi

echo "逃げ道封鎖チェック: 違反なし"
