#!/usr/bin/env bash
# =====================================================================
# pre-push-ci-checks.sh のテスト(手元で動かす。docker が要る)
#
# 使い方: bash .claude/scripts/ship/tests/test-pre-push-ci-checks.sh
# 一時のリポジトリを作り、秘密の値の有無と、commit したかどうかを変えて、終了コードと出力を確かめる。
# 秘密の値は、このファイル自体が CI の gitleaks に引っかからないよう、動かすときに組み立てる。
# =====================================================================
set -uo pipefail
export MSYS_NO_PATHCONV=1 MSYS2_ARG_CONV_EXCL='*'

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
SCRIPT="$HERE/../pre-push-ci-checks.sh"

pass=0
fail=0
check() {
    local name=$1 want_rc=$2 got_rc=$3 want_text=$4 out=$5
    if [ "$got_rc" -eq "$want_rc" ] && { [ -z "$want_text" ] || grep -qF -- "$want_text" <<<"$out"; }; then
        echo "PASS: $name"
        pass=$((pass + 1))
    else
        echo "FAIL: $name(期待 $want_rc「$want_text」、実際 $got_rc)"
        echo "$out" | sed 's/^/    /'
        fail=$((fail + 1))
    fi
}

TMP_RAW=$(mktemp -d)
trap 'rm -rf "$TMP_RAW"' EXIT
TMP=$(cd "$TMP_RAW" && { pwd -W 2>/dev/null || pwd; })

# GitHub の個人のアクセストークンの形の値(実在しない)
SECRET="ghp_$(printf '%s' 'Zq8Lm3Vx7Rt2Nw9Kp4Hy6Bc1Df5Gj0Ts8Ua3Ye' | cut -c1-36)"

new_repo() {
    local dir="$TMP/$1"
    git init -q "$dir"
    git -C "$dir" config user.name test
    git -C "$dir" config user.email test@localhost
    echo "hello" >"$dir/README.md"
    git -C "$dir" add README.md
    git -C "$dir" commit -q -m base
    echo "$dir"
}

# 1. 秘密の値が無ければ通る
r=$(new_repo clean)
echo "plain text" >"$r/note.txt"
git -C "$r" add note.txt && git -C "$r" commit -q -m clean
out=$(cd "$r" && bash "$SCRIPT" --base HEAD~1 2>&1); rc=$?
check "秘密の値が無ければ通る" 0 "$rc" "gitleaks(秘密の値): 通った" "$out"

# 2. commit した秘密の値で止まり、ファイルと行と指紋を出す
r=$(new_repo committed)
printf 'token = "%s"\n' "$SECRET" >"$r/config.txt"
git -C "$r" add config.txt && git -C "$r" commit -q -m leak
sha=$(git -C "$r" rev-parse HEAD)
out=$(cd "$r" && bash "$SCRIPT" --base HEAD~1 2>&1); rc=$?
check "commit した秘密の値で止まる" 1 "$rc" "config.txt:1 規則 github-pat" "$out"
check "止まったときに指紋を出す" 1 "$rc" "指紋: ${sha}:config.txt:github-pat:1" "$out"

# 3. まだ commit していない秘密の値でも止まる
r=$(new_repo uncommitted)
printf 'token = "%s"\n' "$SECRET" >"$r/draft.txt"
out=$(cd "$r" && bash "$SCRIPT" --base HEAD 2>&1); rc=$?
check "まだ commit していない秘密の値で止まる" 1 "$rc" "draft.txt:1 規則 github-pat" "$out"
check "作業フォルダの index を変えない" 0 "$(git -C "$r" diff --cached --name-only | grep -c . || true)" "" ""

# 4. 基準より前のコミットの秘密の値は調べない
r=$(new_repo before_base)
printf 'token = "%s"\n' "$SECRET" >"$r/old.txt"
git -C "$r" add old.txt && git -C "$r" commit -q -m old-leak
echo "plain" >"$r/new.txt"
git -C "$r" add new.txt && git -C "$r" commit -q -m new
out=$(cd "$r" && bash "$SCRIPT" --base HEAD~1 2>&1); rc=$?
check "基準より前のコミットは調べない" 0 "$rc" "gitleaks(秘密の値): 通った" "$out"

# 5. .gitleaksignore に書いた指紋は止めない
r=$(new_repo ignored)
printf 'token = "%s"\n' "$SECRET" >"$r/config.txt"
git -C "$r" add config.txt && git -C "$r" commit -q -m leak
echo "$(git -C "$r" rev-parse HEAD):config.txt:github-pat:1" >"$r/.gitleaksignore"
git -C "$r" add .gitleaksignore && git -C "$r" commit -q -m ignore
out=$(cd "$r" && bash "$SCRIPT" --base HEAD~2 2>&1); rc=$?
check ".gitleaksignore に書いた指紋は止めない" 0 "$rc" "gitleaks(秘密の値): 通った" "$out"

# 6. 使い方の誤りと、無い基準のコミット
r=$(new_repo usage)
out=$(cd "$r" && bash "$SCRIPT" --unknown 2>&1); rc=$?
check "知らない引数は使い方の誤り" 3 "$rc" "使い方:" "$out"
out=$(cd "$r" && bash "$SCRIPT" --base 0000000000000000000000000000000000000000 2>&1); rc=$?
check "無い基準のコミットは準備の誤り" 3 "$rc" "基準のコミット" "$out"

# 7. gitleaks を動かせないときは「調べられなかった」として、通ったことにしない
mkdir -p "$TMP_RAW/fakebin"
printf '#!/usr/bin/env bash\necho "docker が動いていない" >&2\nexit 125\n' >"$TMP_RAW/fakebin/docker"
chmod +x "$TMP_RAW/fakebin/docker"
r=$(new_repo no_docker)
out=$(cd "$r" && PATH="$TMP_RAW/fakebin:$PATH" bash "$SCRIPT" --base HEAD 2>&1); rc=$?
check "gitleaks を動かせないときは調べられなかった" 2 "$rc" "gitleaks(秘密の値): 調べられなかった" "$out"

echo ""
echo "PASS: $pass / FAIL: $fail"
[ "$fail" -eq 0 ]
