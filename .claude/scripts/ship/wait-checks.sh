#!/bin/bash
# =====================================================================
# /ship-it の手順7の2で、必須の検査の結果を待つ間に裏で動かすスクリプト
#
# 使い方: bash .claude/scripts/ship/wait-checks.sh <PR番号>
# Claude は Bash の run_in_background で動かしてから返答を終える。このスクリプトが終わると Claude が呼び戻され、
# 出力の1行を読んで、手順7の見届けを続ける。所有者がチャットに何も書かなくても続きが始まるようにするためである。
#
# PR と必須の検査を読み直し、次のどれかが起きたら、何が起きたかを1行出して 0 で終わる。
#   - PR がマージされたか、閉じられた
#   - 必須の検査の結果がすべて出た(赤の検査があるときも含む)
#   - 必須の検査がまだ1つも報告されていない(push の直後など)
# PR がマージされたときにも終わるのは、マージのあとも GitHub に「実行中」のまま残る検査があると、
# 検査の結果だけを待っていては待ちが終わらないためである(gh pr checks --watch はこのときに終わらない)。
# PR か検査を続けて5回読めなかったときは、そのことを1行出して 1 で終わる。
# 待つ時間の上限は設けない。上限を過ぎると、所有者がチャットに書かなければ続きが始まらなくなるためである。
#
# 待っている間は、.claude/.state/ship-watch/checks-wait-<PR番号> に、読み直しのたびにいまの時刻(UNIX 秒)を書き、
# 終わるときに消す。Stop フック check-ship-watch-before-stop.sh は、このファイルの時刻が新しいときだけ、
# 結果が出ていない検査があるまま返答を終えるのを通す。
#
# gh pr checks に --json を付けると、結果が出ていない検査があっても JSON を出して 0 で終わる。
# 必須の検査が1つも無いときは、「no required checks reported」の文を出して 0 以外で終わる。
# (https://github.com/cli/cli/blob/trunk/pkg/cmd/pr/checks/checks.go の populateStatusChecks と Exporter の扱い)
#
# 前提: bash と perl(JSON::PP)と gh。jqには依存しない。
# =====================================================================
set -u
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR

pr="${1:-}"
case "$pr" in
    '' | *[!0-9]*)
        echo "使い方: bash .claude/scripts/ship/wait-checks.sh <PR番号>" >&2
        exit 64
        ;;
esac
# 読み直しの間隔(秒)。テストが短くするために変えられる
interval="${SHIP_WAIT_INTERVAL:-60}"
max_fail=5

top=$(git rev-parse --show-toplevel 2>/dev/null) || {
    echo "git のリポジトリの外で動かした。作業フォルダの最上位で動かしてください。" >&2
    exit 64
}
state_dir="${top//\\//}/.claude/.state/ship-watch"
beat="$state_dir/checks-wait-$pr"
mkdir -p "$state_dir" || exit 1
trap 'rm -f "$beat" "$beat.tmp"' EXIT
trap 'exit 143' TERM INT HUP

# PR の状態を出す。読めなければ 1 で終わる
read_state() {
    gh pr view "$pr" --json state 2>/dev/null | perl -MJSON::PP -e '
        local $/; my $d = eval { JSON::PP::decode_json(<STDIN>) };
        exit 1 unless ref $d eq "HASH" && defined $d->{state} && !ref $d->{state};
        print $d->{state}, "\n";
    ' 2>/dev/null
}

# 必須の検査を読み、「pending」(結果が出ていない検査がある)、「done」(結果がすべて出た)、
# 「none」(必須の検査がまだ1つも無い)のどれかを出す。読めなければ 1 で終わる
read_checks() {
    local out err rc
    err=$(mktemp) || return 1
    out=$(gh pr checks "$pr" --required --json name,bucket 2>"$err")
    rc=$?
    if [ "$rc" -ne 0 ]; then
        if grep -qE 'no (required )?checks reported' "$err" 2>/dev/null; then
            rm -f "$err"
            echo none
            return 0
        fi
        rm -f "$err"
        return 1
    fi
    rm -f "$err"
    printf '%s' "$out" | perl -MJSON::PP -e '
        local $/; my $d = eval { JSON::PP::decode_json(<STDIN>) };
        exit 1 unless ref $d eq "ARRAY";
        unless (@$d) { print "none\n"; exit 0 }
        my $pending = grep { ref $_ eq "HASH" && ($_->{bucket} // "") eq "pending" } @$d;
        print $pending ? "pending\n" : "done\n";
    ' 2>/dev/null
}

fails=0
while :; do
    date +%s >"$beat.tmp" 2>/dev/null && mv -f "$beat.tmp" "$beat" 2>/dev/null
    if state=$(read_state); then
        case "$state" in
            MERGED) echo "PR #$pr がマージされた。"; exit 0 ;;
            CLOSED) echo "PR #$pr が閉じられた。"; exit 0 ;;
        esac
        if checks=$(read_checks); then
            fails=0
            case "$checks" in
                done) echo "PR #$pr の必須の検査の結果がすべて出た。"; exit 0 ;;
                none) echo "PR #$pr の必須の検査がまだ1つも報告されていない。"; exit 0 ;;
            esac
        else
            fails=$((fails + 1))
        fi
    else
        fails=$((fails + 1))
    fi
    if [ "$fails" -ge "$max_fail" ]; then
        echo "PR #$pr の状態か必須の検査を続けて${max_fail}回読めなかった。"
        exit 1
    fi
    sleep "$interval"
done
