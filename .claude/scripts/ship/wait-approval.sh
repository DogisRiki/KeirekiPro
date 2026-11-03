#!/bin/bash
# =====================================================================
# /ship の手順7で、所有者の承認を待つ間に裏で動かすスクリプト
#
# 使い方: bash .claude/scripts/ship/wait-approval.sh <PR番号>
# Claude は Bash の run_in_background で動かしてから返答を終える。このスクリプトが終わると Claude が呼び戻され、
# 出力の1行を読んで、手順7の1から見届けを続ける。所有者がチャットに何も書かなくても続きが始まるようにするためである。
#
# PR を読み直し、次のどれかが起きたら、何が起きたかを1行出して 0 で終わる。
#   - PR がマージされたか、閉じられた
#   - PR に承認のレビューが新しく付いた
#   - PR にほかのレビュー(変更の依頼、コメントだけのレビュー)かコメントが新しく付いた
#   - PR の head が変わった(push や、仕組みによるブランチの更新)
# PR を続けて5回読めなかったときは、そのことを1行出して 1 で終わる。
# 待つ時間の上限は設けない。上限を過ぎると、所有者がチャットに書かなければ続きが始まらなくなるためである。
#
# 待っている間は、.claude/.state/ship-watch/approval-wait-<PR番号> に、読み直しのたびにいまの時刻(UNIX 秒)を書き、
# 終わるときに消す。Stop フック check-ship-watch-before-stop.sh は、このファイルの時刻が新しいときだけ、
# 承認待ちのまま返答を終えるのを通す。
#
# 前提: bash と perl(JSON::PP)と gh。jqには依存しない。
# =====================================================================
set -u
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR

pr="${1:-}"
case "$pr" in
    '' | *[!0-9]*)
        echo "使い方: bash .claude/scripts/ship/wait-approval.sh <PR番号>" >&2
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
beat="$state_dir/approval-wait-$pr"
mkdir -p "$state_dir" || exit 1
trap 'rm -f "$beat" "$beat.tmp"' EXIT
trap 'exit 143' TERM INT HUP

# PR の「状態 head レビューの数 承認のレビューの数 コメントの数」をタブ区切りの1行で出す。読めなければ 1 で終わる
read_pr() {
    gh pr view "$pr" --json state,headRefOid,reviews,comments 2>/dev/null | perl -MJSON::PP -e '
        local $/; my $d = eval { JSON::PP::decode_json(<STDIN>) };
        exit 1 unless ref $d eq "HASH" && defined $d->{state};
        my @r = grep { ref $_ eq "HASH" } @{ ref $d->{reviews} eq "ARRAY" ? $d->{reviews} : [] };
        my $approved = grep { ($_->{state} // "") eq "APPROVED" } @r;
        my $comments = ref $d->{comments} eq "ARRAY" ? scalar @{ $d->{comments} } : 0;
        printf "%s\t%s\t%d\t%d\t%d\n", $d->{state}, $d->{headRefOid} // "", scalar @r, $approved, $comments;
    ' 2>/dev/null
}

base=""
fails=0
while :; do
    date +%s >"$beat.tmp" 2>/dev/null && mv -f "$beat.tmp" "$beat" 2>/dev/null
    if now=$(read_pr); then
        fails=0
        IFS=$'\t' read -r state head reviews approved comments <<<"$now"
        case "$state" in
            MERGED) echo "PR #$pr がマージされた。"; exit 0 ;;
            CLOSED) echo "PR #$pr が閉じられた。"; exit 0 ;;
        esac
        if [ -z "$base" ]; then
            base=$now
        else
            IFS=$'\t' read -r _ head0 reviews0 approved0 comments0 <<<"$base"
            if [ "$approved" -gt "$approved0" ]; then
                echo "PR #$pr が承認された。"; exit 0
            elif [ "$reviews" -gt "$reviews0" ]; then
                echo "PR #$pr に承認のほかのレビューが付いた。"; exit 0
            elif [ "$comments" -gt "$comments0" ]; then
                echo "PR #$pr にコメントが付いた。"; exit 0
            elif [ "$head" != "$head0" ]; then
                echo "PR #$pr の head が変わった。"; exit 0
            fi
        fi
    else
        fails=$((fails + 1))
        if [ "$fails" -ge "$max_fail" ]; then
            echo "PR #$pr の状態を続けて${max_fail}回読めなかった。"
            exit 1
        fi
    fi
    sleep "$interval"
done
