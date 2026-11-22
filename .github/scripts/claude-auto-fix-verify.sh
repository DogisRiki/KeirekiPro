#!/usr/bin/env bash
# =====================================================================
# claude-auto-fix の verify ジョブで、Claude の変更を確かめるスクリプト
# (design.md の claude-auto-fix-verify.sh の節)
#
# 使い方: claude-auto-fix-verify.sh <apply|check|confirm> <kind> <key> <detail> <起点のコミット>
#   起点のコミットは、verify ジョブが作業のフォルダに作り直した起点のコードのコミットである。
#   verify ジョブは、apply、check、confirm の順に、同じ作業のフォルダで呼ぶ。
#
# apply の形:
#   1. 作業のフォルダ(起点のコミットのまま)に Claude の変更 claude.patch を当てる
#   2. 派生のファイルを次の順で作り直す。派生のファイルとは、Claude が直接書かず、
#      Claude が変えたファイルからコマンドで作り直すファイルである
#      - npm の公開日時の判定: 種類が npm のとき、修正版の公開日時を npm のレジストリから読み、
#        frontend-vuln-fix.sh decide で扱いを決める。exclude なら frontend-vuln-fix.sh exclude で
#        除外の欄に足し、wait なら blocked にする
#      - pnpm: frontend/package.json か frontend/pnpm-workspace.yaml が変わったとき、
#        pnpm install --lockfile-only --no-frozen-lockfile --ignore-scripts --ignore-pnpmfile を動かす。
#        --ignore-pnpmfile は、Claude が書いた .pnpmfile.cjs を apply の中で動かさず、apply の出力を書き換えさせないため
#        エラーの文に ERR_PNPM_NO_MATURE_MATCHING_VERSION があれば(公開から72時間経っていない版で
#        止まった。research.md の pnpm のエラーの文の確認)blocked にし、ほかの失敗は unfixed にする
#      - Go の部品: backend/go.mod が変わったとき、go mod tidy を動かす
#      - Go の標準ライブラリ: 種類が go-stdlib のとき、backend-vuln-fix.sh go_bump <key の版> を動かす
#      - Dockerfile の digest: 名前が Dockerfile で始まるファイルで、Claude の変更と作り直しが
#        足した FROM の行のイメージが、タグがあり digest が無いとき、backend-vuln-fix.sh digest で
#        digest を読み、そのイメージの後ろに @sha256:<digest> を書く
#   3. 作り直したあとのコードを、起点のコミットの子のコミットにし、claude-auto-fix-guard.sh
#      <起点のコミット> <そのコミット> を、作業のフォルダを今のフォルダにして呼ぶ
#   4. ガードを通れば、起点のコミットからそのコミットまでの差を final.patch に書く
#   標準出力: 通らなければ outcome=<unfixed|blocked> の1行を書き、final.patch を置かない。
#   通れば次の3行を書く。
#     areas=<変わった領域の名前の JSON の配列>
#     sha256=<final.patch の SHA-256>
#     cooldown=<true|false>
#   領域は、final.patch が変えたパスから、ci.yaml の detect-changes ジョブと同じ見分け方
#   (filters と、backend_go と backend_compat を決める手順)で決める。名前の順は
#   frontend backend_java backend_go backend_compat dockerfile である。
#   cooldown は、base.patch が変えたパスと final.patch が変えたパスを並べ、作業のフォルダの
#   .github/ci-tool-versions.json とともに lib-claude-auto-fix.sh の cooldown_needed に渡して決める。
#
# check と confirm の形は、起点のコミットに final.patch を当てた木(最後の差分の木)を一時の index で作り、
# 作業のフォルダの追跡するファイルをその木に戻し、追跡しないファイルと無視するファイルを消してから動く。
# 品質チェックや CodeQL のビルドが作業のフォルダを変えても、PR にする中身を確かめるためである。
#
# check の形:
#   起点のコミットから最後の差分の木までに変わったパスから、apply と同じ見分け方で領域を決め直し、
#   領域ごとに次の品質チェックを、GH_TOKEN と GITHUB_TOKEN を外して流す。e2e-smoke は流さない。
#     frontend        作業のフォルダで frontend-vuln-fix.sh frontend_test
#     backend_java    backend で chmod +x ./gradlew のあと ./gradlew check --configuration-cache
#     backend_go      backend で make check と make mutation-diff BASE=origin/main
#     backend_compat  KEIREKIPRO_REPO_ROOT に作業のフォルダの絶対パスを渡し、backend で make compat と make compat-cross
#     dockerfile      変わって残っている Dockerfile ごとに、ci.yaml の docker-smoke と同じ文脈で docker build。
#                     docker-smoke が docker/terraform/Dockerfile に渡すトークンの secret は渡さない
#   1つでも 0 以外(シグナルでの打ち切りを含む)で終われば outcome=unfixed を書いて止まる。
#   すべて通れば、作業のフォルダを最後の差分の木に戻してから outcome=ok を書く。
#
# confirm の形:
#   対象が消えたかを確かめ、outcome=<ok|unfixed> を書く。CAF_REASON が red-check のときと、種類が
#   dependabot か container のときは、調べずに ok にする(red-check と dependabot は check の品質チェックで、
#   container は verify-image ジョブで確かめる)。
#     npm        frontend/pnpm-lock.yaml があり、組の範囲ごとに frontend-vuln-fix.sh vulnerable が 1 で終わること
#     maven      backend-vuln-fix.sh tree で依存の木を書き、vulnerable が組の範囲で 1 で終わること
#     go-stdlib  backend-vuln-fix.sh vulncheck と go_plan の .stdlib が null であること
#     go-module  go_plan の .modules に、key の @ より前の部品が無いこと
#     codeql     CODEQL_SARIF_DIR の *.sarif の結果に、$RUNNER_TEMP/codeql-alert.json の rule_id と同じ規則の ID
#                (ruleId か rule.id)の結果が、path と同じファイル(結果のパスの先頭の target/ を除いて比べる)に無いこと
#   vulnerable が 0 で終わったときと、0 と 1 のほかで終わったとき(調べられなかったとき)は unfixed にする。
#
# 環境変数:
#   RUNNER_TEMP            一時のファイルを書くフォルダ(必須)
#   CAF_TARGET_DIR         作業のフォルダ(既定は今のフォルダの target)。Git のリポジトリであること。
#                          apply では、HEAD が起点のコミットで、変更が無いこと
#   CAF_CLAUDE_PATCH       Claude の変更の差分(既定は $RUNNER_TEMP/claude-auto-fix-claude.patch。apply だけが読む)
#   CAF_BASE_PATCH         prepare ジョブが書いた起点のコードの差分(既定は
#                          $RUNNER_TEMP/claude-auto-fix-base.patch。apply だけが読む)。空でもよいが、ファイルは要る
#   CAF_FINAL_PATCH        最後の差分(既定は $RUNNER_TEMP/claude-auto-fix-final.patch)。apply が書き、check と confirm が読む
#   CAF_REASON             対象ごとの実行の reason(confirm だけが読む。red-check のとき対象を調べない)
#   CODEQL_SARIF_DIR       CodeQL の analyze が SARIF を書いたフォルダ(種類が codeql の confirm で必須)
#   CAF_FRONTEND_VULN_FIX  frontend-vuln-fix.sh の場所(既定はこのスクリプトと同じフォルダ。テストが替える)
#   CAF_BACKEND_VULN_FIX   backend-vuln-fix.sh の場所(既定はこのスクリプトと同じフォルダ。テストが替える)
# ガードと vuln-fix のスクリプトは、作業のフォルダの写しではなく、このスクリプトと同じ
# フォルダのもの(main のコード)を使う。Claude が作業のフォルダのスクリプトを変えても、
# 確かめ方が変わらないようにするためである。
#
# 道具と品質チェックの出力と、このスクリプトの説明の文は標準エラーに出す。種類が codeql のときは、
# CodeQL の警告に関わるファイルの名前が実行の記録に残らないように、標準エラーに出さず、
# $RUNNER_TEMP/claude-auto-fix-verify.log に書く。
#
# 引数と環境の誤りは 2 で終わる。差分を書けないなどの、このスクリプトの中の失敗は 1 で終わる。
# source すると、関数と CAF_AREA_FILTERS を定義するだけで、何も動かさない(テストが caf_areas を呼ぶ)。
#
# テスト: .github/scripts/tests/test-claude-auto-fix-verify.sh
# =====================================================================
set -euo pipefail

CAF_VERIFY_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=.github/scripts/lib-claude-auto-fix.sh
. "$CAF_VERIFY_DIR/lib-claude-auto-fix.sh"

# ci.yaml の detect-changes ジョブの filters のうち、5つの領域の形を同じ順に並べる
# (そろっていることはテストが ci.yaml を読んで確かめる)。backend の見分けは領域ではないので入れない
CAF_AREA_FILTERS=(
    "frontend frontend/**"
    "backend_java backend/src/**"
    "backend_java backend/*.gradle"
    "backend_java backend/gradle/**"
    "backend_java backend/config/**"
    "backend_java backend/gradlew*"
    "backend_java docker/backend/**"
    "backend_go backend/**/*.go"
    "backend_go backend/go.mod"
    "backend_go backend/go.sum"
    "backend_go backend/Makefile"
    "backend_go backend/.golangci.yml"
    "backend_go backend/.testcoverage.yml"
    "backend_go backend/.gremlins.yaml"
    "backend_go backend/api/**"
    "backend_go backend/sqlc.yaml"
    "backend_go backend/db/queries/**"
    "backend_go backend/assets/**"
    "backend_go backend/src/main/resources/db/migration/**"
    "backend_go backend/src/main/resources/mail/**"
    "backend_go docker/backend-go/**"
    "backend_compat backend/compat/**"
    "dockerfile docker/**/Dockerfile*"
)

# 使い方: caf_glob_regex <glob>
# paths-filter(picomatch、dot: true)の glob を、パス全体に当てる拡張正規表現にする。
# ** は / をまたいで当たり、**/ は0個以上のフォルダに当たる。* と ? は / に当たらない
caf_glob_regex() {
    local g="$1" r="" c i n="${#1}"
    for ((i = 0; i < n; i++)); do
        c="${g:i:1}"
        case "$c" in
        '*')
            if [ "${g:i+1:1}" = '*' ]; then
                if [ "${g:i+2:1}" = / ]; then
                    r+='(.*/)?'
                    i=$((i + 2))
                else
                    r+='.*'
                    i=$((i + 1))
                fi
            else
                r+='[^/]*'
            fi
            ;;
        '?') r+='[^/]' ;;
        . | + | ^ | '$' | '(' | ')' | '[' | ']' | '{' | '}' | '|' | "\\") r+="\\$c" ;;
        *) r+="$c" ;;
        esac
    done
    printf '^%s$' "$r"
}

# 使い方: caf_areas <作業のフォルダ> <変えたパスを NUL で区切って並べたファイル>
# 変わった領域の名前を JSON の配列で出す。backend_go は作業のフォルダに backend/go.mod があるときだけ、
# backend_compat は backend/compat があり、Java 版か Go 版か比べる検査のファイルに当たるときだけにする
# (ci.yaml の detect-changes ジョブの Decide backend jobs の手順と同じ)
caf_areas() {
    local dir="$1" list="$2" entry area glob re path
    local frontend=false java=false go_files=false compat_files=false dockerfile=false go=false compat=false
    local -a paths=()
    [ -f "$list" ] || {
        echo "claude-auto-fix-verify: 変えたパスの一覧のファイルがありません: ${list}" >&2
        return 1
    }
    mapfile -d '' -t paths <"$list"
    for entry in "${CAF_AREA_FILTERS[@]}"; do
        area="${entry%% *}"
        glob="${entry#* }"
        re=$(caf_glob_regex "$glob")
        for path in "${paths[@]}"; do
            [[ "$path" =~ $re ]] || continue
            case "$area" in
            frontend) frontend=true ;;
            backend_java) java=true ;;
            backend_go) go_files=true ;;
            backend_compat) compat_files=true ;;
            dockerfile) dockerfile=true ;;
            esac
            break
        done
    done
    if [ "$go_files" = true ] && [ -f "$dir/backend/go.mod" ]; then
        go=true
    fi
    if [ -d "$dir/backend/compat" ] && { [ "$java" = true ] || [ "$go_files" = true ] || [ "$compat_files" = true ]; }; then
        compat=true
    fi
    jq -cn --argjson f "$frontend" --argjson j "$java" --argjson g "$go" --argjson c "$compat" --argjson d "$dockerfile" '
        [ (if $f then "frontend" else empty end), (if $j then "backend_java" else empty end),
          (if $g then "backend_go" else empty end), (if $c then "backend_compat" else empty end),
          (if $d then "dockerfile" else empty end) ]'
}

usage() {
    echo "::error::claude-auto-fix-verify: $1" >&2
    echo "使い方: claude-auto-fix-verify.sh <apply|check|confirm> <kind> <key> <detail> <起点のコミット>" >&2
    exit 2
}
fail() {
    echo "::error::claude-auto-fix-verify: $1" >&2
    exit 1
}
# 使い方: say <文>。説明の文を、種類に合った出力先(標準エラーか記録のファイル)に書く
say() {
    printf 'claude-auto-fix-verify: %s\n' "$1" >&3
}
# 使い方: stop <unfixed|blocked> <理由>
stop() {
    say "$2"
    printf 'outcome=%s\n' "$1"
    exit 0
}

# 使い方: staged_paths <出力のファイル>
# 作業のフォルダの変更をすべて index に入れ、起点のコミットから変わったパスを NUL で区切って書く
staged_paths() {
    git -C "$TARGET" add -A || fail "変更を index に入れられません"
    git -C "$TARGET" diff --cached --name-only --no-renames -z "$BASE" >"$1" || fail "変えたパスを読めません"
}

# 使い方: path_changed <パス>。起点のコミットからそのパスが変わったなら 0
path_changed() {
    staged_paths "$W/changed"
    tr '\0' '\n' <"$W/changed" | grep -qxF -- "$1"
}

# 使い方: run_tool <説明> <フォルダ> <コマンド>...
# 作業のフォルダの中のフォルダでコマンドを動かし、出力を $W/tool.log と説明の文の出力先に書く
run_tool() {
    local what="$1" dir="$2" rc=0
    shift 2
    (cd "$dir" && "$@" </dev/null) >"$W/tool.log" 2>&1 || rc=$?
    cat "$W/tool.log" >&3
    [ "$rc" -eq 0 ] || say "${what} が ${rc} で終わりました"
    return "$rc"
}

npm_step() {
    local name ver urgent published how
    name=$(jq -r '.name' <<<"$DETAIL")
    ver=$(jq -r '.version' <<<"$DETAIL")
    urgent=$(jq -r '.urgent' <<<"$DETAIL")
    published=$(curl -fsS "https://registry.npmjs.org/${name/\//%2F}" | jq -r --arg v "$ver" '.time[$v] // ""') || published=""
    [[ "$published" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:.]+Z$ ]] || stop unfixed "${name} ${ver} の公開日時を読めませんでした"
    how=$(cd "$TARGET" && bash "$FVF" decide "$published" "$(date +%s)" "$urgent") || fail "decide が失敗しました"
    case "$how" in
    go) ;;
    exclude)
        (cd "$TARGET" && bash "$FVF" exclude frontend/pnpm-workspace.yaml "${name}@${ver}") ||
            fail "除外の欄に足せません"
        say "${name}@${ver} を除外の欄に足しました"
        ;;
    wait) stop blocked "${name} ${ver} は公開から72時間経っていません" ;;
    *) fail "decide の結果を読めません: ${how}" ;;
    esac
}

pnpm_step() {
    if ! path_changed frontend/package.json && ! path_changed frontend/pnpm-workspace.yaml; then
        return 0
    fi
    run_tool "pnpm install" "$TARGET/frontend" pnpm install --lockfile-only --no-frozen-lockfile --ignore-scripts --ignore-pnpmfile && return 0
    if grep -qF ERR_PNPM_NO_MATURE_MATCHING_VERSION "$W/tool.log"; then
        stop blocked "公開から72時間経っていない版があり、pnpm が入れられませんでした"
    fi
    stop unfixed "pnpm install が失敗しました"
}

go_step() {
    path_changed backend/go.mod || return 0
    run_tool "go mod tidy" "$TARGET/backend" env GOTOOLCHAIN=auto go mod tidy || stop unfixed "go mod tidy が失敗しました"
}

stdlib_step() {
    [ "$KIND" = go-stdlib ] || return 0
    run_tool "go_bump" "$TARGET" bash "$BVF" go_bump "$KEY" || stop unfixed "Go の版を ${KEY} に上げられませんでした"
}

# 使い方: from_image <FROM の行>。digest を足すイメージ(タグがあり、digest も変数も無い)を出す。無ければ空
from_image() {
    local -a words=()
    local w first=1
    read -r -a words <<<"$1"
    for w in "${words[@]}"; do
        if [ "$first" -eq 1 ]; then
            first=0
            continue
        fi
        case "$w" in
        --*) continue ;;
        esac
        case "$w" in
        *@* | *'$'*) return 0 ;;
        esac
        [[ "${w##*/}" == *:* ]] && printf '%s' "$w"
        return 0
    done
    return 0
}

digest_step() {
    local f line image d new
    local -a files=()
    staged_paths "$W/changed"
    mapfile -d '' -t files <"$W/changed"
    for f in "${files[@]}"; do
        [[ "${f##*/}" == Dockerfile* ]] || continue
        [ -f "$TARGET/$f" ] || continue
        git -C "$TARGET" diff --cached --no-ext-diff --no-textconv --no-color --no-renames --unified=0 "$BASE" -- ":(literal)$f" |
            awk '/^@@/ { h = 1; next } /^diff --git / { h = 0; next }
                 h && /^\+/ { l = substr($0, 2); if (tolower(substr(l, 1, 5)) == "from " || tolower(substr(l, 1, 5)) == "from\t") print l }' \
                >"$W/from" || fail "Dockerfile の差分を読めません: ${f}"
        while IFS= read -r line; do
            image=$(from_image "$line")
            [ -n "$image" ] || continue
            d=$(cd "$TARGET" && bash "$BVF" digest "$image") || stop unfixed "イメージ ${image} の digest を読めませんでした"
            [[ "$d" =~ ^sha256:[0-9a-f]{64}$ ]] || stop unfixed "イメージ ${image} の digest の形が違います"
            new="${line/" $image"/" $image@$d"}"
            [ "$new" != "$line" ] || stop unfixed "イメージ ${image} の行に digest を書けませんでした"
            OLD="$line" NEW="$new" awk '$0 == ENVIRON["OLD"] { print ENVIRON["NEW"]; next } { print }' \
                "$TARGET/$f" >"$W/dockerfile" || fail "Dockerfile を書き直せません: ${f}"
            cat "$W/dockerfile" >"$TARGET/$f" || fail "Dockerfile を書き直せません: ${f}"
            say "${f} の ${image} に digest を足しました"
        done <"$W/from"
    done
}

# 使い方: base_patch_paths <出力のファイル>。base.patch が変えたパスを1行に1つ書く(名前の変更は元と先の両方)
# git apply --numstat は名前の変更の先のパスしか出さないので、起点のコミットの木に base.patch を
# 逆向きに当てた木を一時の index で作り、その木と起点のコミットの差を名前の変更を見分けずに読む
base_patch_paths() {
    : >"$1"
    [ -s "$BASE_PATCH" ] || return 0
    local before
    GIT_INDEX_FILE="$W/base-index" git -C "$TARGET" read-tree "$BASE" || fail "起点のコミットの木を読めません"
    GIT_INDEX_FILE="$W/base-index" git -C "$TARGET" apply --cached --binary -R "$BASE_PATCH" 2>&3 ||
        fail "base.patch を起点のコミットに逆向きに当てられません"
    before=$(GIT_INDEX_FILE="$W/base-index" git -C "$TARGET" write-tree) || fail "base.patch の前の木を作れません"
    git -C "$TARGET" diff --name-only --no-renames -z "$before" "$BASE" | tr '\0' '\n' >"$1" ||
        fail "base.patch が変えたパスを読めません"
}

# 一時のフォルダ W を作り、終わるときに消す
make_work() {
    W=$(mktemp -d "$RT/caf-verify.XXXXXX") || fail "一時のフォルダを作れません"
    trap 'rm -rf -- "$W"' EXIT
}

apply_mode() {
    rm -f -- "$FINAL_PATCH"
    make_work

    git -C "$TARGET" apply --index --binary --whitespace=nowarn "$CLAUDE_PATCH" 2>&3 ||
        stop unfixed "Claude の変更を起点のコードに当てられませんでした"

    if [ "$KIND" = npm ]; then
        npm_step
    fi
    pnpm_step
    go_step
    stdlib_step
    digest_step

    staged_paths "$W/changed"
    [ -s "$W/changed" ] || stop unfixed "起点のコードからの変更がありません"
    git -C "$TARGET" -c user.name=claude-auto-fix -c user.email=claude-auto-fix@users.noreply.github.com \
        -c commit.gpgsign=false commit -q --no-verify -m "claude-auto-fix: verify" >&3 2>&3 ||
        fail "作り直したあとのコードをコミットできません"
    local head
    head=$(git -C "$TARGET" rev-parse HEAD) || fail "作り直したあとのコミットを読めません"

    (cd "$TARGET" && CAF_KIND="$KIND" bash "$CAF_VERIFY_DIR/claude-auto-fix-guard.sh" "$BASE" "$head") >&3 2>&3 ||
        stop unfixed "ガードを通りませんでした"

    git -C "$TARGET" diff --binary --no-ext-diff --no-textconv --no-color "$BASE" "$head" >"$W/final.patch" ||
        fail "最後の差分を書けません"
    git -C "$TARGET" diff --name-only --no-renames -z "$BASE" "$head" >"$W/final-paths" ||
        fail "最後の差分の変えたパスを読めません"

    local areas sum cooldown
    areas=$(caf_areas "$TARGET" "$W/final-paths") || fail "変わった領域を決められません"
    base_patch_paths "$W/cooldown-paths"
    tr '\0' '\n' <"$W/final-paths" >>"$W/cooldown-paths" || fail "変えたパスの一覧を作れません"
    cooldown=$(cooldown_needed "$TARGET/.github/ci-tool-versions.json" "$W/cooldown-paths") ||
        fail "dependency-cooldown の判定が要るかを決められません"
    sum=$(sha256sum <"$W/final.patch" | cut -d' ' -f1) || fail "最後の差分の SHA-256 を計算できません"
    mv -- "$W/final.patch" "$FINAL_PATCH" || fail "最後の差分を書き出し先に置けません: ${FINAL_PATCH}"
    printf 'areas=%s\nsha256=%s\ncooldown=%s\n' "$areas" "$sum" "$cooldown"
}

# 起点のコミットに final.patch を当てた木(最後の差分の木)を一時の index で作り、TREE に入れる
final_tree() {
    GIT_INDEX_FILE="$W/final-index" git -C "$TARGET" read-tree "$BASE" || fail "起点のコミットの木を読めません"
    GIT_INDEX_FILE="$W/final-index" git -C "$TARGET" apply --cached --binary "$FINAL_PATCH" 2>&3 ||
        usage "final.patch を起点のコミットに当てられません"
    TREE=$(GIT_INDEX_FILE="$W/final-index" git -C "$TARGET" write-tree) || fail "最後の差分の木を作れません"
}

# 作業のフォルダの追跡するファイルを最後の差分の木に戻し、追跡しないファイルと無視するファイルを消す
restore_tree() {
    git -C "$TARGET" read-tree -u --reset "$TREE" >&3 2>&3 || fail "作業のフォルダを最後の差分の木に戻せません"
    git -C "$TARGET" clean -ffdxq >&3 2>&3 || fail "作業のフォルダの追跡しないファイルを消せません"
}

# 使い方: run_check <説明> <フォルダ> <コマンド>...
# 品質チェックを、GitHub のトークンを外して動かし、出力を説明の文の出力先に書く。
# 0 以外(シグナルでの打ち切りを含む)で終われば unfixed で止まる
run_check() {
    local what="$1" dir="$2" rc=0
    shift 2
    say "${what} を流します"
    (cd "$dir" && exec env -u GH_TOKEN -u GITHUB_TOKEN "$@" </dev/null) >&3 2>&3 || rc=$?
    [ "$rc" -eq 0 ] || stop unfixed "${what} が ${rc} で終わりました"
}

# 使い方: has_area <領域の名前>。AREAS(JSON の配列)にその名前があれば 0
has_area() {
    [[ "$AREAS" == *"\"$1\""* ]]
}

# 変わって残っている Dockerfile ごとに、ci.yaml の docker-smoke と同じ文脈で docker build を流す
dockerfile_checks() {
    local entry re="" f context
    local -a files=()
    for entry in "${CAF_AREA_FILTERS[@]}"; do
        [ "${entry%% *}" = dockerfile ] && re=$(caf_glob_regex "${entry#* }")
    done
    [ -n "$re" ] || fail "dockerfile の領域の形がありません"
    mapfile -d '' -t files <"$W/paths"
    for f in "${files[@]}"; do
        [[ "$f" =~ $re ]] || continue
        if [ ! -f "$TARGET/$f" ]; then
            say "削除されたため docker build を飛ばします: ${f}"
            continue
        fi
        case "$f" in
        docker/backend/Dockerfile.prod | docker/backend-go/Dockerfile.prod) context=./backend ;;
        *) context=. ;;
        esac
        run_check "docker build ${f}" "$TARGET" docker build --file "$f" "$context"
    done
}

check_mode() {
    make_work
    final_tree
    restore_tree
    git -C "$TARGET" diff --name-only --no-renames -z "$BASE" "$TREE" >"$W/paths" ||
        fail "最後の差分の変えたパスを読めません"
    AREAS=$(caf_areas "$TARGET" "$W/paths") || fail "変わった領域を決められません"
    say "変わった領域: ${AREAS}"
    if has_area frontend; then
        run_check "frontend の品質チェック" "$TARGET" bash "$FVF" frontend_test
    fi
    if has_area backend_java; then
        chmod +x "$TARGET/backend/gradlew" || stop unfixed "backend/gradlew に実行の権限を付けられません"
        run_check "gradlew check" "$TARGET/backend" ./gradlew check --configuration-cache
    fi
    if has_area backend_go; then
        run_check "make check" "$TARGET/backend" make check
        run_check "make mutation-diff" "$TARGET/backend" make mutation-diff BASE=origin/main
    fi
    if has_area backend_compat; then
        run_check "make compat" "$TARGET/backend" KEIREKIPRO_REPO_ROOT="$TARGET" make compat
        run_check "make compat-cross" "$TARGET/backend" KEIREKIPRO_REPO_ROOT="$TARGET" make compat-cross
    fi
    if has_area dockerfile; then
        dockerfile_checks
    fi
    restore_tree
    printf 'outcome=ok\n'
}

# 使い方: ranges_of <組の JSON>。組の範囲を1行に1つ出す。範囲が空でない文字列の空でない配列でなければ 2 で終わる
ranges_of() {
    jq -e '(.ranges | type) == "array" and (.ranges | length) > 0
        and all(.ranges[]; type == "string" and . != "" and (test("\n") | not))' >/dev/null 2>&1 <<<"$1" ||
        usage "組の JSON の範囲の形が違います"
    jq -r '.ranges[]' <<<"$1"
}

# 使い方: judge_vulnerable <終わり方> <説明>。vulnerable の終わり方が 1(範囲に入る版が無い)でなければ unfixed で止まる
judge_vulnerable() {
    case "$1" in
    1) ;;
    0) stop unfixed "$2 に入る版が残っています" ;;
    *) stop unfixed "$2 に入る版が残っているかを調べられませんでした(${1} で終わりました)" ;;
    esac
}

confirm_npm() {
    local name range rc
    local -a ranges=()
    name=$(jq -r '.name' <<<"$DETAIL")
    ranges_of "$DETAIL" >/dev/null
    mapfile -t ranges < <(ranges_of "$DETAIL")
    [ -f "$TARGET/frontend/pnpm-lock.yaml" ] || stop unfixed "frontend/pnpm-lock.yaml がありません"
    for range in "${ranges[@]}"; do
        rc=0
        (cd "$TARGET" && bash "$FVF" vulnerable frontend/pnpm-lock.yaml "$name" "$range") >&3 2>&3 || rc=$?
        judge_vulnerable "$rc" "${name} の範囲 ${range}"
    done
}

confirm_maven() {
    local name rc
    jq -e '(.name | type) == "string" and .name != ""' >/dev/null 2>&1 <<<"$DETAIL" || usage "maven の組の JSON の形が違います"
    ranges_of "$DETAIL" >/dev/null
    name=$(jq -r '.name' <<<"$DETAIL")
    (cd "$TARGET" && bash "$BVF" tree "$W/tree") >&3 2>&3 || stop unfixed "依存の木を書き出せませんでした"
    rc=0
    (cd "$TARGET" && bash "$BVF" vulnerable "$W/tree" "$name" "" "$DETAIL") >&3 2>&3 || rc=$?
    judge_vulnerable "$rc" "${name} の組の範囲"
}

# 使い方: go_plan_file。govulncheck の結果から go_plan の結果を $W/plan.json に書く
go_plan_file() {
    (cd "$TARGET" && bash "$BVF" vulncheck "$W/vulncheck.json") 2>&3 >&3 || stop unfixed "govulncheck が失敗しました"
    (cd "$TARGET" && bash "$BVF" go_plan "$W/vulncheck.json") >"$W/plan.json" 2>&3 ||
        stop unfixed "govulncheck の結果をまとめられませんでした"
}

confirm_stdlib() {
    local rc=0
    go_plan_file
    jq -e '.stdlib == null' >/dev/null 2>&3 <"$W/plan.json" || rc=$?
    case "$rc" in
    0) ;;
    1) stop unfixed "Go の標準ライブラリの脆弱性が残っています" ;;
    *) stop unfixed "govulncheck の結果を読めません" ;;
    esac
}

confirm_module() {
    local module="${KEY%@*}" rc=0
    go_plan_file
    jq -e --arg m "$module" '[.modules[] | select(.module == $m)] | length == 0' >/dev/null 2>&3 <"$W/plan.json" || rc=$?
    case "$rc" in
    0) ;;
    1) stop unfixed "Go の部品 ${module} の脆弱性が残っています" ;;
    *) stop unfixed "govulncheck の結果を読めません" ;;
    esac
}

confirm_codeql() {
    local alert="$RT/codeql-alert.json" rule path s rc
    local -a sarifs=()
    [ -n "${CODEQL_SARIF_DIR:-}" ] && [ -d "$CODEQL_SARIF_DIR" ] || usage "CODEQL_SARIF_DIR のフォルダがありません"
    jq -e '(.rule_id | type) == "string" and .rule_id != "" and (.path | type) == "string" and .path != ""' \
        >/dev/null 2>&1 <"$alert" || usage "警告のファイルを読めません: ${alert}"
    rule=$(jq -r '.rule_id' <"$alert")
    path=$(jq -r '.path' <"$alert")
    shopt -s nullglob
    sarifs=("$CODEQL_SARIF_DIR"/*.sarif)
    shopt -u nullglob
    [ "${#sarifs[@]}" -gt 0 ] || stop unfixed "CodeQL の SARIF がありません"
    for s in "${sarifs[@]}"; do
        rc=0
        jq -e --arg r "$rule" --arg p "$path" '
            [ .runs[] | (.results // [])[] | select((.ruleId // .rule.id) == $r)
              | (.locations // [])[] | .physicalLocation.artifactLocation.uri
              | select(type == "string") | ltrimstr("target/") | select(. == $p) ] | length == 0' \
            >/dev/null 2>&3 <"$s" || rc=$?
        case "$rc" in
        0) ;;
        1) stop unfixed "CodeQL の警告と同じ規則の結果が、同じファイルに残っています" ;;
        *) stop unfixed "CodeQL の SARIF を読めません" ;;
        esac
    done
}

confirm_mode() {
    make_work
    final_tree
    restore_tree
    if [ "${CAF_REASON:-}" = red-check ]; then
        say "red-check は、変えた領域の品質チェックが通ったことで確かめます"
        printf 'outcome=ok\n'
        return 0
    fi
    case "$KIND" in
    npm) confirm_npm ;;
    maven) confirm_maven ;;
    go-stdlib) confirm_stdlib ;;
    go-module) confirm_module ;;
    codeql) confirm_codeql ;;
    dependabot) say "dependabot は、変えた領域の品質チェックが通ったことで確かめます" ;;
    container) say "container は、verify-image ジョブで確かめます" ;;
    esac
    printf 'outcome=ok\n'
}

main() {
    [ $# -eq 5 ] || usage "引数は5つです(${#}個でした)"
    MODE="$1"
    KIND="$2"
    KEY="$3"
    DETAIL="$4"
    BASE="$5"
    case "$MODE" in
    apply | check | confirm) ;;
    *) usage "知らない形です: ${MODE}" ;;
    esac
    case "$KIND" in
    npm | maven | go-stdlib | go-module | codeql | container | dependabot) ;;
    *) usage "知らない種類です: ${KIND}" ;;
    esac
    [ -n "$KEY" ] || usage "key が空です"
    if [ "$KIND" = npm ]; then
        jq -e '(.name | type) == "string" and .name != "" and (.version | type) == "string" and .version != ""
            and (.urgent | type) == "boolean"' >/dev/null 2>&1 <<<"$DETAIL" ||
            usage "npm の組の JSON の形が違います"
    fi
    if [ "$KIND" = go-stdlib ]; then
        [[ "$KEY" =~ ^[0-9]+(\.[0-9]+)+$ ]] || usage "go-stdlib の key の版の形が違います: ${KEY}"
    fi
    if [ "$KIND" = go-module ]; then
        [[ "$KEY" == ?*@?* ]] || usage "go-module の key の形が違います: ${KEY}"
    fi
    [ -n "${RUNNER_TEMP:-}" ] && [ -d "$RUNNER_TEMP" ] || usage "RUNNER_TEMP のフォルダがありません"
    RT=$(cd "$RUNNER_TEMP" && pwd)
    TARGET="${CAF_TARGET_DIR:-target}"
    [ -d "$TARGET" ] || usage "作業のフォルダがありません: ${TARGET}"
    TARGET=$(cd "$TARGET" && pwd)
    git -C "$TARGET" rev-parse --is-inside-work-tree >/dev/null 2>&1 || usage "作業のフォルダが Git のリポジトリではありません: ${TARGET}"
    BASE=$(git -C "$TARGET" rev-parse --verify --quiet "${BASE}^{commit}") || usage "起点のコミットを読めません: $5"
    FINAL_PATCH="${CAF_FINAL_PATCH:-$RT/claude-auto-fix-final.patch}"
    if [ "$MODE" = apply ]; then
        [ "$(git -C "$TARGET" rev-parse HEAD)" = "$BASE" ] || usage "作業のフォルダの HEAD が起点のコミットではありません"
        [ -z "$(git -C "$TARGET" status --porcelain)" ] || usage "作業のフォルダに起点のコミットからの変更があります"
        CLAUDE_PATCH="${CAF_CLAUDE_PATCH:-$RT/claude-auto-fix-claude.patch}"
        BASE_PATCH="${CAF_BASE_PATCH:-$RT/claude-auto-fix-base.patch}"
        [ -f "$CLAUDE_PATCH" ] && [ -r "$CLAUDE_PATCH" ] || usage "Claude の変更の差分を読めません: ${CLAUDE_PATCH}"
        [ -f "$BASE_PATCH" ] && [ -r "$BASE_PATCH" ] || usage "base.patch を読めません: ${BASE_PATCH}"
        CLAUDE_PATCH=$(cd "$(dirname "$CLAUDE_PATCH")" && pwd)/$(basename "$CLAUDE_PATCH")
        BASE_PATCH=$(cd "$(dirname "$BASE_PATCH")" && pwd)/$(basename "$BASE_PATCH")
    else
        [ -f "$FINAL_PATCH" ] && [ -r "$FINAL_PATCH" ] || usage "final.patch を読めません: ${FINAL_PATCH}"
        FINAL_PATCH=$(cd "$(dirname "$FINAL_PATCH")" && pwd)/$(basename "$FINAL_PATCH")
    fi
    FVF="${CAF_FRONTEND_VULN_FIX:-$CAF_VERIFY_DIR/frontend-vuln-fix.sh}"
    BVF="${CAF_BACKEND_VULN_FIX:-$CAF_VERIFY_DIR/backend-vuln-fix.sh}"
    [ -f "$FVF" ] || usage "frontend-vuln-fix.sh がありません: ${FVF}"
    [ -f "$BVF" ] || usage "backend-vuln-fix.sh がありません: ${BVF}"
    if [ "$KIND" = codeql ]; then
        exec 3>>"$RT/claude-auto-fix-verify.log"
    else
        exec 3>&2
    fi
    case "$MODE" in
    apply) apply_mode ;;
    check) check_mode ;;
    confirm) confirm_mode ;;
    esac
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    main "$@"
fi
