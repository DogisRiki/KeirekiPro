# shellcheck shell=bash
# =====================================================================
# Go のモジュールの版が、Go のモジュールの索引(index.golang.org)に初めて取り込まれた
# 時刻を調べるライブラリ
# (check-dependency-cooldown.sh から source して使う)
#
# 調べ方:
#   索引の index?since=<時刻>&limit=2000 を、判定の時刻の「待つ時間 + 1時間」前から
#   読む。索引は、取り込んだ順に「モジュール、版、取り込んだ時刻」を1行ずつ返す
#   (NDJSON)。読み始めから判定の時刻までを、GOMOD_INDEX_SEGMENT_HOURS 時間ずつの区間に分け、
#   区間ごとの読み取りを同時に動かす。区間の中では、2ページ目からは、前のページの最後の行の
#   時刻を since にする。1ページが2000件より少ないか、最後の行の時刻が区間の終わりを過ぎたら、
#   その区間を読み終える。最後の行の時刻は秒の端数を切り上げて比べるので、区間の終わりの1秒前の
#   中の行で終わるページでは、次のページも読む(同じ1秒の中の続きの行を読み落とさないため)。
#   区間の境のあたりの行は2度読むことがある。
#   読んだ範囲に無い組は、読み始めより前に取り込まれているので、待つ時間を過ぎている。
#   読み始めを1時間早めるのは、待つ時間のちょうど境にある組を、読んだ範囲に入れるためである。
#
# なぜ proxy.golang.org の .info の時刻を使わないか:
#   .info の Time は、モジュールの作者が付けたタグの時刻などから決まり、公開より古い時刻に
#   できる。索引の時刻は、proxy が初めて取り込んだ時刻で、作者が変えられない。
#
# なぜ索引を1度だけ読むか:
#   72時間分の索引は200ページ近くある。部品ごとに読むと、問い合わせの数が部品の数だけ
#   増える。照らす組をまとめて受け取り、1度読んだ索引にすべての組を照らす。
#
# なぜ区間に分けて同時に読むか:
#   索引の1回の問い合わせは、応答までに約4秒かかる(2026-11-08 に測った)。73時間分の索引を
#   1本で順に読むと約10分かかり、Dependabot の PR の自動マージの判定の時間の上限(5分)に
#   収まらない。区間ごとに同時に読めば、4時間の区間で約20本になり、1分ほどで読み終える。
#   16本を同時に問い合わせても、応答は4秒でそろった(2026-11-08 に確かめた)。
#
# 照らし方:
#   - 版は、先頭の v の有無によらず照らす。依存グラフの差分比較の API は、版の先頭の v を
#     落として返す(例: 1.8.7)。索引は v を付けて返す(例: v1.8.7)
#   - モジュールの名前は、大文字と小文字を区別せずに照らす。大文字と小文字だけが違う
#     モジュールが索引に2つあれば、新しい方の時刻を使う。待つ時間を短く見積もらないためである
#   - 同じ組が索引に2度あれば(ページの境と区間の境の行は2度読む)、新しい方の時刻を使う
#   - 取り込んだ時刻に秒の端数があれば、次の秒に切り上げる。待つ時間の数え始めを早めないため
#
# 環境変数:
#   GOMOD_INDEX_BASE(既定 https://index.golang.org。テストが差し替える)
#   NOW_EPOCH(判定の時刻。既定は今の時刻)
#   COOLDOWN_HOURS(待つ時間。既定 72)
#   GOMOD_INDEX_MAX_PAGES(読むページの上限。区間ごと。既定 1000)
#   GOMOD_INDEX_SEGMENT_HOURS(同時に読む区間の長さ。時間の単位の正の整数。既定 4)
# 問い合わせは curl -fsS --max-time 120 --retry 2 で行う。
#
# source しても何もしない。関数を定義するだけで、シェルの設定(set -e など)と
# trap を変えない。関数は exit せず、戻り値で成否を返す。
# 区間ごとの読み取りは、裏で動かすサブシェルで動かし、すべての終わりを待ってから返す。
#
# 関数と戻り値:
#   gomod_index_ages <照らす組のファイル> <出力のファイル>
#     照らす組のファイルは、1行に「モジュール<TAB>版」。
#     出力のファイルに、照らす組の順に「モジュール<TAB>版<TAB>new|old<TAB>取り込まれた時刻」を書く。
#     モジュールと版は、照らす組のファイルの書き方のまま書く。
#     new は待つ時間より新しい組、old は待つ時間を過ぎた組である。取り込まれた時刻は、
#     1970-01-01T00:00:00Z からの秒である。読んだ範囲に無い組は old にして、時刻を空にする。
#     照らす組が無ければ、索引を読まずに出力のファイルを空にする。
#   0 = 照らせた / 1 = 索引を読めないか、索引の形が違うか、読み終えられない
#   (標準エラーに理由を出す。出力のファイルは空にする)
#   gomod_index_since
#     索引を読み始める時刻を、1970-01-01T00:00:00Z からの秒で出す。読んだ範囲に無い組は、
#     この時刻より前に取り込まれている。
# =====================================================================

# 索引の1行の形。取り込んだ時刻は RFC 3339 の UTC で、秒の端数は付くことも付かないこともある
_GMI_SHAPE='type == "object" and (.Path | type) == "string" and (.Version | type) == "string"
    and (.Timestamp | type) == "string"
    and (.Timestamp | test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(\\.[0-9]+)?Z$"))'

# 取り込んだ時刻を秒にする jq の関数。秒の端数に0でない数字があれば、次の秒に切り上げる
_GMI_EPOCH='def gmi_epoch: capture("^(?<s>[^.Z]+)(?<f>\\.[0-9]+)?Z$")
    | (.s + "Z" | fromdateiso8601) + (if ((.f // "") | test("[1-9]")) then 1 else 0 end);'

gomod_index_since() {
    echo $((${NOW_EPOCH:-$(date -u +%s)} - (${COOLDOWN_HOURS:-72} + 1) * 3600))
}

_gmi_fail() {
    echo "index.golang.org の$1" >&2
}

# 使い方: _gmi_segment <一時のフォルダ> <区間の番号> <読み始めの時刻> <区間の終わりの秒>
# 1つの区間を、読み始めの時刻から since で順に読み、当たった行を <一時のフォルダ>/hits.<区間の番号> に書く。
# 1ページが2000件より少ないか、最後の行の時刻が区間の終わりを過ぎたら読み終える。
_gmi_segment() {
    local d="$1" i="$2" since="$3" end="$4"
    local base max url page=0 meta n last last_epoch
    base="${GOMOD_INDEX_BASE:-https://index.golang.org}"
    max="${GOMOD_INDEX_MAX_PAGES:-1000}"
    : >"$d/hits.$i"
    while :; do
        page=$((page + 1))
        if [ "$page" -gt "$max" ]; then
            _gmi_fail "索引を ${max} ページ読んでも、区間の終わりの時刻に届きませんでした(最後の読み始め: ${since})"
            return 1
        fi
        url="${base}/index?since=${since}&limit=2000"
        if ! curl -fsS --max-time 120 --retry 2 -o "$d/body.$i" "$url" 2>"$d/curl.$i"; then
            _gmi_fail "索引を読めませんでした(${url}: $(head -n 1 "$d/curl.$i"))"
            return 1
        fi
        if ! meta=$(jq -r -s "$_GMI_EPOCH"'
                if all(.[]; '"$_GMI_SHAPE"') then
                    "\(length)\t\(if length > 0 then last.Timestamp else "" end)\t\(if length > 0 then (last.Timestamp | gmi_epoch) else "" end)"
                else error("shape") end' "$d/body.$i" 2>/dev/null); then
            _gmi_fail "索引の形が違います(${url})"
            return 1
        fi
        IFS=$'\t' read -r n last last_epoch <<<"$meta"
        jq -r -s "$_GMI_EPOCH"'.[] | [(.Path | ascii_downcase), .Version, (.Timestamp | gmi_epoch)] | @tsv' \
            "$d/body.$i" | awk -F'\t' 'NR == FNR { k[$0] = 1; next } (($1 "\t" $2) in k)' "$d/keys" - >>"$d/hits.$i"
        [ "$n" -ge 2000 ] || break
        # 切り上げた時刻が区間の終わりと同じなら、元の時刻は区間の中なので、次のページも読む
        [ "$last_epoch" -le "$end" ] || break
        if [ "$last" = "$since" ]; then
            _gmi_fail "索引の読み始めの時刻が進みません(${url})"
            return 1
        fi
        since="$last"
    done
}

# 使い方: _gmi_read <一時のフォルダ> <照らす組のファイル> <出力のファイル>
_gmi_read() {
    local d="$1" wanted="$2" out="$3"
    local now hours seg s e since i=0 j rc=0 pids=() ranges=()
    now="${NOW_EPOCH:-$(date -u +%s)}"
    hours="${COOLDOWN_HOURS:-72}"
    seg="${GOMOD_INDEX_SEGMENT_HOURS:-4}"
    if ! [[ "$seg" =~ ^[1-9][0-9]*$ ]]; then
        _gmi_fail "索引の区間の長さ(GOMOD_INDEX_SEGMENT_HOURS=${seg})が正の整数ではありません"
        return 1
    fi
    seg=$((seg * 3600))

    # 照らす鍵: 小文字のモジュール<TAB>v の付いた版
    awk -F'\t' 'NF >= 2 && $1 != "" {
        v = $2; sub(/^v/, "", v); print tolower($1) "\tv" v }' "$wanted" | sort -u >"$d/keys"

    # 読み始めから判定の時刻までを区間に分ける。区間の読み始めの時刻をすべて決めてから、
    # 区間ごとの読み取りを同時に動かす(途中で失敗して、動いている読み取りを残さないため)
    s=$(NOW_EPOCH="$now" COOLDOWN_HOURS="$hours" gomod_index_since)
    while [ "$s" -lt "$now" ]; do
        e=$((s + seg))
        [ "$e" -le "$now" ] || e="$now"
        since=$(jq -n -r --argjson s "$s" '$s | todate') || return 1
        ranges+=("${since} ${e}")
        s="$e"
    done
    for i in "${!ranges[@]}"; do
        _gmi_segment "$d" "$i" "${ranges[$i]% *}" "${ranges[$i]#* }" 2>"$d/err.$i" &
        pids+=("$!")
    done
    for j in "${!pids[@]}"; do
        wait "${pids[$j]}" || rc=1
        cat "$d/err.$j" >&2
    done
    [ "$rc" -eq 0 ] || return 1
    : >"$d/hits"
    for j in "${!pids[@]}"; do
        cat "$d/hits.$j" >>"$d/hits"
    done

    awk -F'\t' -v now="$now" -v wait="$((hours * 3600))" '
        FILENAME == ARGV[1] { k = $1 "\t" $2; if (!(k in t) || $3 + 0 > t[k]) t[k] = $3 + 0; next }
        NF >= 2 && $1 != "" {
            v = $2; sub(/^v/, "", v); k = tolower($1) "\tv" v
            if (k in t) printf "%s\t%s\t%s\t%s\n", $1, $2, (now - t[k] < wait ? "new" : "old"), t[k]
            else printf "%s\t%s\told\t\n", $1, $2
        }' "$d/hits" "$wanted" >"$out"
}

gomod_index_ages() {
    local wanted="${1:?}" out="${2:?}" d rc=0
    : >"$out" || return 1
    if ! awk -F'\t' 'NF >= 2 && $1 != "" { found = 1 } END { exit !found }' "$wanted"; then
        return 0
    fi
    d=$(mktemp -d) || return 1
    _gmi_read "$d" "$wanted" "$out" || rc=1
    rm -rf "$d"
    [ "$rc" -eq 0 ] || : >"$out"
    return "$rc"
}
