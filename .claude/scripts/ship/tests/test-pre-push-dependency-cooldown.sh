#!/usr/bin/env bash
# =====================================================================
# pre-push-dependency-cooldown.sh のテスト
#
# 実行: bash .claude/scripts/ship/tests/test-pre-push-dependency-cooldown.sh
# テストの場合ごとに、一時のフォルダに偽の git のリポジトリを作り、docker を偽物に替えて流す。
# 偽の docker は、ファイルに書いた判定の結果を返すだけで、コンテナを動かさない。
# 公開時刻を読む pre-push-cooldown.sh そのものは、外の索引と registry を読むので、ここでは流さない。
# 前提: bash・git・perl
# =====================================================================
set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$(cd "$HERE/.." && pwd)/pre-push-dependency-cooldown.sh"
TMP_RAW=$(mktemp -d)
trap 'rm -rf "$TMP_RAW"' EXIT
# Windows の git には C:/... の形のパスを渡す。ほかの OS ではそのまま使う
TMP_ROOT=$(cd "$TMP_RAW" && { pwd -W 2>/dev/null || pwd -P; })

pass=0
failn=0
ok() { pass=$((pass + 1)); printf 'ok   %s\n' "$1"; }
ng() { failn=$((failn + 1)); printf 'NG   %s\n' "$1"; }
check() { if [ "$2" = "$3" ]; then ok "$1"; else ng "$1 (want [$3] got [$2])"; fi; }
has() { if printf '%s' "$2" | grep -qF -- "$3"; then ok "$1"; else ng "$1 (出力に [$3] が無い)"; fi; }
hasnt() { if printf '%s' "$2" | grep -qF -- "$3"; then ng "$1 (出力に [$3] がある)"; else ok "$1"; fi; }

# 偽の docker。-v の「<フォルダ>:/w」の <フォルダ> に、STUB/result を result.tsv として写し、
# /w/added.tsv を STUB/added に写す。STUB/fail があれば失敗する。呼ばれた引数を STUB/calls に書く
STUB="$TMP_RAW/stub"
mkdir -p "$STUB/bin"
cat >"$STUB/bin/docker" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$@" >>"$STUB_DIR/calls"
if [ -f "$STUB_DIR/fail" ]; then echo "コンテナに道具を入れられない" >&2; exit 69; fi
while [ $# -gt 0 ]; do
    case "$1" in
    -v) case "$2" in *:/w) w="${2%:/w}" ;; esac; shift 2 ;;
    *) shift ;;
    esac
done
cp "$w/added.tsv" "$STUB_DIR/added"
cp "$STUB_DIR/result" "$w/result.tsv"
EOF
chmod +x "$STUB/bin/docker"
export STUB_DIR="$STUB"
export PATH="$STUB/bin:$PATH"

# 偽のリポジトリを作り、go.mod に jwt 5.3.1 だけを書いた基準のコミットを作る。
# 判定の部品の lib-gomod-index.sh は、置き場所があることだけを確かめるので空のファイルを置く
newcase() {
    rm -f "$STUB/calls" "$STUB/fail" "$STUB/result" "$STUB/added"
    R="$TMP_ROOT/repo-$1"
    git init -q "$R"
    git -C "$R" config user.email t@example.com
    git -C "$R" config user.name t
    mkdir -p "$R/backend" "$R/.github/scripts"
    : >"$R/.github/scripts/lib-gomod-index.sh"
    printf 'module example\n\ngo 1.25\n\nrequire github.com/golang-jwt/jwt/v5 v5.3.1\n' >"$R/backend/go.mod"
    git -C "$R" add -A
    git -C "$R" commit -q -m base
    BASE=$(git -C "$R" rev-parse HEAD)
    printf 'module example\n\ngo 1.25\n\nrequire (\n\tgithub.com/golang-jwt/jwt/v5 v5.3.1\n\tgithub.com/example/x v1.0.0\n)\n' >"$R/backend/go.mod"
}
run() { (cd "$R" && bash "$SCRIPT" "$@" 2>&1); }
T=$'\t'

# --- 増えた部品が無い -------------------------------------------------------------
newcase none
git -C "$R" checkout -q -- backend/go.mod
out=$(run --base "$BASE")
check "増えた部品が無いと通る" "$?" 0
has "増えた部品が無いと書く" "$out" "通った(増えた部品が無い)"
check "増えた部品が無いと docker を呼ばない" "$([ -f "$STUB/calls" ] && echo called || echo none)" none

# --- 72時間経っていない版がある(まだ commit していない変更) -----------------------------
newcase young
printf 'gomod\tgithub.com/example/x\t1.0.0\tyoung\t1769630395\t\n' >"$STUB/result"
out=$(run --base "$BASE")
check "72時間経っていない版があると止まる" "$?" 1
has "止まった部品と公開時刻を書く" "$out" "gomod github.com/example/x@1.0.0: 公開 2026-01-28 19:59 UTC"
has "入れられる時刻を書く" "$out" "入れられるのは 2026-01-31 19:59 UTC から"
check "増えた部品だけを判定に渡す" "$(cat "$STUB/added")" "gomod${T}github.com/example/x${T}1.0.0"
hasnt "判定の時刻を渡さなければ空で渡す" "$(cat "$STUB/calls")" "NOW_EPOCH=1"

# --- --now-epoch を判定に渡す(commit した変更) ---------------------------------------
newcase now
git -C "$R" commit -q -am add-x
printf 'gomod\tgithub.com/example/x\t1.0.0\told\t1769630395\t\n' >"$STUB/result"
out=$(run --base "$BASE" --head HEAD --now-epoch 1769688000)
check "古い版だけなら通る" "$?" 0
has "判定の時刻を書く" "$out" "判定に使う時刻: 2026-01-29 12:00 UTC"
has "判定の時刻をコンテナに渡す" "$(cat "$STUB/calls")" "NOW_EPOCH=1769688000"

# --- 公開時刻を読めない版がある ----------------------------------------------------
newcase unknown
printf 'gomod\tgithub.com/example/x\t1.0.0\tunknown\t\tGo のモジュールの索引を読めない: HTTP 429\n' >"$STUB/result"
out=$(run --base "$BASE")
check "公開時刻を読めないと調べられなかったとする" "$?" 2
has "読めなかった理由を書く" "$out" "Go のモジュールの索引を読めない: HTTP 429"

# --- 止まった版と読めない版の両方がある -------------------------------------------------
newcase both
printf 'npm\ta\t1.0.0\tyoung\t1769630395\t\nnpm\tb\t1.0.0\tunknown\t\tregistry が HTTP 503 を返した\n' >"$STUB/result"
out=$(run --base "$BASE")
check "止まった版があれば読めない版があっても止まったとする" "$?" 1
has "読めない版も書く" "$out" "npm b@1.0.0: registry が HTTP 503 を返した"

# --- コンテナが動かない ------------------------------------------------------------
newcase fail
touch "$STUB/fail"
out=$(run --base "$BASE")
check "コンテナが動かないと調べられなかったとする" "$?" 2
has "コンテナの出力を書く" "$out" "コンテナに道具を入れられない"

# --- 使い方の誤り ------------------------------------------------------------------
newcase usage
out=$(run --bogus)
check "知らない引数は使い方の誤り" "$?" 3
out=$(run --now-epoch soon)
check "数でない判定の時刻は使い方の誤り" "$?" 3
out=$(run --base no-such-commit)
check "無いコミットは準備の誤り" "$?" 3

echo ""
echo "pass=$pass fail=$failn"
[ "$failn" -eq 0 ]
