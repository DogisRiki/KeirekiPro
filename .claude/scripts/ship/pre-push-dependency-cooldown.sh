#!/usr/bin/env bash
# =====================================================================
# push の前に、CI の dependency-cooldown と同じ判定を手元で流す(/ship の手順1が呼ぶ)
#
# 使い方: bash .claude/scripts/ship/pre-push-dependency-cooldown.sh [--base <コミット>] [--head <コミット>] [--now-epoch <秒>]
#   作業フォルダの中で動かす。
#   --base       比べる元のコミット。既定は git merge-base origin/main HEAD(PR の比べる先に当たる)
#   --head       調べるコミット。既定は作業フォルダのファイル(まだ commit していない変更を含む)
#   --now-epoch  判定に使う時刻(UNIX 秒)。既定は今。過去の push の前の変更を、その時点の時刻で確かめ直すときに渡す
#   環境変数 GOMOD_INDEX_BASE を置くと、Go のモジュールの索引をその URL から読む(lib-gomod-index.sh と同じ意味)
#
# CI の dependency-cooldown(.github/scripts/check-dependency-cooldown.sh)は、PR で増えた部品のうち、
# 公開から72時間経っていない版を、所有者が承認するまで赤にする。ここでは、増えた部品を pre-push-deps.pl で求め、
# 公開時刻を CI と同じ読み方で読む pre-push-cooldown.sh をコンテナの中で動かす。
# CI の脆弱性の警告による例外と所有者の承認は、ここでは見ない(72時間経っていない版はすべて止まったとする)。
#
# 終了コード: 0 = 通った / 1 = 止まった / 2 = 調べられなかった / 3 = 使い方の誤りか、調べる準備ができなかった
# 前提: bash・git・perl・docker。jq には依存しない。
# 問い合わせる先: index.golang.org(Go のモジュールの索引)と registry.npmjs.org。部品の名前と版を問い合わせに使う。
#   コンテナは、道具(bash・curl・jq・coreutils)を入れるために Alpine のパッケージの配布元にもつなぐ。
# =====================================================================
set -uo pipefail

# Windows の Git Bash が docker と git に渡す引数のパスを書き換えないようにする
export MSYS_NO_PATHCONV=1 MSYS2_ARG_CONV_EXCL='*'

ALPINE_IMAGE='docker.io/library/alpine:3.22@sha256:49340b346798875b5592e5d420241f2f9cfba5f47e62ebb1446a1b34734e898f'
COOLDOWN_HOURS=72
LABEL="dependency-cooldown(公開から${COOLDOWN_HOURS}時間)"

usage() { echo "使い方: bash .claude/scripts/ship/pre-push-dependency-cooldown.sh [--base <コミット>] [--head <コミット>] [--now-epoch <秒>]" >&2; exit 3; }
fail_setup() { echo "準備ができませんでした: $*" >&2; exit 3; }

BASE_ARG=""
HEAD_ARG=""
NOW_ARG=""
while [ $# -gt 0 ]; do
    case "$1" in
    --base) [ $# -ge 2 ] || usage; BASE_ARG="$2"; shift 2 ;;
    --head) [ $# -ge 2 ] || usage; HEAD_ARG="$2"; shift 2 ;;
    --now-epoch) [[ "${2:-}" =~ ^[0-9]+$ ]] || usage; NOW_ARG="$2"; shift 2 ;;
    *) usage ;;
    esac
done

# Windows では、docker(Windows のプログラム)に C:/ の形のパスを渡す
host_path() { (cd "$1" && { pwd -W 2>/dev/null || pwd; }); }

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
TOP=$(git rev-parse --show-toplevel 2>/dev/null) || fail_setup "git の作業フォルダの中で動かしてください"
TOP=$(host_path "$TOP")
[ -f "$TOP/.github/scripts/lib-gomod-index.sh" ] || fail_setup ".github/scripts/lib-gomod-index.sh が無い"

if [ -n "$BASE_ARG" ]; then
    BASE=$(git -C "$TOP" rev-parse --verify --quiet "${BASE_ARG}^{commit}") || fail_setup "比べる元のコミット $BASE_ARG が無い"
else
    BASE=$(git -C "$TOP" merge-base origin/main HEAD) || fail_setup "origin/main との分かれ目を求められない"
fi
if [ -n "$HEAD_ARG" ]; then
    HEAD_SHA=$(git -C "$TOP" rev-parse --verify --quiet "${HEAD_ARG}^{commit}") || fail_setup "調べるコミット $HEAD_ARG が無い"
fi

TMP_RAW=$(mktemp -d) || fail_setup "一時のフォルダを作れない"
trap 'rm -rf "$TMP_RAW"' EXIT
TMP=$(host_path "$TMP_RAW")
mkdir -p "$TMP/base" "$TMP/head" "$TMP/w"

# 比べる元はコミットから、調べる側は --head のコミットか作業フォルダのファイルから取り出す
for f in backend/go.mod frontend/pnpm-lock.yaml; do
    name=$(basename "$f")
    git -C "$TOP" show "${BASE}:${f}" >"$TMP/base/$name" 2>/dev/null || rm -f "$TMP/base/$name"
    if [ -n "$HEAD_ARG" ]; then
        git -C "$TOP" show "${HEAD_SHA}:${f}" >"$TMP/head/$name" 2>/dev/null || rm -f "$TMP/head/$name"
    elif [ -f "$TOP/$f" ]; then
        cp "$TOP/$f" "$TMP/head/$name" || fail_setup "$f を読めない"
    fi
done

echo "比べる元: ${BASE}"
echo "調べる側: ${HEAD_SHA:-作業フォルダのファイル(まだ commit していない変更を含む)}"
[ -z "$NOW_ARG" ] || echo "判定に使う時刻: $(perl -MPOSIX -e 'print strftime("%Y-%m-%d %H:%M UTC", gmtime(shift))' "$NOW_ARG")"

perl "$HERE/pre-push-deps.pl" "$TMP/base" "$TMP/head" >"$TMP/w/added.tsv" || fail_setup "増えた部品を求められない"
added_count=$(grep -c . "$TMP/w/added.tsv" || true)
echo "増えた部品: ${added_count} 組"
if [ "$added_count" -eq 0 ]; then
    echo "${LABEL}: 通った(増えた部品が無い)"
    exit 0
fi

if ! docker run --rm -v "$TOP:/r:ro" -v "$TMP/w:/w" \
    -e NOW_EPOCH="$NOW_ARG" -e COOLDOWN_HOURS="$COOLDOWN_HOURS" -e GOMOD_INDEX_BASE "$ALPINE_IMAGE" sh -c '
        [ -n "$NOW_EPOCH" ] || unset NOW_EPOCH
        apk add --no-cache -q bash curl jq coreutils >/dev/null 2>&1 || { echo "コンテナに道具を入れられない" >&2; exit 69; }
        exec bash /r/.claude/scripts/ship/pre-push-cooldown.sh /w/added.tsv /w/result.tsv /r/.github/scripts/lib-gomod-index.sh
    ' >"$TMP/docker.log" 2>&1 || [ ! -f "$TMP/w/result.tsv" ]; then
    echo "${LABEL}: 調べられなかった"
    tail -n 5 "$TMP/docker.log" | sed 's/^/  /'
    exit 2
fi

# 結果の1行は「種類<TAB>名前<TAB>版<TAB>young|old|unknown<TAB>公開時刻の秒<TAB>理由」
perl -MPOSIX -F'\t' -lane '
    BEGIN { $w = '"$COOLDOWN_HOURS"' * 3600 }
    sub t { strftime("%Y-%m-%d %H:%M UTC", gmtime($_[0])) }
    if ($F[3] eq "young") { push @y, sprintf("  - %s %s@%s: 公開 %s。入れられるのは %s から", @F[0..2], t($F[4]), t($F[4] + $w)) }
    elsif ($F[3] eq "unknown") { push @u, sprintf("  - %s %s@%s: %s", @F[0..2], $F[5]) }
    END {
        my $s = @y ? "止まった(公開から'"$COOLDOWN_HOURS"'時間経っていない版がある)" : @u ? "調べられなかった(公開時刻を読めない版がある)" : "通った";
        print "'"$LABEL"': $s";
        print for @y, @u;
        $? = @y ? 1 : @u ? 2 : 0;
    }' "$TMP/w/result.tsv"
