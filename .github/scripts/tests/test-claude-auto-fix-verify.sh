#!/usr/bin/env bash
# =====================================================================
# claude-auto-fix-verify.sh の自動テスト(apply・check・confirm の形)
#
# 場合ごとに、起点のコードの Git のリポジトリ target を作ってコミットし、Claude の変更の差分
# claude.patch を作ってから、apply の形を呼ぶ。check と confirm の場合は、apply が書いた final.patch で
# その形を呼ぶ。pnpm・go・curl・make・docker は PATH の先頭に置いた偽物に替え、backend/gradlew は
# 起点のコードに置いた偽物にする。frontend-vuln-fix.sh と backend-vuln-fix.sh は、環境変数
# CAF_FRONTEND_VULN_FIX と CAF_BACKEND_VULN_FIX で偽物に替える。偽物は、受け取った引数と今のフォルダを
# CAP のファイルに残し、動き方を CAP のファイルで選ぶ。ガードは本物の claude-auto-fix-guard.sh を使う。
# 領域の見分けは、ci.yaml の detect-changes ジョブを yq で読んで比べる(yq が要る)。
#
# 場合の名前を KP_TEST_CASE に入れると、その場合だけを流す(例: KP_TEST_CASE=ok)。
# 名前は ok areas plain cooldown-base cooldown-rename npm-wait npm-exclude npm-go npm-unreadable
# pnpm-mature pnpm-fail pnpm-skip go-tidy go-tidy-fail go-stdlib go-bump-fail digest digest-fail
# guard guard-derived noapply filters globs usage
# check-areas check-all check-fail check-none check-restore check-codeql check-usage
# confirm-npm confirm-nolock confirm-maven confirm-stdlib confirm-module confirm-codeql confirm-other。
# =====================================================================
set -uo pipefail

HERE="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$HERE/claude-auto-fix-verify.sh"
CI_YAML="$HERE/../workflows/ci.yaml"
VERSIONS="$HERE/../ci-tool-versions.json"
WORK=$(mktemp -d) || exit 1
[ -n "$WORK" ] && [ -d "$WORK" ] || exit 1
trap 'rm -rf "$WORK"' EXIT
FAILED=0
CASE="${KP_TEST_CASE:-}"
RAN=0

ok() { echo "  ok: $1"; }
ng() { echo "  NG: $1" >&2; FAILED=1; }
expect_eq() { if [ "$2" = "$3" ]; then ok "$1"; else ng "$1(期待: [$3] 実際: [$2])"; fi; }
want() { if [ -z "$CASE" ] || [ "$CASE" = "$1" ]; then RAN=$((RAN + 1)); return 0; fi; return 1; }

export GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@example.com GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@example.com

BIN="$WORK/bin"
mkdir -p "$BIN"

# --- 偽の pnpm: CAP/pnpm-mode で動き方を選ぶ。既定は今のフォルダの pnpm-lock.yaml に1行足す
cat >"$BIN/pnpm" <<'EOF'
#!/usr/bin/env bash
printf '%s|%s\n' "$PWD" "$*" >>"$CAP/pnpm.calls"
case "$(cat "$CAP/pnpm-mode" 2>/dev/null)" in
mature)
    echo " ERR_PNPM_NO_MATURE_MATCHING_VERSION  8 versions do not meet the minimumReleaseAge constraint:" >&2
    echo "left@9.9.9 was published at 2026-11-20T00:00:00.000Z, within the minimumReleaseAge cutoff" >&2
    exit 1 ;;
fail)
    echo " ERR_PNPM_FETCH_404  GET https://registry.npmjs.org/left: Not Found - 404" >&2
    exit 1 ;;
ignorefile)
    echo "build" >>.prettierignore ;;
*)
    echo "  lock-updated: true" >>pnpm-lock.yaml ;;
esac
EOF

# --- 偽の go: CAP/go-mode が fail なら失敗し、そのほかは今のフォルダの go.sum に1行足す
cat >"$BIN/go" <<'EOF'
#!/usr/bin/env bash
printf '%s|%s|%s\n' "$PWD" "${GOTOOLCHAIN:-}" "$*" >>"$CAP/go.calls"
[ "$(cat "$CAP/go-mode" 2>/dev/null)" != fail ] || { echo "go: tidy failed" >&2; exit 1; }
echo "example.com/m v1.2.3 h1:tidied=" >>go.sum
EOF

# --- 偽の curl: CAP/curl-mode が fail なら 22 で終わり、そのほかは CAP/registry.json を出す
cat >"$BIN/curl" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$CAP/curl.calls"
[ "$(cat "$CAP/curl-mode" 2>/dev/null)" != fail ] || exit 22
cat "$CAP/registry.json"
EOF
chmod +x "$BIN/pnpm" "$BIN/go" "$BIN/curl"

# --- 偽の品質チェックが共に使う fake_mode <名前>。標準出力と標準エラーに1行ずつ書き、
# GitHub のトークンを受け取ったら CAP/token.calls に名前を残し、CAP/mode-<名前> の中身で動き方を選ぶ。
# fail は 1 で終わり、kill は自分を KILL のシグナルで止め、touch は作業のフォルダの追跡するファイルを変えて
# 追跡しないファイルと無視するファイルを作る。そのほかは 0 で終わる。呼ばれたときの作業のフォルダの
# docs/readme.txt の中身を CAP/seen-<名前> に残す
FAKE_MODE="$WORK/fake-mode.sh"
cat >"$FAKE_MODE" <<'EOF'
fake_mode() {
    [ -z "${GH_TOKEN:-}${GITHUB_TOKEN:-}" ] || echo "$1" >>"$CAP/token.calls"
    cat "$CAF_TARGET_DIR/docs/readme.txt" >"$CAP/seen-$1" 2>/dev/null
    echo "CHECK-OUTPUT $1"
    echo "CHECK-ERROR $1" >&2
    case "$(cat "$CAP/mode-$1" 2>/dev/null)" in
    fail) exit 1 ;;
    kill) kill -KILL $$ ;;
    touch)
        echo tampered >>"$CAF_TARGET_DIR/docs/readme.txt"
        echo junk >"$CAF_TARGET_DIR/junk.txt"
        mkdir -p "$CAF_TARGET_DIR/frontend/node_modules" && echo x >"$CAF_TARGET_DIR/frontend/node_modules/x" ;;
    esac
    exit 0
}
EOF
export FAKE_MODE

# --- 偽の make: 今のフォルダ・引数・KEIREKIPRO_REPO_ROOT を残し、make-<1つ目の引数> の名前で動き方を選ぶ
cat >"$BIN/make" <<'EOF'
#!/usr/bin/env bash
printf '%s|%s|%s\n' "$PWD" "$*" "${KEIREKIPRO_REPO_ROOT:-}" >>"$CAP/make.calls"
. "$FAKE_MODE"
fake_mode "make-$1"
EOF

# --- 偽の docker
cat >"$BIN/docker" <<'EOF'
#!/usr/bin/env bash
printf '%s|%s\n' "$PWD" "$*" >>"$CAP/docker.calls"
. "$FAKE_MODE"
fake_mode docker
EOF
chmod +x "$BIN/make" "$BIN/docker"
export PATH="$BIN:$PATH"

# --- 偽の backend/gradlew(起点のコードに実行の権限を付けずに置く)
FAKE_GRADLEW="$WORK/gradlew"
cat >"$FAKE_GRADLEW" <<'EOF'
#!/usr/bin/env bash
printf '%s|%s\n' "$PWD" "$*" >>"$CAP/gradlew.calls"
. "$FAKE_MODE"
fake_mode gradlew
EOF
chmod 644 "$FAKE_GRADLEW"

# --- 偽の frontend-vuln-fix.sh: decide は CAP/decide の中身を出し、exclude は除外の欄に1行足す。
# frontend_test は偽の品質チェックにする。vulnerable は、範囲が CAP/vulnerable の行にあれば 0 で終わり、
# 無ければ CAP/vulnerable-rc の数(既定は 1)で終わる
FAKE_FVF="$WORK/fake-frontend-vuln-fix.sh"
cat >"$FAKE_FVF" <<'EOF'
#!/usr/bin/env bash
printf '%s|%s\n' "$PWD" "$*" >>"$CAP/fvf.calls"
case "$1" in
decide) cat "$CAP/decide" ;;
exclude) printf "minimumReleaseAgeExclude:\n  - '%s'\n" "$3" >>"$2" ;;
frontend_test) . "$FAKE_MODE"; fake_mode frontend_test ;;
vulnerable)
    if grep -qxF -- "$4" "$CAP/vulnerable" 2>/dev/null; then echo 2.0.0; exit 0; fi
    exit "$(cat "$CAP/vulnerable-rc" 2>/dev/null || echo 1)" ;;
*) exit 2 ;;
esac
EOF

# --- 偽の backend-vuln-fix.sh: go_bump は go.mod の toolchain を上げ、digest はイメージの名前から作った値を出す。
# tree は CAP/tree-fail があれば失敗し、無ければ受け取ったファイルに fake tree と書く。vulnerable は、
# 依存の木のファイルが tree の書いたもので、範囲が空のときだけ、CAP/maven-vulnerable があれば 0 で、
# 無ければ CAP/vulnerable-rc の数(既定は 1)で終わる。vulncheck は CAP/vulncheck-fail があれば失敗し、
# 無ければ受け取ったファイルに fake vulncheck と書く。go_plan は、受け取ったファイルが vulncheck の
# 書いたものなら CAP/plan.json を出し、違えば 9 で終わる
FAKE_BVF="$WORK/fake-backend-vuln-fix.sh"
cat >"$FAKE_BVF" <<'EOF'
#!/usr/bin/env bash
printf '%s|%s\n' "$PWD" "$*" >>"$CAP/bvf.calls"
case "$1" in
go_bump)
    [ "$(cat "$CAP/bump-mode" 2>/dev/null)" != fail ] || exit 1
    sed -i -E "s/^toolchain go.*/toolchain go$2/" backend/go.mod ;;
digest)
    [ ! -f "$CAP/digest-fail" ] || exit 1
    printf 'sha256:%s\n' "$(printf '%s' "$2" | sha256sum | cut -c1-64)" ;;
tree)
    [ ! -f "$CAP/tree-fail" ] || exit 1
    echo "fake tree" >"$2" ;;
vulnerable)
    [ "$(cat "$2" 2>/dev/null)" = "fake tree" ] && [ -z "$4" ] || exit 9
    if [ -f "$CAP/maven-vulnerable" ]; then echo 1.2.2; exit 0; fi
    exit "$(cat "$CAP/vulnerable-rc" 2>/dev/null || echo 1)" ;;
vulncheck)
    [ ! -f "$CAP/vulncheck-fail" ] || exit 1
    echo "fake vulncheck" >"$2" ;;
go_plan)
    [ "$(cat "$2" 2>/dev/null)" = "fake vulncheck" ] || exit 9
    cat "$CAP/plan.json" ;;
*) exit 2 ;;
esac
EOF

# テストが期待する digest(偽の digest と同じ作り方)
fake_digest() { printf 'sha256:%s' "$(printf '%s' "$1" | sha256sum | cut -c1-64)"; }

HEX_B=$(printf 'b%.0s' $(seq 64))
HEX_C=$(printf 'c%.0s' $(seq 64))

# 使い方: new_case <場合の名前>
# 起点のコードのリポジトリを作ってコミットし、BASE・T・CAP・RT・TOP を決めて、環境変数を渡す
new_case() {
    TOP="$WORK/$1"
    T="$TOP/target"
    CAP="$TOP/cap"
    RT="$TOP/rt"
    mkdir -p "$T" "$CAP" "$RT"
    export CAP
    (
        cd "$T" || exit 1
        git init -q .
        mkdir -p backend/internal backend/src/main/java backend/gradle frontend/src docker/frontend docker/backend-go docs .github
        echo "apply from: 'gradle/quality.gradle'" >backend/build.gradle
        printf 'module example.com/app\n\ngo 1.25.0\n\ntoolchain go1.25.0\n' >backend/go.mod
        echo "example.com/base v1.0.0 h1:base=" >backend/go.sum
        printf 'package internal\n\nfunc App() {}\n' >backend/internal/app.go
        printf 'class A {\n}\n' >backend/src/main/java/A.java
        printf '{\n  "name": "app",\n  "dependencies": { "left": "1.0.0" }\n}\n' >frontend/package.json
        printf 'minimumReleaseAge: 4320\n' >frontend/pnpm-workspace.yaml
        printf "lockfileVersion: '9.0'\n" >frontend/pnpm-lock.yaml
        echo "export const a = 1;" >frontend/src/a.ts
        echo "dist" >frontend/.prettierignore
        printf 'FROM node:22-alpine@sha256:%s AS base\nRUN echo base\nFROM alpine:3 AS tools\n' "$HEX_B" >docker/frontend/Dockerfile
        printf 'FROM golang:1.25.0-alpine@sha256:%s AS build\nRUN echo build\n' "$HEX_C" >docker/backend-go/Dockerfile
        echo "readme" >docs/readme.txt
        cp "$VERSIONS" .github/ci-tool-versions.json
        cp "$FAKE_GRADLEW" backend/gradlew && chmod 644 backend/gradlew
        git add -A && git commit -q -m base
    ) || { ng "$1: 起点のリポジトリを作れません"; return 1; }
    BASE=$(git -C "$T" rev-parse HEAD)
    : >"$RT/base.patch"
    export RUNNER_TEMP="$RT" CAF_TARGET_DIR="$T" CAF_CLAUDE_PATCH="$RT/claude.patch" \
        CAF_BASE_PATCH="$RT/base.patch" CAF_FINAL_PATCH="$RT/final.patch" \
        CAF_FRONTEND_VULN_FIX="$FAKE_FVF" CAF_BACKEND_VULN_FIX="$FAKE_BVF"
}

# 使い方: claude_change <target の中で動かすシェルの文>
# Claude の変更を作業のフォルダに書き、claude.patch に書き出してから、作業のフォルダを起点に戻す
claude_change() {
    (
        cd "$T" || exit 1
        eval "$1"
        git add -A
        git diff --cached --binary >"$CAF_CLAUDE_PATCH"
        git reset -q --hard HEAD
    ) || ng "Claude の変更を作れません"
}

# 使い方: run_apply <kind> <key> <detail>
run_apply() {
    (cd "$TOP" && bash "$SCRIPT" apply "$1" "$2" "$3" "$BASE") >"$CAP/out" 2>"$CAP/err"
    echo $? >"$CAP/rc"
}

# 使い方: run_mode <check|confirm> <kind> <key> <detail>。apply のあとの作業のフォルダで、その形を呼ぶ
run_mode() {
    (cd "$TOP" && bash "$SCRIPT" "$1" "$2" "$3" "$4" "$BASE") >"$CAP/out" 2>"$CAP/err"
    echo $? >"$CAP/rc"
}

# 使い方: expect_mode <説明> <outcome>。終わり方が 0 で、標準出力が outcome の1行だけであること
expect_mode() {
    expect_eq "$1" "$(cat "$CAP/rc")|$(cat "$CAP/out")" "0|outcome=$2"
}

# 使い方: reset_calls。偽物の呼び出しの記録を消す
reset_calls() { rm -f "$CAP"/*.calls; }

out() { cat "$CAP/out"; }
calls() { cat "$CAP/$1.calls" 2>/dev/null; }
patch_sha() { sha256sum <"$CAF_FINAL_PATCH" | cut -d' ' -f1; }

# 使い方: expect_ok <場合の名前> <areas の JSON> <cooldown>
# 標準出力が areas・sha256・cooldown の3行だけで、final.patch が起点から作り直したあとのコミットの差であること
expect_ok() {
    expect_eq "$1: 終わり方" "$(cat "$CAP/rc")" 0
    if [ ! -f "$CAF_FINAL_PATCH" ]; then
        ng "$1: final.patch がありません(標準エラー: $(cat "$CAP/err"))"
        return
    fi
    expect_eq "$1: 標準出力" "$(out)" "$(printf 'areas=%s\nsha256=%s\ncooldown=%s' "$2" "$(patch_sha)" "$3")"
    local head
    head=$(git -C "$T" rev-parse HEAD)
    if git -C "$T" diff --binary --no-ext-diff --no-textconv --no-color "$BASE" "$head" | cmp -s - "$CAF_FINAL_PATCH"; then
        ok "$1: final.patch は起点から作り直したあとのコミットまでの差"
    else
        ng "$1: final.patch が起点から作り直したあとのコミットまでの差と違う"
    fi
    expect_eq "$1: 作り直したあとのコミットの親は起点" "$(git -C "$T" rev-parse HEAD~1)" "$BASE"
}

# 使い方: expect_outcome <場合の名前> <outcome>
expect_outcome() {
    expect_eq "$1: 終わり方" "$(cat "$CAP/rc")" 0
    expect_eq "$1: 標準出力" "$(out)" "outcome=$2"
    if [ -e "$CAF_FINAL_PATCH" ]; then ng "$1: final.patch が残っている"; else ok "$1: final.patch を書かない"; fi
}

final_has() {
    if grep -qF -- "$2" "$CAF_FINAL_PATCH" 2>/dev/null; then ok "$1"; else ng "$1(final.patch に [$2] が無い)"; fi
}

NPM_DETAIL='{"name":"@scope/pkg","version":"2.0.1","ranges":["< 2.0.1"],"urgent":true,"alerts":[7]}'
NPM_KEY='@scope/pkg@2.0.1'
npm_registry() { echo '{"time":{"2.0.0":"2026-01-01T00:00:00.000Z","2.0.1":"2026-11-20T01:02:03.000Z"}}' >"$CAP/registry.json"; }
ADD_DEP="sed -i 's/\"left\": \"1.0.0\"/\"left\": \"1.0.0\", \"@scope\\/pkg\": \"2.0.1\"/' frontend/package.json"

if want ok; then
    echo "[ok] apply が最後の差分を final.patch に書き、変わった領域を areas に、SHA-256 を sha256 に出す"
    new_case ok
    claude_change "echo 'export const b = 2;' >>frontend/src/a.ts; echo '// fixed' >>backend/internal/app.go"
    echo stale >"$CAF_FINAL_PATCH"
    run_apply dependabot 12 '{}'
    expect_ok ok '["frontend","backend_go"]' false
    final_has "ok: Claude の変更が final.patch に入る" "+export const b = 2;"
    expect_eq "ok: pnpm を呼ばない" "$(calls pnpm)" ""
    expect_eq "ok: go を呼ばない" "$(calls go)" ""
    expect_eq "ok: vuln-fix を呼ばない" "$(calls fvf)$(calls bvf)" ""
fi

if want areas; then
    echo "[areas] backend/compat があり Java 版と Dockerfile を変えたとき、4つの領域を出す"
    new_case areas
    mkdir -p "$T/backend/compat" && echo compat >"$T/backend/compat/README" &&
        git -C "$T" add -A && git -C "$T" commit -q -m compat
    BASE=$(git -C "$T" rev-parse HEAD)
    claude_change "printf 'class A {\n  int x;\n}\n' >backend/src/main/java/A.java; sed -i 's/RUN echo build/RUN echo build2/' docker/backend-go/Dockerfile"
    run_apply dependabot 12 '{}'
    expect_ok areas '["backend_java","backend_go","backend_compat","dockerfile"]' true
    expect_eq "areas: FROM の行を変えないときは digest を読まない" "$(calls bvf)" ""
fi

if want plain; then
    echo "[plain] ふつうのコードだけを変えたとき cooldown=false を出す"
    new_case plain
    claude_change "echo more >>docs/readme.txt"
    run_apply codeql 5 '{}'
    expect_ok plain '[]' false
fi

if want cooldown-base; then
    echo "[cooldown-base] base.patch が依存の版を宣言するファイルを変えたとき cooldown=true を出す"
    new_case cooldown-base
    (cd "$T" && sed -i 's/1.0.0/1.0.1/' frontend/package.json && git diff --binary >"$CAF_BASE_PATCH" &&
        git add -A && git commit -q -m dependabot) || ng "cooldown-base: base.patch を作れません"
    BASE=$(git -C "$T" rev-parse HEAD)
    claude_change "echo more >>docs/readme.txt"
    run_apply dependabot 12 '{}'
    expect_ok cooldown-base '[]' true
fi

if want cooldown-rename; then
    echo "[cooldown-rename] base.patch の名前の変更の元のパスも cooldown の判定に入れる"
    new_case cooldown-rename
    (cd "$T" && git mv backend/go.sum backend/go2.sum && git diff --cached -M --binary >"$CAF_BASE_PATCH" &&
        git commit -q -m rename) || ng "cooldown-rename: base.patch を作れません"
    grep -q '^rename from backend/go.sum' "$CAF_BASE_PATCH" || ng "cooldown-rename: base.patch が名前の変更の形ではない"
    BASE=$(git -C "$T" rev-parse HEAD)
    claude_change "echo more >>docs/readme.txt"
    run_apply dependabot 12 '{}'
    expect_ok cooldown-rename '[]' true
fi

if want npm-wait; then
    echo "[npm-wait] 種類が npm で decide が wait を返せば blocked になる"
    new_case npm-wait
    npm_registry
    echo wait >"$CAP/decide"
    claude_change "$ADD_DEP"
    echo stale >"$CAF_FINAL_PATCH"
    run_apply npm "$NPM_KEY" "$NPM_DETAIL"
    expect_outcome npm-wait blocked
    expect_eq "npm-wait: レジストリの URL" "$(calls curl | grep -o 'https://[^ ]*')" "https://registry.npmjs.org/@scope%2Fpkg"
    decide_call=$(calls fvf)
    case "$decide_call" in
    "$T|decide 2026-11-20T01:02:03.000Z "[0-9]*" true") ok "npm-wait: decide に公開日時・今の時刻・urgent を渡す" ;;
    *) ng "npm-wait: decide の呼び方(実際: [$decide_call])" ;;
    esac
    expect_eq "npm-wait: pnpm を呼ばない" "$(calls pnpm)" ""
fi

if want npm-exclude; then
    echo "[npm-exclude] decide が exclude を返せば exclude が呼ばれて除外の欄に足される"
    new_case npm-exclude
    npm_registry
    echo exclude >"$CAP/decide"
    claude_change "$ADD_DEP"
    run_apply npm "$NPM_KEY" "$NPM_DETAIL"
    expect_ok npm-exclude '["frontend"]' true
    expect_eq "npm-exclude: exclude の呼び方" "$(calls fvf | sed -n 2p)" "$T|exclude frontend/pnpm-workspace.yaml @scope/pkg@2.0.1"
    final_has "npm-exclude: 除外の欄に足した行が final.patch に入る" "+  - '@scope/pkg@2.0.1'"
    expect_eq "npm-exclude: pnpm の呼び方" "$(calls pnpm)" "$T/frontend|install --lockfile-only --no-frozen-lockfile --ignore-scripts --ignore-pnpmfile"
    final_has "npm-exclude: pnpm が作り直した lockfile が final.patch に入る" "+  lock-updated: true"
fi

if want npm-go; then
    echo "[npm-go] decide が go を返せば exclude を呼ばずに進む"
    new_case npm-go
    npm_registry
    echo go >"$CAP/decide"
    claude_change "$ADD_DEP"
    run_apply npm "$NPM_KEY" "$NPM_DETAIL"
    expect_ok npm-go '["frontend"]' true
    expect_eq "npm-go: exclude を呼ばない" "$(calls fvf | grep -c exclude)" 0
fi

if want npm-unreadable; then
    echo "[npm-unreadable] 公開日時を読めなければ unfixed になり、decide を呼ばない"
    new_case npm-unreadable
    echo fail >"$CAP/curl-mode"
    claude_change "$ADD_DEP"
    run_apply npm "$NPM_KEY" "$NPM_DETAIL"
    expect_outcome npm-unreadable unfixed
    expect_eq "npm-unreadable: decide を呼ばない" "$(calls fvf)" ""
fi

if want pnpm-mature; then
    echo "[pnpm-mature] 偽の pnpm が72時間の待ちのエラーを返せば blocked になる"
    new_case pnpm-mature
    echo mature >"$CAP/pnpm-mode"
    claude_change "$ADD_DEP"
    run_apply dependabot 12 '{}'
    expect_outcome pnpm-mature blocked
fi

if want pnpm-fail; then
    echo "[pnpm-fail] pnpm がほかの理由で失敗すれば unfixed になる"
    new_case pnpm-fail
    echo fail >"$CAP/pnpm-mode"
    claude_change "$ADD_DEP"
    run_apply dependabot 12 '{}'
    expect_outcome pnpm-fail unfixed
fi

if want pnpm-skip; then
    echo "[pnpm-skip] package.json と pnpm-workspace.yaml を変えなければ pnpm を呼ばない"
    new_case pnpm-skip
    claude_change "echo 'export const c = 3;' >>frontend/src/a.ts"
    run_apply codeql 5 '{}'
    expect_ok pnpm-skip '["frontend"]' false
    expect_eq "pnpm-skip: pnpm を呼ばない" "$(calls pnpm)" ""
fi

if want go-tidy; then
    echo "[go-tidy] backend/go.mod を変えたとき go mod tidy を動かし、cooldown=true を出す"
    new_case go-tidy
    claude_change "printf '\nrequire example.com/m v1.2.3\n' >>backend/go.mod"
    run_apply go-module 'example.com/m@v1.2.3' '{"module":"example.com/m","version":"v1.2.3"}'
    expect_ok go-tidy '["backend_go"]' true
    expect_eq "go-tidy: go の呼び方" "$(calls go)" "$T/backend|auto|mod tidy"
    final_has "go-tidy: 作り直した go.sum が final.patch に入る" "+example.com/m v1.2.3 h1:tidied="
fi

if want go-tidy-fail; then
    echo "[go-tidy-fail] go mod tidy が失敗すれば unfixed になる"
    new_case go-tidy-fail
    echo fail >"$CAP/go-mode"
    claude_change "printf '\nrequire example.com/m v1.2.3\n' >>backend/go.mod"
    run_apply go-module 'example.com/m@v1.2.3' '{"module":"example.com/m","version":"v1.2.3"}'
    expect_outcome go-tidy-fail unfixed
fi

if want go-stdlib; then
    echo "[go-stdlib] 種類が go-stdlib で go_bump が呼ばれる"
    new_case go-stdlib
    claude_change "echo '// stdlib' >>backend/internal/app.go"
    run_apply go-stdlib 1.25.3 '{"version":"1.25.3"}'
    expect_ok go-stdlib '["backend_go"]' true
    expect_eq "go-stdlib: go_bump の呼び方" "$(calls bvf)" "$T|go_bump 1.25.3"
    final_has "go-stdlib: go_bump が上げた toolchain が final.patch に入る" "+toolchain go1.25.3"
    expect_eq "go-stdlib: Claude が go.mod を変えないときは go mod tidy を呼ばない" "$(calls go)" ""
fi

if want go-bump-fail; then
    echo "[go-bump-fail] go_bump が失敗すれば unfixed になる"
    new_case go-bump-fail
    echo fail >"$CAP/bump-mode"
    claude_change "echo '// stdlib' >>backend/internal/app.go"
    run_apply go-stdlib 1.25.3 '{"version":"1.25.3"}'
    expect_outcome go-bump-fail unfixed
fi

if want digest; then
    echo "[digest] Dockerfile の FROM の行を digest の無いタグに変えたとき偽の digest で @sha256: が足される"
    new_case digest
    claude_change "printf 'FROM node:24-alpine AS base\nRUN echo base\nFROM alpine:3 AS tools\nFROM --platform=linux/arm64 nginx:1.29 AS web\nFROM base AS final\nFROM scratch\nFROM busybox:1.37@sha256:$HEX_B AS pinned\n' >docker/frontend/Dockerfile"
    run_apply container CVE-2026-0001 '{"id":"CVE-2026-0001"}'
    expect_ok digest '["dockerfile"]' true
    expect_eq "digest: 変えた FROM の行に digest を足し、ほかの行と digest を書いた行はそのまま" "$(cat "$T/docker/frontend/Dockerfile")" \
        "$(printf 'FROM node:24-alpine@%s AS base\nRUN echo base\nFROM alpine:3 AS tools\nFROM --platform=linux/arm64 nginx:1.29@%s AS web\nFROM base AS final\nFROM scratch\nFROM busybox:1.37@sha256:%s AS pinned' \
            "$(fake_digest node:24-alpine)" "$(fake_digest nginx:1.29)" "$HEX_B")"
    expect_eq "digest: digest を読むのはタグを書いたイメージだけ" "$(calls bvf)" \
        "$(printf '%s|digest node:24-alpine\n%s|digest nginx:1.29' "$T" "$T")"
fi

if want digest-fail; then
    echo "[digest-fail] digest を読めなければ unfixed になる"
    new_case digest-fail
    : >"$CAP/digest-fail"
    claude_change "sed -i 's/^FROM node:22-alpine@sha256:[0-9a-f]*/FROM node:24-alpine/' docker/frontend/Dockerfile"
    run_apply container CVE-2026-0001 '{"id":"CVE-2026-0001"}'
    expect_outcome digest-fail unfixed
fi

if want guard; then
    echo "[guard] ガードが0以外のとき unfixed になる"
    new_case guard
    claude_change "printf 'class A {\n  @SuppressWarnings(\"x\")\n  void f() {}\n}\n' >backend/src/main/java/A.java"
    run_apply maven 'org.example:lib@1.2.3' '{"name":"org.example:lib","version":"1.2.3"}'
    expect_outcome guard unfixed
    if grep -q 'SuppressWarnings' "$CAP/err"; then
        ok "guard: ガードが見つけた行を標準エラーに出す"
    else
        ng "guard: ガードの出力が標準エラーに無い"
    fi
fi

if want guard-derived; then
    echo "[guard-derived] 派生のファイルを作り直したあとの差にもガードを掛ける"
    new_case guard-derived
    echo ignorefile >"$CAP/pnpm-mode"
    claude_change "$ADD_DEP"
    run_apply dependabot 12 '{}'
    expect_outcome guard-derived unfixed
    expect_eq "guard-derived: pnpm は呼ばれた" "$(calls pnpm | wc -l | tr -d ' ')" 1
fi

if want noapply; then
    echo "[noapply] claude.patch を起点のコードに当てられなければ unfixed になる"
    new_case noapply
    printf 'diff --git a/nothing.txt b/nothing.txt\n--- a/nothing.txt\n+++ b/nothing.txt\n@@ -1 +1 @@\n-old\n+new\n' >"$CAF_CLAUDE_PATCH"
    run_apply dependabot 12 '{}'
    expect_outcome noapply unfixed
fi

if want filters; then
    echo "[filters] 領域の見分けが ci.yaml の detect-changes ジョブの filters と同じである"
    if ! command -v yq >/dev/null 2>&1; then
        ng "filters: yq がありません"
    else
        ci_json=$(yq -r '.jobs."detect-changes".steps[] | select(.id == "filter") | .with.filters' "$CI_YAML" | yq -o=json '.')
        expect_eq "filters: ci.yaml の見分けの名前は backend と5つの領域" \
            "$(jq -r 'keys_unsorted | map(select(. != "backend")) | join(" ")' <<<"$ci_json")" \
            "frontend backend_java backend_go backend_compat dockerfile"
        ci_lines=$(jq -r 'to_entries[] | select(.key != "backend") | .key as $k | .value[] | "\($k) \(.)"' <<<"$ci_json")
        script_lines=$(bash -c '. "$1" && printf "%s\n" "${CAF_AREA_FILTERS[@]}"' _ "$SCRIPT")
        expect_eq "filters: スクリプトの見分けの形が ci.yaml と同じ" "$script_lines" "$ci_lines"
        decide_run=$(yq -r '.jobs."detect-changes".steps[] | select(.id == "backend") | .run' "$CI_YAML")
        # caf_areas が写した、backend_go と backend_compat を決める2つの条件の行(ci.yaml の Decide backend jobs の手順)
        while IFS='|' read -r label line; do
            if grep -qxF -- "$line" <(sed -E 's/^[[:space:]]+//' <<<"$decide_run"); then
                ok "filters: ci.yaml の ${label} を決める条件が caf_areas と同じ"
            else
                ng "filters: ci.yaml の ${label} を決める条件が変わった(caf_areas を見直す)"
            fi
        done <<'LINES'
backend_go|if [ "$GO_FILES" = true ] && [ -f backend/go.mod ]; then
backend_compat|if [ -d backend/compat ] && { [ "$JAVA_FILES" = true ] || [ "$GO_FILES" = true ] || [ "$COMPAT_FILES" = true ]; }; then
LINES
    fi
fi

# 使い方: areas_of <起点のフォルダ> <パス>...
areas_of() {
    local dir="$1" list="$WORK/globs-list"
    shift
    printf '%s\0' "$@" >"$list"
    bash -c '. "$1" && caf_areas "$2" "$3"' _ "$SCRIPT" "$dir" "$list"
}

if want globs; then
    echo "[globs] 領域の見分けが paths-filter の glob と同じに当たる"
    G="$WORK/globs"
    mkdir -p "$G/go/backend" "$G/nogo/backend" "$G/compat/backend/compat" "$G/compatnogo/backend/compat"
    : >"$G/go/backend/go.mod"
    : >"$G/compat/backend/go.mod"
    expect_eq "globs: backend/x.gradle は backend_java" "$(areas_of "$G/go" backend/x.gradle)" '["backend_java"]'
    expect_eq "globs: backend/sub/x.gradle はどれにも当たらない" "$(areas_of "$G/go" backend/sub/x.gradle)" '[]'
    expect_eq "globs: backend/gradlew.bat は backend_java" "$(areas_of "$G/go" backend/gradlew.bat)" '["backend_java"]'
    expect_eq "globs: backend/main.go は backend_go" "$(areas_of "$G/go" backend/main.go)" '["backend_go"]'
    expect_eq "globs: backend/a/b/c.go は backend_go" "$(areas_of "$G/go" backend/a/b/c.go)" '["backend_go"]'
    expect_eq "globs: backend/.golangci.yml は backend_go" "$(areas_of "$G/go" backend/.golangci.yml)" '["backend_go"]'
    expect_eq "globs: backend/main.gox はどれにも当たらない" "$(areas_of "$G/go" backend/main.gox)" '[]'
    expect_eq "globs: go.mod が無ければ backend_go にしない" "$(areas_of "$G/nogo" backend/main.go)" '[]'
    expect_eq "globs: docker/a/b/Dockerfile.prod は dockerfile" "$(areas_of "$G/go" docker/a/b/Dockerfile.prod)" '["dockerfile"]'
    expect_eq "globs: docker/Dockerfile は dockerfile" "$(areas_of "$G/go" docker/Dockerfile)" '["dockerfile"]'
    expect_eq "globs: docker/a/NotDockerfile はどれにも当たらない" "$(areas_of "$G/go" docker/a/NotDockerfile)" '[]'
    expect_eq "globs: docker/backend-go/Dockerfile は backend_go と dockerfile" \
        "$(areas_of "$G/go" docker/backend-go/Dockerfile)" '["backend_go","dockerfile"]'
    expect_eq "globs: frontendx/a はどれにも当たらない" "$(areas_of "$G/go" frontendx/a)" '[]'
    expect_eq "globs: frontend/.npmrc は frontend" "$(areas_of "$G/go" frontend/.npmrc)" '["frontend"]'
    expect_eq "globs: backend/compat があり Java 版を変えれば backend_compat も" \
        "$(areas_of "$G/compat" backend/src/x.java)" '["backend_java","backend_compat"]'
    expect_eq "globs: backend/compat があっても3つに当たらなければ backend_compat にしない" \
        "$(areas_of "$G/compat" docs/x.md)" '[]'
    expect_eq "globs: go.mod が無くても Go 版のファイルに当たれば backend_compat にする(ci.yaml と同じ)" \
        "$(areas_of "$G/compatnogo" backend/main.go)" '["backend_compat"]'
    expect_eq "globs: 空白を含むパス" "$(areas_of "$G/go" 'frontend/a b.ts')" '["frontend"]'
fi

if want usage; then
    echo "[usage] 引数と環境の誤りは 2 で終わる"
    new_case usage
    claude_change "echo more >>docs/readme.txt"
    (cd "$TOP" && bash "$SCRIPT") >/dev/null 2>&1
    expect_eq "usage: 引数が無い" "$?" 2
    (cd "$TOP" && bash "$SCRIPT" bogus dependabot 12 '{}' "$BASE") >/dev/null 2>&1
    expect_eq "usage: 知らない形" "$?" 2
    (cd "$TOP" && bash "$SCRIPT" apply bogus 12 '{}' "$BASE") >/dev/null 2>&1
    expect_eq "usage: 知らない種類" "$?" 2
    (cd "$TOP" && bash "$SCRIPT" apply npm "$NPM_KEY" 'not json' "$BASE") >/dev/null 2>&1
    expect_eq "usage: npm の組が JSON でない" "$?" 2
    (cd "$TOP" && bash "$SCRIPT" apply go-stdlib 'go1.25.3; rm' '{}' "$BASE") >/dev/null 2>&1
    expect_eq "usage: go-stdlib の版の形が違う" "$?" 2
    (cd "$TOP" && CAF_BASE_PATCH="$RT/none.patch" bash "$SCRIPT" apply dependabot 12 '{}' "$BASE") >/dev/null 2>&1
    expect_eq "usage: base.patch が無い" "$?" 2
    git -C "$T" -c user.name=t -c user.email=t@example.com -c commit.gpgsign=false commit -q --allow-empty -m moved
    (cd "$TOP" && bash "$SCRIPT" apply dependabot 12 '{}' "$BASE") >/dev/null 2>&1
    expect_eq "usage: 作業のフォルダの HEAD が起点のコミットでない" "$?" 2
    git -C "$T" reset -q --hard "$BASE"
    echo dirty >>"$T/docs/readme.txt"
    (cd "$TOP" && bash "$SCRIPT" apply dependabot 12 '{}' "$BASE") >/dev/null 2>&1
    expect_eq "usage: 作業のフォルダが起点のコミットのままでない" "$?" 2
    expect_eq "usage: 誤りのときは何も書かない" "$(git -C "$T" rev-parse HEAD)" "$BASE"
fi

# ---------------------------------------------------------------------
# check の形
# ---------------------------------------------------------------------

if want check-areas; then
    echo "[check-areas] check が apply と同じ領域を決め直し、その領域の品質チェックだけを、トークンを外して流す"
    new_case check-areas
    claude_change "echo 'export const b = 2;' >>frontend/src/a.ts; echo '// fixed' >>backend/internal/app.go"
    run_apply dependabot 12 '{}'
    expect_ok check-areas '["frontend","backend_go"]' false
    (
        export GH_TOKEN=secret GITHUB_TOKEN=secret2
        CAF_CLAUDE_PATCH="$RT/none.patch" CAF_BASE_PATCH="$RT/none.patch" run_mode check dependabot 12 '{}'
    )
    expect_mode "check-areas: claude.patch と base.patch が無くても、通れば ok" ok
    expect_eq "check-areas: frontend の品質チェック" "$(calls fvf)" "$T|frontend_test"
    expect_eq "check-areas: backend_go の品質チェック" "$(calls make)" \
        "$(printf '%s|check|\n%s|mutation-diff BASE=origin/main|' "$T/backend" "$T/backend")"
    expect_eq "check-areas: 変わっていない領域の品質チェックを流さない" "$(calls gradlew)$(calls docker)" ""
    expect_eq "check-areas: e2e-smoke も pnpm も呼ばない" "$(calls pnpm)" ""
    expect_eq "check-areas: 品質チェックに GitHub のトークンを渡さない" "$(calls token)" ""
    if grep -qF 'CHECK-OUTPUT frontend_test' "$CAP/err"; then
        ok "check-areas: 品質チェックの出力を標準エラーに出す"
    else
        ng "check-areas: 品質チェックの出力が標準エラーに無い"
    fi
fi

# 使い方: all_areas_case <場合の名前>。5つの領域を変える Claude の変更で apply まで動かす
all_areas_case() {
    new_case "$1"
    mkdir -p "$T/backend/compat" && echo compat >"$T/backend/compat/README" &&
        git -C "$T" add -A && git -C "$T" commit -q -m compat
    BASE=$(git -C "$T" rev-parse HEAD)
    claude_change "printf 'class A {\n  int x;\n}\n' >backend/src/main/java/A.java; echo '// go' >>backend/internal/app.go
        echo 'export const b = 2;' >>frontend/src/a.ts; sed -i 's/RUN echo base/RUN echo base2/' docker/frontend/Dockerfile
        mkdir -p docker/backend && printf 'FROM eclipse-temurin:21@sha256:$HEX_B\n' >docker/backend/Dockerfile.prod
        printf 'FROM alpine:3@sha256:$HEX_B\n' >docker/backend-go/Dockerfile.prod
        rm docker/backend-go/Dockerfile"
    run_apply dependabot 12 '{}'
    expect_ok "$1" '["frontend","backend_java","backend_go","backend_compat","dockerfile"]' true
    reset_calls
}

if want check-all; then
    echo "[check-all] 5つの領域ごとに設計の品質チェックが呼ばれ、e2e-smoke は呼ばれない"
    all_areas_case check-all
    run_mode check dependabot 12 '{}'
    expect_mode "check-all: 通れば ok" ok
    expect_eq "check-all: frontend は frontend_test を最上位で" "$(calls fvf)" "$T|frontend_test"
    expect_eq "check-all: backend_java は gradlew check を backend で(実行の権限を付けて)" "$(calls gradlew)" \
        "$T/backend|check --configuration-cache"
    expect_eq "check-all: backend_go と backend_compat は make を backend で、compat には KEIREKIPRO_REPO_ROOT を付けて" \
        "$(calls make)" "$(printf '%s|check|\n%s|mutation-diff BASE=origin/main|\n%s|compat|%s\n%s|compat-cross|%s' \
            "$T/backend" "$T/backend" "$T/backend" "$T" "$T/backend" "$T")"
    expect_eq "check-all: dockerfile は残っている Dockerfile ごとに docker-smoke と同じ文脈で、トークンを渡さずに" \
        "$(calls docker)" "$(printf '%s|build --file docker/backend-go/Dockerfile.prod ./backend\n%s|build --file docker/backend/Dockerfile.prod ./backend\n%s|build --file docker/frontend/Dockerfile .' \
            "$T" "$T" "$T")"
    expect_eq "check-all: e2e-smoke も pnpm も呼ばない" "$(calls pnpm)" ""
fi

if want check-fail; then
    echo "[check-fail] 品質チェックが失敗か打ち切りなら unfixed になる"
    all_areas_case check-fail
    for name in frontend_test gradlew make-check make-mutation-diff make-compat make-compat-cross docker; do
        for m in fail kill; do
            echo "$m" >"$CAP/mode-$name"
            run_mode check dependabot 12 '{}'
            expect_mode "check-fail: ${name} が ${m} なら unfixed" unfixed
            rm -f "$CAP/mode-$name"
        done
    done
fi

if want check-none; then
    echo "[check-none] 領域に当たる変更が無ければ、品質チェックを流さずに ok になる"
    new_case check-none
    claude_change "echo more >>docs/readme.txt"
    run_apply dependabot 12 '{}'
    expect_ok check-none '[]' false
    run_mode check dependabot 12 '{}'
    expect_mode "check-none: ok" ok
    expect_eq "check-none: 品質チェックを流さない" "$(calls fvf)$(calls gradlew)$(calls make)$(calls docker)$(calls pnpm)" ""
fi

if want check-restore; then
    echo "[check-restore] 品質チェックが作業のフォルダを変えても、check は最後の差分の木に戻して終わる"
    new_case check-restore
    claude_change "echo 'export const b = 2;' >>frontend/src/a.ts"
    run_apply dependabot 12 '{}'
    echo touch >"$CAP/mode-frontend_test"
    echo before >>"$T/docs/readme.txt"
    run_mode check dependabot 12 '{}'
    expect_mode "check-restore: ok" ok
    expect_eq "check-restore: 追跡するファイルを戻す" "$(cat "$T/docs/readme.txt")" readme
    expect_eq "check-restore: 追跡しないファイルと無視するファイルを消す" \
        "$(git -C "$T" status --porcelain --ignored)" ""
    expect_eq "check-restore: 品質チェックの前にも、最後の差分の木に戻す" "$(cat "$CAP/seen-frontend_test" 2>/dev/null)" readme
fi

if want check-codeql; then
    echo "[check-codeql] 種類が codeql のとき、品質チェックの出力を標準出力と標準エラーに出さず、記録のファイルに書く"
    new_case check-codeql
    claude_change "echo 'export const b = 2;' >>frontend/src/a.ts"
    run_apply codeql 5 '{}'
    expect_ok check-codeql '["frontend"]' false
    run_mode check codeql 5 '{}'
    expect_mode "check-codeql: 通れば標準出力は outcome=ok だけ" ok
    expect_eq "check-codeql: 標準エラーに何も出さない" "$(cat "$CAP/err")" ""
    if grep -qF 'CHECK-OUTPUT frontend_test' "$RT/claude-auto-fix-verify.log" &&
        grep -qF 'CHECK-ERROR frontend_test' "$RT/claude-auto-fix-verify.log"; then
        ok "check-codeql: 品質チェックの出力を記録のファイルに書く"
    else
        ng "check-codeql: 品質チェックの出力が記録のファイルに無い"
    fi
    echo fail >"$CAP/mode-frontend_test"
    run_mode check codeql 5 '{}'
    expect_mode "check-codeql: 失敗すれば標準出力は outcome=unfixed だけ" unfixed
    expect_eq "check-codeql: 失敗しても標準エラーに何も出さない" "$(cat "$CAP/err")" ""
fi

if want check-usage; then
    echo "[check-usage] final.patch を読めないか起点のコミットに当てられなければ 2 で終わる"
    new_case check-usage
    claude_change "echo 'export const b = 2;' >>frontend/src/a.ts"
    run_apply dependabot 12 '{}'
    CAF_FINAL_PATCH="$RT/none.patch" run_mode check dependabot 12 '{}'
    expect_eq "check-usage: final.patch が無い" "$(cat "$CAP/rc")" 2
    printf 'diff --git a/nothing.txt b/nothing.txt\n--- a/nothing.txt\n+++ b/nothing.txt\n@@ -1 +1 @@\n-old\n+new\n' >"$RT/bad.patch"
    CAF_FINAL_PATCH="$RT/bad.patch" run_mode check dependabot 12 '{}'
    expect_eq "check-usage: final.patch が起点のコミットに当たらない" "$(cat "$CAP/rc")" 2
    expect_eq "check-usage: 誤りのときは品質チェックを流さない" "$(calls fvf)" ""
fi

# ---------------------------------------------------------------------
# confirm の形
# ---------------------------------------------------------------------

NPM_DETAIL2='{"name":"@scope/pkg","version":"2.0.1","ranges":["< 1.5.0",">= 2.0.0, < 2.0.1"],"urgent":true,"alerts":[7]}'

if want confirm-npm; then
    echo "[confirm-npm] npm では vulnerable が範囲に入る版が残ると返せば unfixed、無いと返せば ok になる"
    new_case confirm-npm
    npm_registry
    echo go >"$CAP/decide"
    claude_change "$ADD_DEP"
    run_apply npm "$NPM_KEY" "$NPM_DETAIL2"
    expect_ok confirm-npm '["frontend"]' true
    reset_calls
    run_mode confirm npm "$NPM_KEY" "$NPM_DETAIL2"
    expect_mode "confirm-npm: どの範囲の版も残らなければ ok" ok
    expect_eq "confirm-npm: 範囲ごとに lockfile を調べる" "$(calls fvf)" \
        "$(printf '%s|vulnerable frontend/pnpm-lock.yaml @scope/pkg < 1.5.0\n%s|vulnerable frontend/pnpm-lock.yaml @scope/pkg >= 2.0.0, < 2.0.1' "$T" "$T")"
    echo '>= 2.0.0, < 2.0.1' >"$CAP/vulnerable"
    run_mode confirm npm "$NPM_KEY" "$NPM_DETAIL2"
    expect_mode "confirm-npm: 2つ目の範囲の版が残れば unfixed" unfixed
    rm -f "$CAP/vulnerable"
    echo 3 >"$CAP/vulnerable-rc"
    run_mode confirm npm "$NPM_KEY" "$NPM_DETAIL2"
    expect_mode "confirm-npm: vulnerable が 0 と 1 のほかで終われば unfixed" unfixed
    rm -f "$CAP/vulnerable-rc"
    run_mode confirm npm "$NPM_KEY" '{"name":"@scope/pkg","version":"2.0.1","ranges":[],"urgent":true}'
    expect_eq "confirm-npm: 範囲が空なら 2 で終わる" "$(cat "$CAP/rc")" 2
fi

if want confirm-nolock; then
    echo "[confirm-nolock] npm で lockfile が無ければ unfixed になる"
    new_case confirm-nolock
    git -C "$T" rm -q frontend/pnpm-lock.yaml && git -C "$T" commit -q -m nolock
    BASE=$(git -C "$T" rev-parse HEAD)
    npm_registry
    echo go >"$CAP/decide"
    claude_change "echo 'export const b = 2;' >>frontend/src/a.ts"
    run_apply npm "$NPM_KEY" "$NPM_DETAIL2"
    expect_ok confirm-nolock '["frontend"]' false
    reset_calls
    run_mode confirm npm "$NPM_KEY" "$NPM_DETAIL2"
    expect_mode "confirm-nolock: unfixed" unfixed
    expect_eq "confirm-nolock: vulnerable を呼ばない" "$(calls fvf)" ""
fi

MAVEN_KEY='org.example:lib@1.2.3'
MAVEN_DETAIL='{"name":"org.example:lib","version":"1.2.3","ranges":["< 1.2.3"],"urgent":false,"alerts":[3]}'

if want confirm-maven; then
    echo "[confirm-maven] maven では tree と vulnerable が範囲に入る版が残ると返せば unfixed、無いと返せば ok になる"
    new_case confirm-maven
    claude_change "printf 'class A {\n  int y;\n}\n' >backend/src/main/java/A.java"
    run_apply maven "$MAVEN_KEY" "$MAVEN_DETAIL"
    expect_ok confirm-maven '["backend_java"]' false
    reset_calls
    run_mode confirm maven "$MAVEN_KEY" "$MAVEN_DETAIL"
    expect_mode "confirm-maven: 残らなければ ok" ok
    bvf_calls=$(calls bvf)
    tree_file=$(sed -n '1s/^.*|tree //p' <<<"$bvf_calls")
    case "$tree_file" in
    "$RT"/*) ok "confirm-maven: 依存の木を一時のフォルダに書き出す" ;;
    *) ng "confirm-maven: tree の呼び方(実際: [$bvf_calls])" ;;
    esac
    expect_eq "confirm-maven: tree を作業のフォルダの最上位で呼び、その木で組の範囲を調べる" "$bvf_calls" \
        "$(printf '%s|tree %s\n%s|vulnerable %s org.example:lib  %s' "$T" "$tree_file" "$T" "$tree_file" "$MAVEN_DETAIL")"
    : >"$CAP/maven-vulnerable"
    run_mode confirm maven "$MAVEN_KEY" "$MAVEN_DETAIL"
    expect_mode "confirm-maven: 範囲に入る版が残れば unfixed" unfixed
    rm -f "$CAP/maven-vulnerable"
    echo 3 >"$CAP/vulnerable-rc"
    run_mode confirm maven "$MAVEN_KEY" "$MAVEN_DETAIL"
    expect_mode "confirm-maven: vulnerable が 0 と 1 のほかで終われば unfixed" unfixed
    rm -f "$CAP/vulnerable-rc"
    : >"$CAP/tree-fail"
    reset_calls
    run_mode confirm maven "$MAVEN_KEY" "$MAVEN_DETAIL"
    expect_mode "confirm-maven: 依存の木を書き出せなければ unfixed" unfixed
    expect_eq "confirm-maven: 依存の木が無ければ vulnerable を呼ばない" "$(calls bvf | grep -c vulnerable)" 0
    rm -f "$CAP/tree-fail"
    run_mode confirm maven "$MAVEN_KEY" '{"name":"org.example:lib","version":"1.2.3"}'
    expect_eq "confirm-maven: 範囲が無ければ 2 で終わる" "$(cat "$CAP/rc")" 2
fi

STDLIB_DETAIL='{"version":"1.25.3","osv":["GO-2026-0001"]}'

if want confirm-stdlib; then
    echo "[confirm-stdlib] go-stdlib では go_plan の .stdlib が null なら ok、残れば unfixed になる"
    new_case confirm-stdlib
    claude_change "echo '// stdlib' >>backend/internal/app.go"
    run_apply go-stdlib 1.25.3 "$STDLIB_DETAIL"
    expect_ok confirm-stdlib '["backend_go"]' true
    reset_calls
    echo '{"stdlib":null,"modules":[{"module":"example.com/x","version":"v1.0.1","osv":["GO-1"]}],"nofix":[]}' >"$CAP/plan.json"
    run_mode confirm go-stdlib 1.25.3 "$STDLIB_DETAIL"
    expect_mode "confirm-stdlib: .stdlib が null なら、部品が残っていても ok" ok
    vc_file=$(calls bvf | sed -n '1s/^.*|vulncheck //p')
    expect_eq "confirm-stdlib: vulncheck の結果を go_plan に渡す" "$(calls bvf)" \
        "$(printf '%s|vulncheck %s\n%s|go_plan %s' "$T" "$vc_file" "$T" "$vc_file")"
    echo '{"stdlib":{"version":"1.25.4","osv":["GO-2026-0002"]},"modules":[],"nofix":[]}' >"$CAP/plan.json"
    run_mode confirm go-stdlib 1.25.3 "$STDLIB_DETAIL"
    expect_mode "confirm-stdlib: .stdlib が残れば unfixed" unfixed
    echo 'not json' >"$CAP/plan.json"
    run_mode confirm go-stdlib 1.25.3 "$STDLIB_DETAIL"
    expect_mode "confirm-stdlib: go_plan の結果を読めなければ unfixed" unfixed
    : >"$CAP/vulncheck-fail"
    reset_calls
    run_mode confirm go-stdlib 1.25.3 "$STDLIB_DETAIL"
    expect_mode "confirm-stdlib: vulncheck が失敗すれば unfixed" unfixed
    expect_eq "confirm-stdlib: vulncheck が失敗すれば go_plan を呼ばない" "$(calls bvf | grep -c go_plan)" 0
fi

MODULE_KEY='example.com/m@v1.2.3'
MODULE_DETAIL='{"module":"example.com/m","version":"v1.2.3","osv":["GO-2026-0003"]}'

if want confirm-module; then
    echo "[confirm-module] go-module では go_plan の .modules にその部品が無ければ ok、あれば unfixed になる"
    new_case confirm-module
    claude_change "echo '// module' >>backend/internal/app.go"
    run_apply go-module "$MODULE_KEY" "$MODULE_DETAIL"
    expect_ok confirm-module '["backend_go"]' false
    echo '{"stdlib":{"version":"1.25.4","osv":["GO-2"]},"modules":[{"module":"example.com/other","version":"v2.0.0","osv":["GO-3"]}],"nofix":[]}' >"$CAP/plan.json"
    run_mode confirm go-module "$MODULE_KEY" "$MODULE_DETAIL"
    expect_mode "confirm-module: ほかの部品と標準ライブラリが残っていても、その部品が無ければ ok" ok
    echo '{"stdlib":null,"modules":[{"module":"example.com/m","version":"v1.2.4","osv":["GO-2026-0003"]}],"nofix":[]}' >"$CAP/plan.json"
    run_mode confirm go-module "$MODULE_KEY" "$MODULE_DETAIL"
    expect_mode "confirm-module: その部品が残れば unfixed" unfixed
    echo 'not json' >"$CAP/plan.json"
    run_mode confirm go-module "$MODULE_KEY" "$MODULE_DETAIL"
    expect_mode "confirm-module: go_plan の結果を読めなければ unfixed" unfixed
    : >"$CAP/vulncheck-fail"
    run_mode confirm go-module "$MODULE_KEY" "$MODULE_DETAIL"
    expect_mode "confirm-module: vulncheck が失敗すれば unfixed" unfixed
    rm -f "$CAP/vulncheck-fail"
    run_mode confirm go-module 'example.com/m' "$MODULE_DETAIL"
    expect_eq "confirm-module: key に @ が無ければ 2 で終わる" "$(cat "$CAP/rc")" 2
fi

# 使い方: sarif <ファイル> <結果の JSON>...。結果を1つの run に並べた SARIF を書く
sarif() {
    local f="$1"
    shift
    printf '{"version":"2.1.0","runs":[{"tool":{"driver":{"name":"CodeQL"}},"results":[%s]}]}\n' \
        "$(IFS=,; printf '%s' "$*")" >"$f"
}
# 使い方: result <規則の ID> <パス>
result() {
    printf '{"ruleId":"%s","message":{"text":"m"},"locations":[{"physicalLocation":{"artifactLocation":{"uri":"%s"}}}]}' "$1" "$2"
}

if want confirm-codeql; then
    echo "[confirm-codeql] codeql では SARIF に警告と同じ規則の ID の結果が同じファイルにあれば unfixed、無ければ ok になる"
    new_case confirm-codeql
    claude_change "echo 'export const b = 2;' >>frontend/src/a.ts"
    run_apply codeql 5 '{}'
    expect_ok confirm-codeql '["frontend"]' false
    echo '{"rule_id":"js/xss","path":"frontend/src/a.ts","category":"/language:javascript-typescript"}' >"$RT/codeql-alert.json"
    n=0
    # 使い方: codeql_case <説明> <outcome> <SARIF を今のフォルダに書く関数の名前>
    codeql_case() {
        n=$((n + 1))
        local dir="$TOP/sarif-$n"
        mkdir -p "$dir"
        (cd "$dir" && "$3")
        CODEQL_SARIF_DIR="$dir" run_mode confirm codeql 5 '{}'
        expect_mode "confirm-codeql: $1" "$2"
        expect_eq "confirm-codeql: $1(標準エラーに何も出さない)" "$(cat "$CAP/err")" ""
    }
    sarif_same() { sarif javascript.sarif "$(result js/other frontend/src/a.ts)" "$(result js/xss frontend/src/a.ts)"; }
    sarif_target() { sarif javascript.sarif "$(result js/xss target/frontend/src/a.ts)"; }
    sarif_rule_id() {
        sarif javascript.sarif '{"rule":{"id":"js/xss"},"locations":[{"physicalLocation":{"artifactLocation":{"uri":"frontend/src/a.ts"}}}]}'
    }
    sarif_second() {
        sarif actions.sarif "$(result js/xss frontend/src/b.ts)"
        sarif javascript.sarif "$(result js/xss frontend/src/a.ts)"
    }
    sarif_other_file() { sarif javascript.sarif "$(result js/xss frontend/src/b.ts)" "$(result js/xss target/frontend/src/a.ts.bak)"; }
    sarif_other_rule() { sarif javascript.sarif "$(result js/other frontend/src/a.ts)"; }
    sarif_no_results() {
        sarif javascript.sarif
        echo '{"version":"2.1.0","runs":[{"tool":{"driver":{"name":"CodeQL"}}}]}' >java.sarif
    }
    sarif_none() { :; }
    sarif_broken() {
        sarif javascript.sarif "$(result js/other frontend/src/b.ts)"
        echo "not json" >java.sarif
    }
    codeql_case "同じ規則の ID の結果が同じファイルにあれば unfixed" unfixed sarif_same
    codeql_case "結果のパスが target/ で始まるときも同じファイルとみなして unfixed" unfixed sarif_target
    codeql_case "規則の ID が rule.id に書かれた結果も比べて unfixed" unfixed sarif_rule_id
    codeql_case "2つ目の SARIF に同じ結果があれば unfixed" unfixed sarif_second
    codeql_case "同じ規則の ID の結果がほかのファイルにだけあれば ok" ok sarif_other_file
    codeql_case "同じファイルにほかの規則の結果だけがあれば ok" ok sarif_other_rule
    codeql_case "結果が無ければ ok" ok sarif_no_results
    codeql_case "SARIF が無ければ unfixed" unfixed sarif_none
    codeql_case "SARIF を JSON として読めなければ unfixed" unfixed sarif_broken
    run_mode confirm codeql 5 '{}'
    expect_eq "confirm-codeql: CODEQL_SARIF_DIR が無ければ 2 で終わる" "$(cat "$CAP/rc")" 2
    mv "$RT/codeql-alert.json" "$RT/codeql-alert.json.bak"
    CODEQL_SARIF_DIR="$TOP/sarif-1" run_mode confirm codeql 5 '{}'
    expect_eq "confirm-codeql: 警告のファイルが無ければ 2 で終わる" "$(cat "$CAP/rc")" 2
fi

if want confirm-other; then
    echo "[confirm-other] dependabot と container と red-check は、品質チェックに任せて ok にする。confirm も最後の差分の木に戻す"
    new_case confirm-other
    claude_change "echo 'export const b = 2;' >>frontend/src/a.ts"
    run_apply dependabot 12 '{}'
    expect_ok confirm-other '["frontend"]' false
    reset_calls
    echo tampered >>"$T/docs/readme.txt"
    echo junk >"$T/junk.txt"
    run_mode confirm dependabot 12 '{}'
    expect_mode "confirm-other: dependabot は ok" ok
    expect_eq "confirm-other: confirm は作業のフォルダを最後の差分の木に戻す" "$(git -C "$T" status --porcelain --ignored)" ""
    run_mode confirm container CVE-2026-0001 '{"id":"CVE-2026-0001"}'
    expect_mode "confirm-other: container は verify-image ジョブに任せて ok" ok
    echo '< 1.5.0' >"$CAP/vulnerable"
    CAF_REASON=red-check run_mode confirm npm "$NPM_KEY" "$NPM_DETAIL2"
    expect_mode "confirm-other: red-check は対象の種類によらず ok" ok
    expect_eq "confirm-other: dependabot・container・red-check では対象を調べない" "$(calls fvf)$(calls bvf)" ""
    CAF_REASON=trigger run_mode confirm npm "$NPM_KEY" "$NPM_DETAIL2"
    expect_mode "confirm-other: red-check でなければ npm の対象を調べて unfixed" unfixed
    CAF_FINAL_PATCH="$RT/none.patch" run_mode confirm dependabot 12 '{}'
    expect_eq "confirm-other: final.patch が無ければ 2 で終わる" "$(cat "$CAP/rc")" 2
fi

if [ "$RAN" -eq 0 ]; then
    echo "KP_TEST_CASE に知らない場合の名前があります: ${CASE}" >&2
    exit 1
fi
if [ "$FAILED" -ne 0 ]; then
    echo "test-claude-auto-fix-verify: 失敗があります" >&2
    exit 1
fi
echo "test-claude-auto-fix-verify: すべて通りました"
