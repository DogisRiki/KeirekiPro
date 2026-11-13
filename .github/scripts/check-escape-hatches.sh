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
#   2. テストの skip/only/@Disabled 追加と、Go のテストの t.Skip / t.SkipNow / t.Skipf 追加
#   3. @ts-ignore / @ts-expect-error / @ts-nocheck の追加
#   4. eslint-disable インラインコメントの追加と、Go の //nolint と // coverage-ignore の追加
#   5. 既存テストのアサーション変更・削除(PR本文に Test-Change-Justification: が無ければ赤。
#      ユニットテスト .test. とE2E .spec. の両方が対象)
#   6. ゲート隣接ファイルの変更(リポジトリ所有者のApproveが無ければ赤。
#      CODEOWNERSの必須レビューと二重の防御。品質チェックが何を調べるかを決めるファイルと、
#      Go 版のコード生成の設定を含む。frontend/package.json と docker/terraform/Dockerfile は、
#      依存の版のほかの欄や行が変わったときだけ赤にする。この2つは CODEOWNERS には載せない)
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

# --- 2c. Go のテストの飛ばしの追加 ---
# t.Skip / t.SkipNow / t.Skipf を見つける。受け手の名前は t に限らない(tb や b、
# テストの外の助けの関数から呼ぶ形もある)ため、.Skip の呼び出しの形で見る。
# _test.go に限らないのは、Docker が無いときに飛ばす助けの関数を、テストの外の
# .go のファイルに置けるためである
found=$(added_lines_for '^backend/.*\.go$' | grep -E '\.Skip(Now|f)?[[:space:]]*\(' || true)
if [ -n "$found" ]; then
    report "Go のテストの飛ばしの追加" "$found"
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

# --- 4b. Go の検査の外しとカバレッジの除外の追加 ---
# //nolint は golangci-lint の検査を外す。// coverage-ignore は go-test-coverage の
# カバレッジの計算からその関数やブロックを外す。どちらも、コメントの後ろの空白の有無を問わずに見る
found=$(added_lines_for '^backend/.*\.go$' | grep -E '//[[:space:]]*(nolint|coverage-ignore)' || true)
if [ -n "$found" ]; then
    report "Go の検査の外しの追加" "$found
例外が必要な場合はコードのコメントではなく backend/.golangci.yml か backend/.testcoverage.yml(所有者承認必須)へ理由付きで定義してください。"
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
# 品質チェックが何を調べるかを決めるファイルを、ここに漏れなく並べる(#826)。
# .github/CODEOWNERS とルートの CLAUDE.md の「人間の承認が必要な変更」にも、同じファイルを並べてある。
#
# 設定のファイルは、今は無い別の名前でも置ける。道具は、決まった名前の順に探して最初に
# 見つけたファイルを読むか、調べるファイルに近い場所のファイルを読むため、別の名前や
# 下のフォルダに新しく置いた設定が、今の設定より先に読まれることがある。
# そのため、今あるファイルの名前だけでなく、道具が読む名前を広く並べる。
#   - vitest は vitest.config.* を vite.config.* より先に読み、vite は vite.config.js を
#     vite.config.ts より先に読む
#   - prettier と、型の情報を使う eslint の検査は、調べるファイルに近いフォルダの
#     .prettierrc* と tsconfig.json を読む
# Go 版の品質チェックとコード生成の設定は、ファイルの名前で完全に一致させる($ で終える)。
# .testcoverage.yml に除外を足す変更も、ここで所有者の承認を求める
gate_patterns=(
    '\.github/'
    '\.claude/'
    # 秘密の情報の検査(gitleaks)から外す一覧と、検査の規則
    '\.gitleaks(ignore|\.toml)$'
    # frontend の lint・単体テストとカバレッジ・E2E の設定
    'frontend/(.*/)?eslint\.config\.[^/]+$'
    'frontend/(vite|vitest)\.config\.[^/]+$'
    'frontend/vitest\.workspace\.[^/]+$'
    'frontend/playwright\.config\.[^/]+$'
    # frontend の型チェックと書式チェックの設定
    'frontend/(.*/)?tsconfig[^/]*\.json$'
    'frontend/(.*/)?\.prettierrc[^/]*$'
    'frontend/(.*/)?prettier\.config\.[^/]+$'
    'frontend/\.prettierignore$'
    '(frontend/(.*/)?)?\.editorconfig$'
    # frontend の未使用のコードの報告(knip)と変異テスト(stryker)の設定
    'frontend/\.?knip\.[^/]+$'
    'frontend/\.?stryker\.conf[^/]*$'
    # backend の Java 版の品質チェックの定義と設定と、アーキテクチャの境界のテスト
    'backend/gradle/quality\.gradle$'
    'backend/config/'
    'backend/src/test/java/com/example/keirekipro/unit/architecture/'
    # backend の Go 版の品質チェックとコード生成の設定
    'backend/(Makefile|\.golangci\.yml|\.testcoverage\.yml|\.gremlins\.yaml|api/oapi-codegen\.yaml|sqlc\.yaml)$'
    # terraform の静的検査(checkov と tflint)の設定と、checkov の既知の指摘の一覧
    'terraform/(.*/)?\.checkov\.ya?ml$'
    'terraform/(.*/)?\.tflint\.hcl$'
    'terraform/\.checkov\.baseline$'
)
gate_pattern="^($(
    IFS='|'
    echo "${gate_patterns[*]}"
))"
gate_files=$(echo "$changed_files" | grep -E "$gate_pattern" || true)

# 一部の欄や行だけが品質チェックを決めるファイル。
# 依存の版を上げる変更(Dependabot の PR など)は、ルートの CLAUDE.md の決まりで
# 所有者の承認の対象外にしてあるので、版の欄や行のほかが変わったときだけ承認を求める。
# base と head のどちらかで中身を読めないとき(ファイルの追加・削除、JSON として読めない)は、
# 変わったものとして承認を求める(読めないことを理由に素通りさせない)。
show_at() {
    git show "$1:$2"
}

# frontend/package.json: CI は scripts の欄のコマンド(pnpm run format / lint / coverage / build)で
# 品質チェックを動かす。prettier と knip は package.json の欄の設定も読む。
# 依存の版の欄(dependencies など)と packageManager を除いた残りを比べる
package_json_settings() {
    show_at "$1" frontend/package.json |
        jq -S 'del(.dependencies, .devDependencies, .optionalDependencies, .peerDependencies, .packageManager)'
}

# docker/terraform/Dockerfile: CI の terraform の静的検査は、このファイルで作ったイメージの
# tflint と checkov を動かす。FROM の行のイメージのタグと digest を除いた残りを比べる。
# イメージの名前を変える変更は、承認を求める
# awk のプログラムの中の $1 と $i は awk の変数であり、シェルに展開させない。
# shellcheck disable=SC2016
dockerfile_without_versions() {
    show_at "$1" docker/terraform/Dockerfile |
        awk '
            toupper($1) == "FROM" {
                for (i = 2; i <= NF; i++) {
                    if (substr($i, 1, 2) == "--") continue
                    sub(/@sha256:[0-9a-f]+$/, "", $i)
                    sub(/:[^:\/]*$/, "", $i)
                    break
                }
            }
            { print }
        '
}

# 使い方: partial_changed <中身を取り出す関数>
# base と head で取り出した中身が違うか、どちらかを取り出せなければ 0(承認が要る)を返す
partial_changed() {
    local before after
    before=$("$1" "$MERGE_BASE" 2>/dev/null) || return 0
    after=$("$1" "$HEAD_SHA" 2>/dev/null) || return 0
    [ "$before" != "$after" ]
}

if printf '%s\n' "$changed_files" | grep -qxF 'frontend/package.json' &&
    partial_changed package_json_settings; then
    gate_files="${gate_files:+$gate_files
}frontend/package.json(依存の版の欄と packageManager のほかの欄)"
fi
if printf '%s\n' "$changed_files" | grep -qxF 'docker/terraform/Dockerfile' &&
    partial_changed dockerfile_without_versions; then
    gate_files="${gate_files:+$gate_files
}docker/terraform/Dockerfile(FROM の行のイメージの版のほかの行)"
fi

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
