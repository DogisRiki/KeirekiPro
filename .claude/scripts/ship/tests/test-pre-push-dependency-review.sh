#!/usr/bin/env bash
# =====================================================================
# pre-push-dependency-review.sh と pre-push-deps.pl のテスト
#
# 実行: bash .claude/scripts/ship/tests/test-pre-push-dependency-review.sh
# テストの場合ごとに、一時のフォルダに偽の git のリポジトリを作り、gh を偽物に替えて流す。
# 偽の gh は、ファイルに書いた答えを返すだけで、GitHub に問い合わせない。
# 前提: bash・git・perl
# =====================================================================
set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$(cd "$HERE/.." && pwd)/pre-push-dependency-review.sh"
DEPS="$(cd "$HERE/.." && pwd)/pre-push-deps.pl"
TMP_RAW=$(mktemp -d)
trap 'rm -rf "$TMP_RAW"' EXIT
# Windows の git には C:/... の形のパスを渡す。ほかの OS ではそのまま使う。
# PATH には、区切りの : を含まない元の形(/tmp/...)を足す
TMP_ROOT=$(cd "$TMP_RAW" && { pwd -W 2>/dev/null || pwd -P; })

pass=0
failn=0
ok() { pass=$((pass + 1)); printf 'ok   %s\n' "$1"; }
ng() { failn=$((failn + 1)); printf 'NG   %s\n' "$1"; }
check() { if [ "$2" = "$3" ]; then ok "$1"; else ng "$1 (want [$3] got [$2])"; fi; }
has() { if printf '%s' "$2" | grep -qF -- "$3"; then ok "$1"; else ng "$1 (出力に [$3] が無い)"; fi; }
hasnt() { if printf '%s' "$2" | grep -qF -- "$3"; then ng "$1 (出力に [$3] がある)"; else ok "$1"; fi; }

# 偽の gh。--jq の式で、名前を返す問い合わせか、脆弱性の行を返す問い合わせかを見分ける。
# STUB/fail があれば失敗する。呼ばれた引数を STUB/calls に1行ずつ書く
STUB="$TMP_RAW/stub"
mkdir -p "$STUB/bin"
cat >"$STUB/bin/gh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$STUB_DIR/calls"
if [ -f "$STUB_DIR/fail" ]; then echo "HTTP 503: Service Unavailable" >&2; exit 1; fi
case "$*" in
*package.name*) cat "$STUB_DIR/names" 2>/dev/null ;;
*) cat "$STUB_DIR/rows" 2>/dev/null ;;
esac
exit 0
EOF
chmod +x "$STUB/bin/gh"
export STUB_DIR="$STUB"
export PATH="$STUB/bin:$PATH"

# 偽のリポジトリを作り、go.mod に jwt 5.3.1 だけを書いた基準のコミットを作る
newcase() {
    rm -f "$STUB/calls" "$STUB/fail" "$STUB/names" "$STUB/rows"
    R="$TMP_ROOT/repo-$1"
    git init -q "$R"
    git -C "$R" config user.email t@example.com
    git -C "$R" config user.name t
    mkdir -p "$R/backend" "$R/frontend" "$R/backend/gradle"
    printf 'module example\n\ngo 1.25\n\nrequire github.com/golang-jwt/jwt/v5 v5.3.1\n' >"$R/backend/go.mod"
    git -C "$R" add -A
    git -C "$R" commit -q -m base
    BASE=$(git -C "$R" rev-parse HEAD)
}
run() { (cd "$R" && bash "$SCRIPT" "$@" 2>&1); }

# --- 増えた部品が無い -------------------------------------------------------------
newcase none
out=$(run --base "$BASE")
check "増えた部品が無いと通る" "$?" 0
has "増えた部品の数が0" "$out" "増えた部品: 0 組"
check "増えた部品が無いと gh を呼ばない" "$([ -f "$STUB/calls" ] && echo called || echo none)" none

# --- 増えた部品に high の脆弱性がある(commit した変更) ---------------------------
newcase high
printf 'module example\n\ngo 1.25\n\nrequire (\n\tgithub.com/golang-jwt/jwt/v5 v5.3.1\n\tgoogle.golang.org/grpc v1.80.0 // indirect\n)\n' >"$R/backend/go.mod"
git -C "$R" commit -q -am add-grpc
echo "google.golang.org/grpc" >"$STUB/names"
echo "GHSA-aaaa-bbbb-cccc high https://github.com/advisories/GHSA-aaaa-bbbb-cccc" >"$STUB/rows"
out=$(run --base "$BASE" --head HEAD)
check "high の脆弱性があると止まる" "$?" 1
has "止まった部品と脆弱性を書く" "$out" "gomod google.golang.org/grpc@1.80.0: GHSA-aaaa-bbbb-cccc(high)"
has "go.mod の部品を go の種類で問い合わせる" "$(cat "$STUB/calls")" "ecosystem=go"
has "版の先頭の v を落として問い合わせる" "$(cat "$STUB/calls")" "affects=google.golang.org/grpc@1.80.0"
hasnt "前からある部品は問い合わせない" "$(cat "$STUB/calls")" "golang-jwt"

# --- まだ commit していない変更も調べる ---------------------------------------------
newcase dirty
printf 'module example\n\ngo 1.25\n\nrequire (\n\tgithub.com/golang-jwt/jwt/v5 v5.3.1\n\tgithub.com/google/cel-go v0.28.0\n)\n' >"$R/backend/go.mod"
echo "github.com/google/cel-go" >"$STUB/names"
echo "GHSA-dddd-eeee-ffff medium https://github.com/advisories/GHSA-dddd-eeee-ffff" >"$STUB/rows"
out=$(run --base "$BASE")
check "commit していない変更の medium の脆弱性で止まる" "$?" 1
has "commit していない変更の部品を書く" "$out" "github.com/google/cel-go@0.28.0: GHSA-dddd-eeee-ffff(medium)"

# --- low だけなら止めない -------------------------------------------------------------
newcase low
printf 'module example\n\ngo 1.25\n\nrequire (\n\tgithub.com/golang-jwt/jwt/v5 v5.3.1\n\tgolang.org/x/text v0.3.0\n)\n' >"$R/backend/go.mod"
echo "golang.org/x/text" >"$STUB/names"
echo "GHSA-gggg-hhhh-iiii low https://github.com/advisories/GHSA-gggg-hhhh-iiii" >"$STUB/rows"
out=$(run --base "$BASE")
check "low の脆弱性だけなら通る" "$?" 0
has "low の脆弱性は止めないものとして書く" "$out" "止めない脆弱性"

# --- 一覧に名前が出ない部品は照らし直さない --------------------------------------------
newcase clean
printf 'module example\n\ngo 1.25\n\nrequire (\n\tgithub.com/golang-jwt/jwt/v5 v5.3.1\n\tgithub.com/example/safe v1.0.0\n)\n' >"$R/backend/go.mod"
: >"$STUB/names"
echo "GHSA-zzzz-zzzz-zzzz critical https://example.invalid" >"$STUB/rows"
out=$(run --base "$BASE")
check "一覧に名前が出なければ通る" "$?" 0
check "まとめた問い合わせの1回だけ呼ぶ" "$(grep -c . "$STUB/calls")" 1

# --- 一覧を読めない ----------------------------------------------------------------
newcase fail
printf 'module example\n\ngo 1.25\n\nrequire (\n\tgithub.com/golang-jwt/jwt/v5 v5.3.1\n\tgithub.com/example/x v1.0.0\n)\n' >"$R/backend/go.mod"
touch "$STUB/fail"
out=$(run --base "$BASE")
check "一覧を読めないと調べられなかったとする" "$?" 2
has "読めなかった理由を書く" "$out" "HTTP 503"

# --- 使い方の誤り ------------------------------------------------------------------
newcase usage
out=$(run --bogus)
check "知らない引数は使い方の誤り" "$?" 3
out=$(run --base no-such-commit)
check "無いコミットは準備の誤り" "$?" 3

# --- pre-push-deps.pl: pnpm-lock.yaml ------------------------------------------------
D="$TMP_ROOT/deps"
mkdir -p "$D/base" "$D/head"
cat >"$D/base/pnpm-lock.yaml" <<'EOF'
lockfileVersion: '9.0'

packages:

  lodash@4.17.21:
    resolution: {integrity: sha512-x}
EOF
cat >"$D/head/pnpm-lock.yaml" <<'EOF'
lockfileVersion: '9.0'

packages:

  '@babel/traverse@7.22.0':
    resolution: {integrity: sha512-y}

  lodash@4.17.21:
    resolution: {integrity: sha512-x}

snapshots:

  zzz@1.0.0: {}
EOF
out=$(perl "$DEPS" "$D/base" "$D/head")
has "pnpm の名前の付いた部品を読む" "$out" "$(printf 'npm\t@babel/traverse\t7.22.0')"
hasnt "前からある pnpm の部品は書かない" "$out" "lodash"
hasnt "packages の節の外は読まない" "$out" "zzz"

# --- pre-push-deps.pl: go.mod の1行の形の require と、maven を読まないこと ----------------
printf 'module example\n\nrequire github.com/a/b v1.2.3 // indirect\n' >"$D/head/go.mod"
printf '[versions]\njjwt = "0.12.6"\n' >"$D/head/libs.versions.toml"
out=$(perl "$DEPS" "$D/base" "$D/head")
has "1行の形の require を読み、版の先頭の v を落とす" "$out" "$(printf 'gomod\tgithub.com/a/b\t1.2.3')"
hasnt "module の行を部品として読まない" "$out" "example"
hasnt "libs.versions.toml を読まない" "$out" "maven"

echo ""
echo "pass=$pass fail=$failn"
[ "$failn" -eq 0 ]
