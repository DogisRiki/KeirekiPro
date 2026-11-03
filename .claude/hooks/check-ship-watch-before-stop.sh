#!/bin/bash
# =====================================================================
# Stop hook: /ship の見届けを、終えてはいけない状態で終えないようにする
#
# いまのブランチのPRが、/ship の手順7で見届けを続ける状態にあるときに、停止をブロックする(exit 2)。
# 止める状態は次の5つ。どれも .claude/skills/ship/SKILL.md の手順7の判定で「見届けを続ける」側に当たる。
#   - PRが開いていて、main と衝突している(mergeStateStatus が DIRTY)
#   - PRが開いていて、必須の検査に結果が出ていないもの(bucket が pending)がある
#   - PRが開いていて、必須の検査がすべて通り、自動マージの予約があり、承認待ち(REVIEW_REQUIRED)でない
#     (マージの途中か、main の取り込みが要る)
#   - PRが開いていて、所有者の承認を待っているのに、承認を待つスクリプト(.claude/scripts/ship/wait-approval.sh)が
#     動いていない。承認を待っているとは、承認待ち(REVIEW_REQUIRED)か、承認待ちのゲートの検査
#     (.github/audit/required-checks.json の approval_gated が true の検査)が赤で、ほかの必須の検査に赤が無いことをいう。
#     スクリプトが動いているかは、スクリプトが読み直しのたびに書く .claude/.state/ship-watch/approval-wait-<PR番号> の
#     時刻が5分以内かで見分ける
#   - PRがマージされ、本文の行頭の Closes #<N> の Issue の集計がまだ出ていない
# 承認待ちのゲートのほかの赤の検査・提案の答え待ちなど、手順7が見届けを終えてよいとする状態では止めない。
#
# 同じ状態では1回だけ止める。開いているPRの状態は prompt_id・PRの番号・head・止めた理由の組で、
# マージ後の集計は session_id・PRの番号の組で見分け、止めた組を .claude/.state/ship-watch/blocked.txt に残す。
# 所有者がチャットで見届けをやめるよう書いたときに、2回目の停止で止まれるようにするためである。
# マージ後の集計を session_id で見分けるのは、集計を出せなかったときに、返答のたびに止めないためである。
#
# PRが無いとき、gh で状態を読めないとき、作業フォルダが決まらないときは通す。
# 前提: bash と perl(JSON::PP)と gh。jqには依存しない。
# Windowsでは Git for Windows(Git Bash同梱)が bash と perl を提供する。macOS/Linuxは標準。
# =====================================================================
set -u
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR

payload=$(cat)

extract() {
    printf '%s' "$payload" | perl -MJSON::PP -e '
        local $/; my $d = eval { JSON::PP::decode_json(<STDIN>) };
        exit 0 unless ref $d;
        my $v = $d;
        for my $k (@ARGV) { $v = eval { $v->{$k} }; last unless defined $v; }
        if (defined $v && !ref $v) { print $v }
        elsif (defined $v && JSON::PP::is_bool($v)) { print $v ? "true" : "false" }
    ' -- "$@" 2>/dev/null
}

# 与えたディレクトリの git の最上位を出す。決まらなければ終了コード1
toplevel_of() {
    local dir="${1//\\//}" top
    [ -n "$dir" ] && [ -d "$dir" ] || return 1
    top=$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null) || return 1
    top=${top//\\//}
    [ -n "$top" ] || return 1
    printf '%s' "$top"
}

# 作業フォルダ: 入力の cwd の git の最上位。決まらなければ CLAUDE_PROJECT_DIR の git の最上位を使う
project_dir=$(toplevel_of "$(extract cwd)") \
    || project_dir=$(toplevel_of "${CLAUDE_PROJECT_DIR:-}") \
    || exit 0
cd "$project_dir" || exit 0

branch=$(git branch --show-current 2>/dev/null)
case "$branch" in
    '' | main) exit 0 ;;
esac

pr_json=$(gh pr view "$branch" --json number,state,headRefName,headRefOid,mergeStateStatus,reviewDecision,autoMergeRequest,body 2>/dev/null) || exit 0
[ -n "$pr_json" ] || exit 0

pr_state=$(printf '%s' "$pr_json" | perl -MJSON::PP -e '
    local $/; my $d = eval { JSON::PP::decode_json(<STDIN>) };
    exit 0 unless ref $d eq "HASH";
    exit 0 unless ($d->{headRefName} // "") eq $ARGV[0];
    print $d->{state} // "";
' -- "$branch" 2>/dev/null)

checks_json=""
if [ "$pr_state" = "OPEN" ]; then
    # 結果が出ていない検査があると gh は 0 以外で終わるので、終了コードではなく出力の JSON で読む
    checks_json=$(gh pr checks "$branch" --required --json name,bucket 2>/dev/null)
elif [ "$pr_state" != "MERGED" ]; then
    exit 0
fi

usage_dir=""
common=$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null) && usage_dir="${common//\\//}/keirekipro-usage/issues"
state_dir="$project_dir/.claude/.state/ship-watch"

# 止める理由を「<見分ける組>\t<Claude への文>」の1行で出す。止めないときは何も出さない
verdict=$(perl -MJSON::PP -e '
    my ($pr_json, $checks_json, $usage_dir, $expected, $state_dir) = @ARGV;
    my $pr = eval { JSON::PP::decode_json($pr_json) };
    exit 0 unless ref $pr eq "HASH";
    my $n = $pr->{number} // "";
    my $sha = $pr->{headRefOid} // "";
    if (($pr->{state} // "") eq "MERGED") {
        my @missing;
        for my $issue ((($pr->{body} // "") =~ /^Closes #([0-9]+)/mg)) {
            my $st;
            if (open my $fh, "<", "$usage_dir/$issue.json") {
                local $/; $st = eval { JSON::PP::decode_json(<$fh>) }; close $fh;
            }
            next if ref $st eq "HASH" && (defined $st->{reported_at} || defined $st->{skip});
            push @missing, "#$issue";
        }
        exit 0 unless @missing;
        my $list = join("、", @missing);
        print "merged|$n\tPR #$n はマージされましたが、Issue $list の集計がまだ GitHub に出ていません。/ship の手順7の判定のとおり、usage-report のスキルの『マージを見届けたとき』の手順で集計を出してから、見届けを終えてください。\n";
        exit 0;
    }
    if (($pr->{mergeStateStatus} // "") eq "DIRTY") {
        print "dirty|$n|$sha\tPR #$n は main と衝突しています。/ship の手順7の判定のとおり、手元で main を取り込んでから見届けを続けてください。\n";
        exit 0;
    }
    my $checks = eval { JSON::PP::decode_json($checks_json) };
    exit 0 unless ref $checks eq "ARRAY" && @$checks;
    my @pending = map { $_->{name} // "" } grep { ref $_ eq "HASH" && ($_->{bucket} // "") eq "pending" } @$checks;
    if (@pending) {
        my %seen; my $names = join("、", grep { !$seen{$_}++ } @pending);
        print "pending|$n|$sha\tPR #$n の必須の検査に、結果がまだ出ていないものがあります($names)。/ship の手順7の判定のとおり、gh pr checks $n --watch --required で結果が出るのを待ち、見届けを続けてください。\n";
        exit 0;
    }
    my $all_pass = !grep { !(ref $_ eq "HASH" && ($_->{bucket} // "") =~ /\A(?:pass|skipping)\z/) } @$checks;
    my $review_required = ($pr->{reviewDecision} // "") eq "REVIEW_REQUIRED";
    if ($all_pass && defined $pr->{autoMergeRequest} && !$review_required) {
        print "merging|$n|$sha\tPR #$n は必須の検査がすべて通り、自動マージの予約があります。/ship の手順7の判定のとおり、マージされるまで見届けを続けてください。\n";
        exit 0;
    }
    my %gated;
    if (open my $fh, "<", $expected) {
        local $/; my $e = eval { JSON::PP::decode_json(<$fh>) }; close $fh;
        if (ref $e eq "HASH" && ref $e->{checks} eq "ARRAY") {
            $gated{$_->{context}} = 1 for grep { ref $_ eq "HASH" && $_->{approval_gated} && defined $_->{context} } @{ $e->{checks} };
        }
    }
    my @red = map { $_->{name} // "" } grep { ref $_ eq "HASH" && ($_->{bucket} // "") =~ /\A(?:fail|cancel)\z/ } @$checks;
    exit 0 if grep { !$gated{$_} } @red;
    exit 0 unless $review_required || @red;
    my $beat;
    if (open my $fh, "<", "$state_dir/approval-wait-$n") { $beat = <$fh>; close $fh; }
    exit 0 if defined $beat && $beat =~ /\A([0-9]+)\s*\z/ && abs(time - $1) <= 300;
    print "approval|$n|$sha\tPR #$n は所有者の承認を待っていますが、承認を待つコマンドが動いていません。/ship の手順7の判定のとおり、bash .claude/scripts/ship/wait-approval.sh $n を Bash の run_in_background で動かしてから返答を終えてください。手順7の判定で承認待ちに当たらないと分かったとき(dependency-cooldown に記録のコメントが無いときなど)は、そのことを書いて返答を終えてください。\n";
' -- "$pr_json" "$checks_json" "$usage_dir" "$project_dir/.github/audit/required-checks.json" "$state_dir" 2>/dev/null)

[ -n "$verdict" ] || exit 0

key=${verdict%%$'\t'*}
message=${verdict#*$'\t'}
case "$key" in
    merged\|*) scope=$(extract session_id) ;;
    *) scope=$(extract prompt_id); [ -n "$scope" ] || scope=$(extract session_id) ;;
esac
key="${scope:-unknown}|$key"

record="$state_dir/blocked.txt"
if [ -f "$record" ] && grep -qxF -- "$key" "$record"; then
    # 同じ状態ではすでに1回止めた。所有者の指示で止まるときのために通す
    exit 0
fi
# 止めた組を残せないときは、同じ状態で止め続けないように通す
mkdir -p "$state_dir" 2>/dev/null || exit 0
if ! {
    [ -f "$record" ] && tail -n 49 "$record"
    printf '%s\n' "$key"
} >"$record.tmp.$$" 2>/dev/null; then
    rm -f "$record.tmp.$$"
    exit 0
fi
if ! mv -f "$record.tmp.$$" "$record" 2>/dev/null; then
    rm -f "$record.tmp.$$"
    exit 0
fi

cat >&2 <<MSG
${message}
所有者がチャットで見届けをやめるよう書いたときは、そのことを書いて返答を終えてください。このフックは、同じ状態では1回だけ止めます。
MSG
exit 2
