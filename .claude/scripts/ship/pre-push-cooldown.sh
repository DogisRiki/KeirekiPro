#!/usr/bin/env bash
# =====================================================================
# push の前に、増えた部品の公開からの時間を調べる(pre-push-dependency-cooldown.sh がコンテナの中で呼ぶ)
#
# 使い方: bash pre-push-cooldown.sh <増えた部品のファイル> <結果のファイル> <lib-gomod-index.sh のパス>
#   増えた部品のファイルは、1行に「種類<TAB>名前<TAB>版」(pre-push-deps.pl の出力。種類は gomod か npm)。
#   結果のファイルに、1行に「種類<TAB>名前<TAB>版<TAB>young|old|unknown<TAB>公開時刻の秒<TAB>理由」を書く。
#   young は公開から COOLDOWN_HOURS 時間(既定72)経っていない版、unknown は公開時刻を読めなかった版。
#   環境変数 NOW_EPOCH(判定の時刻。既定は今)と COOLDOWN_HOURS は CI と同じ意味で読む。
#   必要な道具: bash・curl・jq・awk・GNU の date(coreutils)
#
# 公開時刻の読み方は CI の .github/scripts/check-dependency-cooldown.sh と同じにする。
#   gomod: Go のモジュールの索引に初めて取り込まれた時刻(lib-gomod-index.sh をそのまま使う)
#   npm:   registry の部品の文書の time["<版>"]
# CI の脆弱性の警告による例外と所有者の承認は、ここでは判定しない(手元では止まったとして返す)。
# =====================================================================
set -euo pipefail

ADDED="${1:?増えた部品のファイルが要ります}"
OUT="${2:?結果のファイルが要ります}"
LIB="${3:?lib-gomod-index.sh のパスが要ります}"

NOW_EPOCH="${NOW_EPOCH:-$(date -u +%s)}"
COOLDOWN_HOURS="${COOLDOWN_HOURS:-72}"
export NOW_EPOCH COOLDOWN_HOURS
NPM_REGISTRY_BASE="https://registry.npmjs.org"
WAIT=$((COOLDOWN_HOURS * 3600))

# shellcheck source=.github/scripts/lib-gomod-index.sh
. "$LIB"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
: >"$OUT"

emit() { printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$@" >>"$OUT"; }

judge() {
    local eco="$1" name="$2" version="$3" published="$4"
    if [ $((NOW_EPOCH - published)) -lt "$WAIT" ]; then
        emit "$eco" "$name" "$version" young "$published" ""
    else
        emit "$eco" "$name" "$version" old "$published" ""
    fi
}

# --- gomod: 索引を1度だけ読み、すべての組を照らす ---
awk -F'\t' '$1 == "gomod" { print $2 "\t" $3 }' "$ADDED" >"$TMP/gomod-wanted.tsv"
if [ -s "$TMP/gomod-wanted.tsv" ]; then
    if gomod_index_ages "$TMP/gomod-wanted.tsv" "$TMP/gomod-ages.tsv" 2>"$TMP/gomod.err"; then
        since=$(gomod_index_since)
        while IFS=$'\t' read -r name version state ts; do
            if [ "$state" = new ]; then
                emit gomod "$name" "$version" young "$ts" ""
            else
                # 索引の読んだ範囲に無い組は、読み始めより前に取り込まれている
                emit gomod "$name" "$version" old "${ts:-$since}" ""
            fi
        done <"$TMP/gomod-ages.tsv"
    else
        reason="Go のモジュールの索引を読めない: $(head -n 1 "$TMP/gomod.err")"
        while IFS=$'\t' read -r name version; do
            emit gomod "$name" "$version" unknown "" "$reason"
        done <"$TMP/gomod-wanted.tsv"
    fi
fi

# --- npm ---
while IFS=$'\t' read -r eco name version; do
    [ "$eco" = npm ] || continue
    if ! [[ "$name" =~ ^(@[A-Za-z0-9._~-]+/)?[A-Za-z0-9._~-]+$ ]]; then
        emit npm "$name" "$version" unknown "" "npm の名前の形ではない"
        continue
    fi
    doc="$TMP/npm-$(printf '%s' "$name" | tr '/@' '__').json"
    if [ ! -f "$doc" ]; then
        code=$(curl -sS -L --max-time 60 -o "$doc" -w '%{http_code}' \
            "${NPM_REGISTRY_BASE}/${name/\//%2f}" 2>/dev/null) || code=000
        [ "$code" = 200 ] || { rm -f "$doc"; emit npm "$name" "$version" unknown "" "registry が HTTP $code を返した"; continue; }
    fi
    t=$(jq -r --arg v "$version" '.time[$v] // empty | strings' "$doc" 2>/dev/null || true)
    published=$( [ -n "$t" ] && date -u -d "$t" +%s 2>/dev/null || true)
    if [ -z "$published" ]; then
        emit npm "$name" "$version" unknown "" "registry の文書に版の公開時刻が無い"
        continue
    fi
    judge npm "$name" "$version" "$published"
done <"$ADDED"

