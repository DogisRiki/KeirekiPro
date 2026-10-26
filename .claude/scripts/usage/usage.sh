#!/bin/bash
# =====================================================================
# 集計の入口のコマンド
#
# 使い方: bash .claude/scripts/usage/usage.sh <サブコマンド> [引数] [--session <ID>]
#   mark <spec-fix|same-failure|switch-to-spec> [--stage <段階>] [--issue <N>]
#     往復と手戻りの印を marks.jsonl に1行足す。標準出力には何も出さない
#   pending
#     まだ出していない Issue と、一覧か案の索引への書き込みが残った Issue の番号を
#     {"issues":[<番号>, ...]} の1行で出す
#   draft <N>
#     Issue N の錠の中で、Issue N が集計の対象かを確かめる。対象でなければ、集計しない印を
#     issues/<N>.json に書いて(書かないこともある)2 で終わる。出し済みなら、一覧の行と案の索引を足し直して 2 で終わる。
#     対象なら、会話の記録を抜き出し、集計の下書きを drafts/<N>/ に作り、下書きの場所と比べの要約と見分けられなかった
#     再開の回数を {"draft":<場所>,"compare":{...},"unknown":{...}} の1行で出す。この PC に記録が無ければ 2 で終わる
#   backfill-list
#     さかのぼりの集計の対象の Issue を、終了日の古い順(同じ日なら番号の小さい順)に、仕組みを main に入れた Issue のうち
#     閉じる PR をまだ待つ Issue と合わせて {"issues":[<番号>, ...],"waiting":[<番号>, ...]} の1行で出す。
#     仕組みが main に入る前なら、gh を呼ばずに 2 で終わる
#   publish <N> --findings <所見のファイル>
#     Issue N の錠の中で、所見のファイルに手元の場所・PC のユーザー名・git の user.email の値が無いことと、出し済みでないことと、
#     drafts/<N>/ の下書きを作ってから60分以内であることを確かめ、Issue N に集計のコメントを書く。出し済みなら、draft と同じく
#     一覧の行と案の索引を足し直して 2 で終わる。集計のコメントを書けたら、一覧か案の索引に書けなくても 0 で終わり、
#     {"failed":[書けなかった書き込み],"owner":"yes|no|unknown","proposals":[案の ID],"url":<集計のコメントの URL>} の1行を出す
#   proposals
#     まだ答えていない案を、github.pl proposals-open の JSON の1行で出す
#   proposal <案の ID> filed|declined
#     案を、案の索引と issues/<N>.json の proposals_pending から外す
#   owner yes|no
#     state.json の owner を真か偽にする
#   session-context
#     会話の始めのフックが Claude の文脈に入れる、まだ出していない集計と、まだ答えていない案を知らせる文を、1行ずつ出す。
#     gh は読むだけに使う。gh が失敗するか10秒を超えたときと、仕組みが main に入った時刻を取れないときは、何も出さずに 0 で終わる
# --session <ID> は、並行作業の仕組みが会話の始めに渡す、その会話の ID である。どのサブコマンドも受ける。
# 手元の記録の置き場所は <git の共通ディレクトリ>/keirekipro-usage/ である。
# 終了コード: 成功は 0、何もしなかったときは 2、失敗は 1(標準エラーに理由を日本語の1文で出す)
# 前提: bash 3.2 以上・perl(JSON::PP)・git・gh。macOS で動く書き方だけを使う
# =====================================================================
set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
GITHUB="$HERE/github.pl"
CONFIG_PATH=.claude/scripts/usage/usage-config.json

fail() {
    printf 'usage.sh: %s\n' "$1" >&2
    exit 1
}

SESSION=
ARGS=()
while [ $# -gt 0 ]; do
    case "$1" in
    --session)
        [ $# -ge 2 ] && [ -n "$2" ] || fail "--session のあとに会話の ID が無い。"
        SESSION=$2
        shift 2
        ;;
    *)
        ARGS+=("$1")
        shift
        ;;
    esac
done
[ ${#ARGS[@]} -gt 0 ] || fail "サブコマンドを mark・pending・draft・backfill-list・publish・proposals・proposal・owner・session-context のどれかにする。"

# Claude が Bash で cd したままでも同じ記録の置き場所を使うように、git を作業フォルダの最上位で動かす
TOP=$(git rev-parse --show-toplevel 2>/dev/null) || fail "git のリポジトリの作業フォルダの中で呼ぶ。"
COMMON=$(git -C "$TOP" rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || fail "git の共通ディレクトリを求められなかった。"
STATE="$COMMON/keirekipro-usage"

ensure_state() {
    mkdir -p "$STATE/issues" || fail "手元の記録の置き場所 $STATE を作れなかった。"
}

# github.pl を作業フォルダの最上位で呼ぶ
github() { (cd "$TOP" && perl "$GITHUB" "$@"); }

# 仕組みが main に入った時刻(データのファイルを足したコミットの時刻)を出す。origin/main かそのコミットが無ければ何も出さない
system_time() {
    git -C "$TOP" rev-parse -q --verify refs/remotes/origin/main >/dev/null || return 0
    git -C "$TOP" log origin/main --first-parent --diff-filter=A --format=%cI -1 -- "$CONFIG_PATH" 2>/dev/null ||
        fail "origin/main の履歴を読めなかった。"
}

# Issue の錠 locks/issue-<N> を mkdir で取り、終わるときに外す。錠が古いとみなす時間(600秒)より古ければ、
# 錠の持ち主が止まったとみなして取り直す。テストだけが KP_USAGE_TEST_ISSUE_LOCK_STALE で短くする
ISSUE_LOCK=
lock_issue() {
    local dir="$STATE/locks/issue-$1" stale=600
    case "${KP_USAGE_TEST_ISSUE_LOCK_STALE-}" in '' | *[!0-9]*) ;; *) stale=$KP_USAGE_TEST_ISSUE_LOCK_STALE ;; esac
    mkdir -p "$STATE/locks" || fail "錠の置き場所 $STATE/locks を作れなかった。"
    until mkdir "$dir" 2>/dev/null; do
        # 錠の持ち主がちょうど外したときは、すぐに取り直す
        [ -d "$dir" ] || { mkdir "$dir" 2>/dev/null && break; fail "Issue の錠 $dir を作れなかった。"; }
        # 待っている間に止められても錠を残さないように、待つ繰り返しは bash で回す
        if perl -e 'my @s = stat $ARGV[0]; exit(@s && time - $s[9] > $ARGV[1] ? 0 : 1)' "$dir" "$stale"; then
            rmdir "$dir" 2>/dev/null || sleep 1
        else
            sleep 1
        fi
    done
    ISSUE_LOCK=$dir
    trap 'rmdir "$ISSUE_LOCK" 2>/dev/null' EXIT
}

# 標準エラーを一時ファイルに受けてコマンドを動かし、失敗したら最後の1行を理由に添えて 1 で終わる: checked <失敗の文> <コマンド>...
# 標準出力はそのまま出す
checked() {
    local what=$1 why
    shift
    if "$@" 2>"$STATE/.err.$$"; then
        rm -f "$STATE/.err.$$"
        return 0
    fi
    why=$(tail -n 1 "$STATE/.err.$$" 2>/dev/null)
    rm -f "$STATE/.err.$$"
    fail "${what}(${why:-理由の出力なし})。"
}

# issues/<N>.json の欄を書く: edit_issue <N> skip <印> <closedAt か -> | edit_issue <N> reported|published <集計のコメントの URL>
# skip は集計しない印を書く。reported は、まだ出し済みと書かれていなければ、出した時刻と URL を書いて出し済みにする。
# published は、publish が集計のコメントを書いたときに、出した時刻と URL と、出した時刻の7日後の list_checked_until を書く。
# ほかの欄は残す。ファイルがあるのに JSON のオブジェクトとして読めないときは、ほかの欄を失わないように書かない
edit_issue() {
    perl -MJSON::PP -MPOSIX -e '
        my ($f, $mode, @v) = @ARGV;
        my $J = JSON::PP->new->utf8->canonical;
        my $d = {};
        if (-e $f) {
            open(my $in, "<:raw", $f) or exit 1;
            local $/;
            my $x = eval { $J->decode(<$in> // "") };
            close $in;
            exit 1 unless ref $x eq "HASH";
            $d = $x;
        }
        if ($mode eq "skip") {
            $d->{skip} = $v[0];
            $d->{closed_at} = $v[1] eq "-" ? undef : $v[1];
        } elsif ($mode eq "published") {
            my $t = time;
            $d->{reported_at} = POSIX::strftime("%Y-%m-%dT%H:%M:%SZ", gmtime $t);
            $d->{list_checked_until} = POSIX::strftime("%Y-%m-%dT%H:%M:%SZ", gmtime($t + 7 * 86400));
            $d->{report_url} = $v[0];
        } else {
            exit 0 if defined $d->{reported_at};
            $d->{reported_at} = POSIX::strftime("%Y-%m-%dT%H:%M:%SZ", gmtime);
            $d->{report_url} = $v[0];
        }
        my $tmp = "$f.tmp.$$";
        open(my $o, ">:raw", $tmp) or exit 1;
        my $ok = print $o $J->encode($d), "\n";
        $ok = close($o) && $ok;
        exit 0 if $ok && rename($tmp, $f);
        unlink $tmp;
        exit 1;
    ' "$STATE/issues/$1.json" "${@:2}" || fail "$STATE/issues/$1.json に書けなかった。"
}

cmd_mark() {
    local kind=${1-} stage='' issue='' branch
    case "$kind" in
    spec-fix | same-failure | switch-to-spec) shift ;;
    *) fail "mark の種類を spec-fix・same-failure・switch-to-spec のどれかにする。" ;;
    esac
    while [ $# -gt 0 ]; do
        case "$1" in
        --stage)
            [ $# -ge 2 ] && [ -n "$2" ] || fail "--stage のあとに段階の名前が無い。"
            stage=$2
            shift 2
            ;;
        --issue)
            [ $# -ge 2 ] || fail "--issue のあとに Issue の番号が無い。"
            # report.pl の issue_no と同じく、0で始まらない10桁までの数だけを受ける
            case "$2" in '' | 0* | *[!0-9]* | ???????????*) fail "--issue のあとに Issue の番号を書く。" ;; esac
            issue=$2
            shift 2
            ;;
        *) fail "mark が知らない引数 $1 を受けた。" ;;
        esac
    done
    branch=$(git -C "$TOP" symbolic-ref -q --short HEAD) || branch=
    ensure_state
    perl -MJSON::PP -e '
        my ($f, $session, $kind, $stage, $issue, $branch) = @ARGV;
        my $row = { ts => time, session => length $session ? $session : undef, kind => $kind,
            stage => length $stage ? $stage : undef, issue => length $issue ? $issue + 0 : undef,
            branch => length $branch ? $branch : undef };
        open(my $fh, ">>:raw", $f) or exit 1;
        my $ok = print $fh JSON::PP->new->canonical->encode($row), "\n";
        close($fh) && $ok or exit 1;
    ' "$STATE/marks.jsonl" "$SESSION" "$kind" "$stage" "$issue" "$branch" || fail "$STATE/marks.jsonl に印を書けなかった。"
}

cmd_pending() {
    [ $# -eq 0 ] || fail "pending は引数を受けない。"
    local sys
    sys=$(system_time) || exit 1
    if [ -z "$sys" ]; then
        printf '{"issues":[]}\n'
        return 0
    fi
    pending_select "$sys" pending
}

# まだ出していない Issue と、一覧か案の索引への書き込みが残った Issue を、{"issues":[...]} の1行で出す: pending_select <仕組みが main に入った時刻> pending|context
# context のときは、ほかの Issue のうち、出してから7日の間(list_checked_until がいまより後)の Issue を recent に足す
pending_select() {
    local sys=$1 mode=$2 since list
    # GitHub の検索がどの時間帯で日付を読んでも落とさないように、協定世界時の日付の前の日から探す
    since=$(perl -MTime::Local=timegm -MPOSIX=strftime -e '
        my ($y, $mo, $d, $h, $mi, $s, $z, $sg, $oh, $om) = $ARGV[0] =~ /\A(\d{4})-(\d\d)-(\d\d)T(\d\d):(\d\d):(\d\d)(Z|([+-])(\d\d):(\d\d))\z/ or exit 1;
        my $t = timegm($s, $mi, $h, $d, $mo - 1, $y);
        $t -= ($sg eq "+" ? 1 : -1) * ($oh * 3600 + $om * 60) if $z ne "Z";
        print strftime("%Y-%m-%d", gmtime($t - 86400));
    ' "$sys") || fail "仕組みが main に入った時刻 $sys を読めなかった。"
    ensure_state
    list=$(gh issue list --state closed --search "closed:>=$since" --limit 200 --json number,closedAt 2>"$STATE/.gh-err.$$") || {
        local why
        why=$(tail -n 1 "$STATE/.gh-err.$$" 2>/dev/null)
        rm -f "$STATE/.gh-err.$$"
        fail "閉じた Issue を gh issue list で読めなかった(${why:-理由の出力なし})。"
    }
    rm -f "$STATE/.gh-err.$$"
    printf '%s' "$list" | perl -MJSON::PP -MTime::Local=timegm -e '
        my ($state, $sys, $mode) = @ARGV;
        my $J = JSON::PP->new->utf8->canonical;
        sub epoch {
            my ($v) = @_;
            return undef unless defined $v && !ref $v;
            my ($y, $mo, $d, $h, $mi, $s, $z, $sg, $oh, $om) = $v =~ /\A(\d{4})-(\d\d)-(\d\d)T(\d\d):(\d\d):(\d\d)(?:\.\d+)?(Z|([+-])(\d\d):(\d\d))\z/ or return undef;
            my $t = timegm($s, $mi, $h, $d, $mo - 1, $y);
            $t -= ($sg eq "+" ? 1 : -1) * ($oh * 3600 + $om * 60) if $z ne "Z";
            return $t;
        }
        sub read_json {
            open(my $fh, "<:raw", $_[0]) or return {};
            local $/;
            my $d = eval { $J->decode(<$fh> // "") };
            return ref $d eq "HASH" ? $d : {};
        }
        # list_pending は真、proposals_pending は空でない配列のときに、書き込みが残っている
        sub has { my ($v) = @_; return ref $v eq "ARRAY" ? scalar @$v : $v ? 1 : 0 }
        my $issues = eval { $J->decode(do { local $/; <STDIN> }) };
        die "gh issue list の出力を JSON の配列として読めなかった\n" unless ref $issues eq "ARRAY";
        my $from = epoch($sys);
        # 受け持ちの出来事がある Issue。report.pl の recv_issue と同じく、recv の行と、Issue の番号がある start の段階の印を数える
        # glob はパスの空白で区切るので、extract.pl と report.pl と同じく opendir で読む
        my %recv;
        my @files;
        if (opendir(my $dh, "$state/extract")) {
            @files = map { "$state/extract/$_" } sort grep { /\.jsonl\z/ } readdir $dh;
            closedir $dh;
        }
        for my $f (@files) {
            open(my $fh, "<:raw", $f) or next;
            while (my $l = <$fh>) {
                next if index($l, "\"recv\"") < 0 && index($l, "\"start\"") < 0;
                my $r = eval { $J->decode($l) };
                next unless ref $r eq "HASH";
                my $k = $r->{k} // "";
                next unless $k eq "recv" || ($k eq "stage" && ($r->{name} // "") eq "start");
                next unless defined $r->{issue} && !ref $r->{issue} && $r->{issue} =~ /\A[1-9][0-9]{0,9}\z/;
                $recv{ $r->{issue} + 0 } = 1;
            }
            close $fh;
        }
        my (%out, %recent);
        for my $i (@$issues) {
            next unless ref $i eq "HASH" && defined $i->{number} && !ref $i->{number} && $i->{number} =~ /\A[1-9][0-9]{0,9}\z/;
            my $n = $i->{number} + 0;
            my $at = epoch($i->{closedAt});
            next unless defined $at && $at >= $from;
            my $st = read_json("$state/issues/$n.json");
            next if defined $st->{skip} && defined $st->{closed_at} && !ref $st->{closed_at} && $st->{closed_at} eq $i->{closedAt};
            if (defined $st->{reported_at}) {
                if (has($st->{list_pending}) || has($st->{proposals_pending})) {
                    $out{$n} = 1;
                } else {
                    my $until = epoch($st->{list_checked_until});
                    $recent{$n} = 1 if defined $until && $until > time;
                }
            } elsif ($recv{$n}) {
                $out{$n} = 1;
            }
        }
        my $o = { issues => [ map { $_ + 0 } sort { $a <=> $b } keys %out ] };
        $o->{recent} = [ map { $_ + 0 } sort { $a <=> $b } keys %recent ] if $mode eq "context";
        print $J->encode($o), "\n";
    ' "$STATE" "$sys" "$mode" 2>"$STATE/.perl-err.$$" || {
        local why
        why=$(tail -n 1 "$STATE/.perl-err.$$" 2>/dev/null)
        rm -f "$STATE/.perl-err.$$"
        fail "まだ出していない Issue を決められなかった(${why:-理由の出力なし})。"
    }
    rm -f "$STATE/.perl-err.$$"
}

cmd_draft() {
    [ $# -eq 1 ] || fail "draft には Issue の番号を1つだけ渡す。"
    printf '%s' "$1" | grep -Eq '^[1-9][0-9]{0,9}$' && [ "$(printf '%s' "$1" | wc -l | tr -d ' ')" = 0 ] ||
        fail "draft の Issue の番号を、0で始まらない10桁までの数にする。"
    local n=$1 sysc decision kind mc at rc why
    ensure_state
    lock_issue "$n"

    # 1. データのファイルを足したコミットを origin/main から求める。無ければ仕組みが main に入る前なので何もしない
    checked "origin の main を取り込めなかった" git -C "$TOP" fetch -q origin main
    sysc=$(git -C "$TOP" log origin/main --first-parent --diff-filter=A --format=%H -1 -- "$CONFIG_PATH" 2>/dev/null) ||
        fail "origin/main の履歴を読めなかった。"
    [ -n "$sysc" ] || exit 2

    # 一時ファイルの名前は、終わるときの trap から見えるように関数の外の変数に置く
    prs="$STATE/.draft-prs.$$"
    issue="$STATE/.draft-issue.$$"
    list="$STATE/.draft-list.$$"
    trap 'rm -f "$prs" "$issue" "$list"; rmdir "$ISSUE_LOCK" 2>/dev/null' EXIT

    # 出し済みなら、出し済みと書き、一覧の行と案の索引を足し直して終わる。ほかの PC で出した Issue もここで見つかる
    if find_report "$n"; then
        already_reported "$n" "$REPORTED_URL"
        exit 2
    fi

    # 2〜3. PR と Issue を、report.pl の collect_prs と同じ gh のコマンドで読む
    checked "gh で PR の一覧を読めなかった" \
        gh pr list --state all --base main --limit 1000 --json number,state,body,headRefName,mergedAt,mergeCommit >"$prs"
    checked "gh で Issue $n を読めなかった" gh issue view "$n" --json state,closedAt >"$issue"
    # report.pl の collect_prs と同じ決まりで Issue の PR を選び、判定を「種類 タブ 閉じる PR の mergeCommit タブ closedAt」の1行で出す。
    # 空の欄は - にする(read がタブの続きを1つにまとめるため)
    decision=$(perl -MJSON::PP -e '
        my ($n, $sysc, $pf, $if) = @ARGV;
        my $J = JSON::PP->new->utf8;
        my $load = sub {
            open(my $in, "<:raw", $_[0]) or die "gh の出力を受けたファイルを開けなかった\n";
            local $/;
            my $x = eval { $J->decode(<$in> // "") };
            close $in;
            die "gh の出力を JSON として読めなかった\n" unless ref $x eq $_[1];
            return $x;
        };
        my ($prs, $iss) = ($load->($pf, "ARRAY"), $load->($if, "HASH"));
        my $at = defined $iss->{closedAt} && !ref $iss->{closedAt} && $iss->{closedAt} ne "" ? $iss->{closedAt} : "-";
        my ($system, $last) = (0, undef);
        for my $p (sort { $a->{number} <=> $b->{number} } grep { ref $_ eq "HASH" && defined $_->{number} } @$prs) {
            my $st = $p->{state} // "";
            next unless $st eq "MERGED" || $st eq "CLOSED";
            my $body = defined $p->{body} && !ref $p->{body} ? $p->{body} : "";
            my $closes = $body =~ /^Closes #$n(?![0-9])/m;
            next unless $closes || $body =~ /^Refs: #$n(?![0-9])/m;
            my $mc = ref $p->{mergeCommit} eq "HASH" ? $p->{mergeCommit}{oid} : undef;
            $system = 1 if defined $mc && !ref $mc && $mc eq $sysc;
            next unless $closes && $st eq "MERGED";
            # report.pl と同じく、閉じる PR のマージの時刻を読めなければ先へ進まない。GitHub の時刻は UTC の Z で終わる形なので、
            # report.pl の iso_epoch より狭い形だけを受けて文字列で比べる。違う形が来たら、選び違えないように 1 で終わる
            my $m = $p->{mergedAt};
            die "PR #$p->{number} のマージの時刻を読めなかった\n"
                unless defined $m && !ref $m && $m =~ /\A[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z\z/;
            $last = { number => $p->{number}, at => $m, mc => $mc } if !defined $last || $m gt $last->{at};
        }
        die "PR #$last->{number} のマージのコミットを読めなかった\n"
            if defined $last && !(defined $last->{mc} && !ref $last->{mc} && $last->{mc} =~ /\A[0-9a-f]{7,64}\z/);
        my $closed = ($iss->{state} // "") eq "CLOSED";
        if ($system) { print "system-pr\t-\t$at\n" }
        elsif (defined $last) { print "ancestor\t$last->{mc}\t$at\n" }
        elsif ($closed) { print "no-merged-pr\t-\t$at\n" }
        else { print "open\t-\t-\n" }
    ' "$n" "$sysc" "$prs" "$issue" 2>"$STATE/.err.$$") || {
        why=$(tail -n 1 "$STATE/.err.$$" 2>/dev/null)
        rm -f "$STATE/.err.$$"
        fail "Issue $n が集計の対象かを、gh から読んだ PR の一覧と Issue で決められなかった(${why:-理由の出力なし})。"
    }
    rm -f "$STATE/.err.$$"
    IFS="$(printf '\t')" read -r kind mc at <<EOF
$decision
EOF
    case "$kind" in
    system-pr | no-merged-pr)
        edit_issue "$n" skip "$kind" "$at"
        exit 2
        ;;
    open) exit 2 ;;
    ancestor) ;;
    *) fail "Issue $n が集計の対象かを決められなかった。" ;;
    esac

    # 4. 閉じる PR のうち最後にマージされた PR が、データのファイルを足したコミットの祖先なら、仕組みが入る前の Issue である
    rc=0
    git -C "$TOP" merge-base --is-ancestor "$mc" "$sysc" 2>/dev/null || rc=$?
    case "$rc" in
    0)
        edit_issue "$n" skip before-system "$at"
        exit 2
        ;;
    1) ;;
    *) fail "Issue $n の閉じる PR のコミット $mc が手元に無く、仕組みが入る前の PR かを確かめられなかった。" ;;
    esac

    # 5. この PC の会話の記録の続きを抜き出す。ほかの呼び出しが読んでいる記録は、読み終わるのを待ってから続きを読む。
    # 消した worktree の会話も読むように、--repo には worktree でなく本体の作業フォルダ(共通ディレクトリの親)を渡す。
    # 途中までしか抜き出していない記録で集計を作らないように、抜き出しに失敗したら集計を作らない
    checked "会話の記録を抜き出せなかった" \
        perl "$HERE/extract.pl" --state "$STATE" --all --wait --repo "$(dirname "$COMMON")"

    # 6. 一覧の過去の行を読み、集計を作って drafts/<N>/ に書く。report.pl は、記録が無ければ 2 で終わる
    checked "gh で一覧の行を読めなかった" github list-read >"$list"
    rc=0
    (cd "$TOP" && perl "$HERE/report.pl" --state "$STATE" --config "$HERE/usage-config.json" --issue "$n" \
        --out "$STATE/drafts/$n" --list "$list") 2>"$STATE/.err.$$" || rc=$?
    why=$(tail -n 1 "$STATE/.err.$$" 2>/dev/null)
    rm -f "$STATE/.err.$$"
    case "$rc" in
    0) ;;
    2) exit 2 ;;
    *) fail "Issue $n の集計を作れなかった(${why:-理由の出力なし})。" ;;
    esac

    # 7. 下書きの場所と、過去の行との比べの要約と、見分けられなかった再開の値ごとの回数を1行の JSON で出す
    perl -MJSON::PP -e '
        my ($dir) = @ARGV;
        my $J = JSON::PP->new->utf8->canonical;
        my $load = sub {
            open(my $in, "<:raw", "$dir/$_[0]") or die "下書きの $_[0] を読めなかった\n";
            local $/;
            my $x = eval { $J->decode(<$in> // "") };
            die "下書きの $_[0] を JSON として読めなかった\n" unless ref $x eq "HASH";
            return $x;
        };
        my ($cmp, $unk) = ($load->("compare.json"), $load->("unknown.json"));
        my @values = map { my $v = $_; +{ map { ($_ => $v->{$_}) } qw(name value_text median_text ratio rows) } }
            grep { ref $_ eq "HASH" } @{ ref $cmp->{values} eq "ARRAY" ? $cmp->{values} : [] };
        print $J->encode({ draft => $dir, compare => { past_rows => $cmp->{past_rows}, values => \@values }, unknown => $unk }), "\n";
    ' "$STATE/drafts/$n" 2>"$STATE/.err.$$" || {
        why=$(tail -n 1 "$STATE/.err.$$" 2>/dev/null)
        rm -f "$STATE/.err.$$"
        fail "Issue $n の下書きの要約を出せなかった(${why:-理由の出力なし})。"
    }
    rm -f "$STATE/.err.$$"
}

cmd_backfill_list() {
    [ $# -eq 0 ] || fail "backfill-list は引数を受けない。"
    local sysc rows kind n mc rc why issues='' waiting=''
    ensure_state

    # 1. draft と同じく、データのファイルを足したコミットを origin/main から求める。無ければ仕組みが main に入る前なので何もしない
    checked "origin の main を取り込めなかった" git -C "$TOP" fetch -q origin main
    sysc=$(git -C "$TOP" log origin/main --first-parent --diff-filter=A --format=%H -1 -- "$CONFIG_PATH" 2>/dev/null) ||
        fail "origin/main の履歴を読めなかった。"
    [ -n "$sysc" ] || exit 2

    # 2. 仕組みが入る前の会話も含めて、この PC の会話の記録を抜き出す。消した worktree の会話も読むように、本体の作業フォルダを渡す
    checked "会話の記録を抜き出せなかった" \
        perl "$HERE/extract.pl" --state "$STATE" --all --wait --repo "$(dirname "$COMMON")"

    # 3〜4. PR を、report.pl の collect_prs と同じ gh のコマンドで1回だけ読む
    prs="$STATE/.backfill-prs.$$"
    trap 'rm -f "$prs"' EXIT
    checked "gh で PR の一覧を読めなかった" \
        gh pr list --state all --base main --limit 1000 --json number,state,body,headRefName,mergedAt,mergeCommit >"$prs"
    # 候補を集め、出し済みの Issue を除き、終了日と番号の順に「種類 タブ 番号 タブ 閉じる PR の mergeCommit」の行で出す。
    # 種類は、仕組みを入れた Issue の keep と、祖先かを確かめる check と、閉じる PR をまだ待つ wait である
    rows=$(perl -MJSON::PP -MTime::Local=timegm -MPOSIX=strftime -e '
        my ($state, $sysc, $pf) = @ARGV;
        my $J = JSON::PP->new->utf8;
        sub read_json {
            open(my $fh, "<:raw", $_[0]) or return undef;
            local $/;
            my $d = eval { $J->decode(<$fh> // "") };
            close $fh;
            return $d;
        }
        # list_pending は真、proposals_pending は空でない配列のときに、書き込みが残っている
        sub has { my ($v) = @_; return ref $v eq "ARRAY" ? scalar @$v : $v ? 1 : 0 }
        my $prs = read_json($pf);
        die "gh の出力を JSON の配列として読めなかった\n" unless ref $prs eq "ARRAY";
        # 手元の記録の recv と stage の行の Issue の番号と、branch の行のブランチの名前。glob はパスの空白で区切るので opendir で読む
        my (%cand, %branch, @files);
        if (opendir(my $dh, "$state/extract")) {
            @files = map { "$state/extract/$_" } sort grep { /\.jsonl\z/ } readdir $dh;
            closedir $dh;
        }
        for my $f (@files) {
            open(my $fh, "<:raw", $f) or next;
            while (my $l = <$fh>) {
                next if index($l, "\"recv\"") < 0 && index($l, "\"stage\"") < 0 && index($l, "\"branch\"") < 0;
                my $r = eval { $J->decode($l) };
                next unless ref $r eq "HASH";
                my $k = $r->{k} // "";
                if ($k eq "branch") {
                    $branch{ $r->{name} } = 1 if defined $r->{name} && !ref $r->{name} && length $r->{name};
                } elsif ($k eq "recv" || $k eq "stage") {
                    $cand{ $r->{issue} + 0 } = 1 if defined $r->{issue} && !ref $r->{issue} && $r->{issue} =~ /\A[1-9][0-9]{0,9}\z/;
                }
            }
            close $fh;
        }
        my @prs = sort { $a->{number} <=> $b->{number} } grep { ref $_ eq "HASH" && defined $_->{number} && !ref $_->{number} } @$prs;
        my $body = sub { defined $_[0]{body} && !ref $_[0]{body} ? $_[0]{body} : "" };
        my $oid = sub { my $m = $_[0]{mergeCommit}; ref $m eq "HASH" && defined $m->{oid} && !ref $m->{oid} ? $m->{oid} : undef };
        # 手元の記録のブランチの PR と、仕組みを入れた PR が、本文の行頭に書いた Issue の番号を候補に足す
        for my $p (@prs) {
            my $head = defined $p->{headRefName} && !ref $p->{headRefName} ? $p->{headRefName} : "";
            my $mc = $oid->($p);
            next unless $branch{$head} || (defined $mc && $mc eq $sysc);
            for my $v ($body->($p) =~ /^(?:Closes|Refs:) #([0-9]+)(?![0-9])/mg) {
                $cand{ $v + 0 } = 1 if $v =~ /\A[1-9][0-9]{0,9}\z/;
            }
        }
        my (@rows, @wait);
        for my $n (sort { $a <=> $b } keys %cand) {
            # 6. 出し済みで、一覧と案の索引への書き込みが残っていない Issue を除く
            my $st = read_json("$state/issues/$n.json");
            next if ref $st eq "HASH" && defined $st->{reported_at} && !has($st->{list_pending}) && !has($st->{proposals_pending});
            # 5. draft と同じ決まりで、仕組みを入れた Issue かと、閉じる PR のうち最後にマージされた PR を決める
            my ($system, $last) = (0, undef);
            for my $p (@prs) {
                my $s = $p->{state} // "";
                next unless $s eq "MERGED" || $s eq "CLOSED";
                my $b = $body->($p);
                my $closes = $b =~ /^Closes #$n(?![0-9])/m;
                next unless $closes || $b =~ /^Refs: #$n(?![0-9])/m;
                my $mc = $oid->($p);
                $system = 1 if defined $mc && $mc eq $sysc;
                next unless $closes && $s eq "MERGED";
                my $m = $p->{mergedAt};
                die "PR #$p->{number} のマージの時刻を読めなかった\n"
                    unless defined $m && !ref $m && $m =~ /\A[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z\z/;
                $last = { number => $p->{number}, at => $m, mc => $mc } if !defined $last || $m gt $last->{at};
            }
            if (!defined $last) {
                push @wait, $n if $system;
                next;
            }
            die "PR #$last->{number} のマージのコミットを読めなかった\n"
                unless defined $last->{mc} && $last->{mc} =~ /\A[0-9a-f]{7,64}\z/;
            # 7. 終了日は、report.pl と同じく、最後にマージされた閉じる PR の mergedAt を所有者の PC の時間帯の日付にしたものである
            my ($y, $mo, $d, $h, $mi, $sec) = $last->{at} =~ /\A(\d+)-(\d+)-(\d+)T(\d+):(\d+):(\d+)Z\z/;
            my $date = strftime("%Y-%m-%d", localtime timegm($sec, $mi, $h, $d, $mo - 1, $y));
            push @rows, [ $date, $n, $system ? "keep" : "check", $last->{mc} ];
        }
        print "$_->[2]\t$_->[1]\t$_->[3]\n" for sort { $a->[0] cmp $b->[0] || $a->[1] <=> $b->[1] } @rows;
        print "wait\t$_\t-\n" for @wait;
    ' "$STATE" "$sysc" "$prs" 2>"$STATE/.err.$$") || {
        why=$(tail -n 1 "$STATE/.err.$$" 2>/dev/null)
        rm -f "$STATE/.err.$$"
        fail "さかのぼりの集計の対象を、手元の記録と gh から読んだ PR の一覧で決められなかった(${why:-理由の出力なし})。"
    }
    rm -f "$STATE/.err.$$"

    # 5. 仕組みを入れた Issue のほかは、閉じる PR のうち最後にマージされた PR がデータのファイルを足したコミットの祖先の Issue だけを残す
    while IFS="$(printf '\t')" read -r kind n mc; do
        case "$kind" in
        keep) issues="$issues${issues:+,}$n" ;;
        wait) waiting="$waiting${waiting:+,}$n" ;;
        check)
            rc=0
            git -C "$TOP" merge-base --is-ancestor "$mc" "$sysc" 2>/dev/null || rc=$?
            case "$rc" in
            0) issues="$issues${issues:+,}$n" ;;
            1) ;;
            *) fail "Issue $n の閉じる PR のコミット $mc が手元に無く、仕組みが入る前の PR かを確かめられなかった。" ;;
            esac
            ;;
        esac
    done <<EOF
$rows
EOF
    printf '{"issues":[%s],"waiting":[%s]}\n' "$issues" "$waiting"
}

# GitHub に集計のコメントがあった Issue を手元でも出し済みにし、一覧の行と、まだ索引に無い案を足し直す:
# already_reported <N> <集計のコメントの URL>
# 一覧と案の索引の両方を試してから、どちらかに書けなかったら 1 で終わる。書けなかった印は github.pl が issues/<N>.json に残す
already_reported() {
    local n=$1 bad=''
    edit_issue "$n" reported "$2"
    github list-ensure "$n" >/dev/null 2>"$STATE/.err.$$" || bad="一覧の行($(tail -n 1 "$STATE/.err.$$" 2>/dev/null))"
    if perl -MJSON::PP -e '
        open(my $in, "<:raw", $ARGV[0]) or exit 1;
        local $/;
        my $d = eval { JSON::PP->new->utf8->decode(<$in> // "") };
        exit(ref $d eq "HASH" && ref $d->{proposals_pending} eq "ARRAY" && @{ $d->{proposals_pending} } ? 0 : 1);
    ' "$STATE/issues/$n.json"; then
        github proposals-ensure "$n" >/dev/null 2>"$STATE/.err.$$" ||
            bad="${bad:+$bad、}案の索引($(tail -n 1 "$STATE/.err.$$" 2>/dev/null))"
    fi
    rm -f "$STATE/.err.$$"
    [ -z "$bad" ] || fail "出し済みの Issue $n の、${bad}を GitHub に書けなかった。"
}

# Issue N に集計のコメントがあれば、その URL を REPORTED_URL に置いて 0 を返し、無ければ 1 を返す。確かめられなければ 1 で終わる
REPORTED_URL=
find_report() {
    local rc=0 why
    REPORTED_URL=$(github reported "$1" 2>"$STATE/.err.$$") || rc=$?
    why=$(tail -n 1 "$STATE/.err.$$" 2>/dev/null)
    rm -f "$STATE/.err.$$"
    case "$rc" in
    0) return 0 ;;
    3) return 1 ;;
    *) fail "Issue $1 に集計のコメントがあるかを確かめられなかった(${why:-理由の出力なし})。" ;;
    esac
}

# 所見のファイルに、手元の場所(ホームディレクトリと、C:/Users/ C:\Users\ /Users/ /home/ を含む場所)と、PC のユーザー名と、
# git の user.email の値のどれかがあれば 1 を返す: private_in <所見のファイル>
# \ と / を同じとみなし、大文字と小文字を区別せずに比べる。1文字の値はどの文にも当たるので比べない
private_in() {
    local email
    email=$(git -C "$TOP" config user.email 2>/dev/null) || email=
    perl -e '
        my ($f, @needles) = @ARGV;
        open(my $in, "<:raw", $f) or exit 1;
        local $/;
        (my $t = lc(<$in> // "")) =~ tr{\\}{/};
        exit 1 if $t =~ m{/users/|/home/};
        for my $s (@needles) {
            (my $x = lc $s) =~ tr{\\}{/};
            exit 1 if length $x > 1 && index($t, $x) >= 0;
        }
        exit 0;
    ' "$1" "${HOME-}" "${USERPROFILE-}" "${USER-}" "${USERNAME-}" "${LOGNAME-}" "$(id -un 2>/dev/null)" "$email"
}

cmd_publish() {
    [ $# -eq 3 ] && [ "$2" = --findings ] && [ -n "$3" ] || fail "publish には Issue の番号と、--findings <所見のファイル> を渡す。"
    printf '%s' "$1" | grep -Eq '^[1-9][0-9]{0,9}$' && [ "$(printf '%s' "$1" | wc -l | tr -d ' ')" = 0 ] ||
        fail "publish の Issue の番号を、0で始まらない10桁までの数にする。"
    local n=$1 findings=$3 dir max=3600 limit rc out why result url
    [ -f "$findings" ] && [ -r "$findings" ] || fail "所見のファイル $findings を読めなかった。"
    # github.pl は作業フォルダの最上位で動くので、相対の場所を、呼ばれた場所からの場所にする
    case "$findings" in /* | [A-Za-z]:[\\/]*) ;; *) findings="$PWD/$findings" ;; esac
    private_in "$findings" ||
        fail "所見のファイルに、手元の場所か、PC のユーザー名か、git の user.email の値があるので、GitHub に書かなかった。"
    ensure_state
    lock_issue "$n"

    if find_report "$n"; then
        already_reported "$n" "$REPORTED_URL"
        exit 2
    fi

    # draft は Issue ごとに drafts/<N>/ の1つだけに下書きを書き、Issue を閉じる PR が無ければ書かない。
    # 作ってから上限の時間(60分)を過ぎた下書きは、そのあとの作業を数えていないので出さない。テストだけが KP_USAGE_TEST_DRAFT_MAX_AGE で短くする
    case "${KP_USAGE_TEST_DRAFT_MAX_AGE-}" in '' | *[!0-9]*) ;; *) max=$KP_USAGE_TEST_DRAFT_MAX_AGE ;; esac
    dir="$STATE/drafts/$n"
    rc=0
    perl -e '
        open(my $in, "<", $ARGV[0]) or exit 3;
        my $t = <$in>;
        exit 3 unless defined $t && $t =~ /\A([0-9]{1,12})\n?\z/;
        my $age = time - $1;
        exit($age >= 0 && $age <= $ARGV[1] ? 0 : 4);
    ' "$dir/created_at" "$max" || rc=$?
    if [ $((max % 60)) -eq 0 ]; then limit="$((max / 60))分"; else limit="${max}秒"; fi
    case "$rc" in
    0) ;;
    3) fail "Issue $n の下書きが無い。draft を先に呼ぶ。" ;;
    *) fail "Issue $n の下書きは、作ってから${limit}を過ぎている。draft からやり直す。" ;;
    esac

    rc=0
    out=$(github publish "$n" --draft "$dir" --findings "$findings" 2>"$STATE/.err.$$") || rc=$?
    why=$(tail -n 1 "$STATE/.err.$$" 2>/dev/null)
    rm -f "$STATE/.err.$$"
    [ "$rc" -eq 0 ] || fail "Issue $n に集計のコメントを書けなかった(${why:-理由の出力なし})。"

    # github.pl の出力に、state.json の owner(真なら yes、偽なら no、無ければ unknown)を足す
    result=$(perl -MJSON::PP -e '
        my ($out, $sf) = @ARGV;
        my $J = JSON::PP->new->utf8->canonical;
        my $o = eval { $J->decode($out) };
        die "github.pl の出力を JSON のオブジェクトとして読めなかった\n" unless ref $o eq "HASH";
        my $owner = "unknown";
        if (open(my $in, "<:raw", $sf)) {
            local $/;
            my $s = eval { $J->decode(<$in> // "") };
            $owner = $s->{owner} ? "yes" : "no" if ref $s eq "HASH" && ref $s->{owner} eq "JSON::PP::Boolean";
        }
        print $J->encode({ url => $o->{url}, proposals => $o->{proposals}, owner => $owner, failed => $o->{failed} }), "\n";
    ' "$out" "$STATE/state.json" 2>"$STATE/.err.$$") || {
        why=$(tail -n 1 "$STATE/.err.$$" 2>/dev/null)
        rm -f "$STATE/.err.$$"
        fail "Issue $n に集計のコメントを書いたが、結果を読めなかった(${why:-理由の出力なし})。次の draft が出し済みと書き直す。"
    }
    rm -f "$STATE/.err.$$"
    # 集計のコメントの URL を読めなかったときは出し済みと書かない。次の draft が、GitHub の集計のコメントから URL を書く
    url=$(printf '%s' "$result" | perl -MJSON::PP -e 'local $/; my $u = JSON::PP->new->utf8->decode(<STDIN>)->{url}; print $u if defined $u && !ref $u')
    [ -z "$url" ] || edit_issue "$n" published "$url"
    printf '%s\n' "$result"
}

# 会話の始めのフックが文脈に入れる文の行を出す。gh が失敗するか待つ上限(10秒)を超えたら、何も出さずに 0 で終わる。
# 本体を別のプロセスのグループで動かし、上限を超えたら、本体が呼んだ gh ごと止める。テストだけが KP_USAGE_TEST_CONTEXT_TIMEOUT で上限を短くする
cmd_session_context() {
    [ $# -eq 0 ] || fail "session-context は引数を受けない。"
    local sys limit=10
    # 仕組みが main に入った時刻を取れないときは、gh を呼ばずに終わる
    sys=$(system_time 2>/dev/null) || return 0
    [ -n "$sys" ] || return 0
    case "${KP_USAGE_TEST_CONTEXT_TIMEOUT-}" in '' | *[!0-9]*) ;; *) limit=$KP_USAGE_TEST_CONTEXT_TIMEOUT ;; esac
    perl -e '
        my ($limit, @cmd) = @ARGV;
        my $pid = open(my $ph, "-|") // exit 0;
        if (!$pid) {
            setpgrp(0, 0);
            open(STDERR, ">", "/dev/null");
            exec @cmd or exit 1;
        }
        my $out = eval {
            local $SIG{ALRM} = sub { die "timeout\n" };
            alarm $limit;
            my $o = do { local $/; <$ph> };
            my $ok = close $ph;
            alarm 0;
            $ok ? $o : undef;
        };
        if (!defined $out) {
            kill "KILL", -$pid, $pid;
            exit 0;
        }
        print $out;
    ' "$limit" env KP_USAGE_CONTEXT_BODY=1 bash "$HERE/usage.sh" session-context
}

# state.json の owner を、真なら yes、偽なら no、無ければ unknown で出す
owner_state() {
    perl -MJSON::PP -e '
        my $s;
        if (open(my $fh, "<:raw", $ARGV[0])) {
            local $/;
            $s = eval { JSON::PP->new->decode(<$fh> // "") };
        }
        print ref $s eq "HASH" && ref $s->{owner} eq "JSON::PP::Boolean" ? ($s->{owner} ? "yes" : "no") : "unknown";
    ' "$STATE/state.json"
}

# session-context の本体。失敗したら 1 で終わり、cmd_session_context が何も出さない
context_body() {
    local sys owner
    sys=$(system_time) || exit 1
    [ -n "$sys" ] || exit 0
    ensure_state
    # 上限を超えて止められた本体が残した一時ファイルを、ほかの会話の本体が使い終えたころに消す
    find "$STATE" -maxdepth 1 -name '.ctx-*' -mmin +10 -exec rm -f {} + 2>/dev/null
    trap 'rm -f "$STATE/.ctx-sel.$$" "$STATE/.ctx-rows.$$" "$STATE/.ctx-props.$$"' EXIT
    pending_select "$sys" context >"$STATE/.ctx-sel.$$" || exit 1
    printf '[]\n' >"$STATE/.ctx-rows.$$"
    printf '[]\n' >"$STATE/.ctx-props.$$"
    # 出してから7日の間の Issue があるときだけ、一覧の行を読む
    if ! grep -q '"recent":\[\]' "$STATE/.ctx-sel.$$"; then
        github list-read >"$STATE/.ctx-rows.$$" || exit 1
    fi
    owner=$(owner_state)
    if [ "$owner" != no ]; then
        github proposals-open >"$STATE/.ctx-props.$$" || exit 1
    fi
    perl -MJSON::PP -e '
        my ($state, $self, $rowsf, $owner, $propsf) = @ARGV;
        my $J = JSON::PP->new->utf8->canonical;
        sub read_json {
            open(my $fh, "<:raw", $_[0]) or return undef;
            local $/;
            return eval { $J->decode(<$fh> // "") };
        }
        my ($sel, $rows, $props) = map { read_json($_) } $self, $rowsf, $propsf;
        exit 1 unless ref $sel eq "HASH" && ref $rows eq "ARRAY" && ref $props eq "ARRAY";
        my %listed = map { ref $_ eq "HASH" && defined $_->{issue} ? ($_->{issue} => 1) : () } @$rows;
        my %issues = map { $_ => 1 } @{ $sel->{issues} };
        # 一覧に行が無い、出してから7日の間の Issue に、list_pending を書き直す
        for my $n (@{ $sel->{recent} }) {
            next if $listed{$n};
            my $f = "$state/issues/$n.json";
            my $d = read_json($f);
            exit 1 unless ref $d eq "HASH";
            $d->{list_pending} = JSON::PP::true;
            my $tmp = "$f.tmp.$$";
            open(my $o, ">:raw", $tmp) or exit 1;
            my $ok = print $o $J->encode($d), "\n";
            $ok = close($o) && $ok;
            if (!($ok && rename($tmp, $f))) { unlink $tmp; exit 1 }
            $issues{$n} = 1;
        }
        for my $n (sort { $a <=> $b } keys %issues) {
            my $st = read_json("$state/issues/$n.json");
            if (ref $st eq "HASH" && defined $st->{reported_at}) {
                print "[usage] Issue #$n の集計は GitHub に出したが、一覧か案の索引への書き込みが残っている。usage-report のスキルの『次の会話で出すとき』の手順で書き足す。\n";
            } else {
                print "[usage] Issue #$n を閉じる PR がマージされ、集計がまだ GitHub に出ていない。usage-report のスキルの『次の会話で出すとき』の手順で出す。\n";
            }
        }
        my @open = grep { ref $_ eq "HASH" && defined $_->{id} && defined $_->{issue} } @$props;
        if ($owner eq "yes") {
            print "[usage] 会話の相手: 所有者\n";
            print "[usage] まだ答えていない直す案がある: ", join("、", map { "$_->{id}（Issue #$_->{issue}）" } @open),
                "。usage-report のスキルの『案を尋ねるとき』の手順で、案ごとに起票するかを尋ねる。\n" if @open;
        } elsif ($owner eq "unknown" && @open) {
            print "[usage] この PC で Claude と話す人が所有者かどうかが、まだ決まっていない。usage-report のスキルの『所有者かを尋ねるとき』の手順で尋ねる。\n";
        }
    ' "$STATE" "$STATE/.ctx-sel.$$" "$STATE/.ctx-rows.$$" "$owner" "$STATE/.ctx-props.$$" || exit 1
}

cmd_proposals() {
    [ $# -eq 0 ] || fail "proposals は引数を受けない。"
    github proposals-open
}

cmd_proposal() {
    [ $# -eq 2 ] || fail "proposal には案の ID と、filed か declined を渡す。"
    # github.pl の proposal_id と同じ形(0で始まらない10桁までの数と、0で始まらない6桁までの数を - でつなぐ)だけを受ける
    printf '%s' "$1" | grep -Eq '^[1-9][0-9]{0,9}-[1-9][0-9]{0,5}$' && [ "$(printf '%s' "$1" | wc -l | tr -d ' ')" = 0 ] ||
        fail "proposal の案の ID を <Issue の番号>-<番号> の形にする。"
    case "$2" in filed | declined) ;; *) fail "proposal の答えを filed か declined にする。" ;; esac
    # github.pl proposal-remove は、案の索引と、その Issue の issues/<N>.json の proposals_pending の両方から外す
    github proposal-remove "$1"
}

cmd_owner() {
    [ $# -eq 1 ] || fail "owner には yes か no を渡す。"
    case "$1" in yes | no) ;; *) fail "owner の答えを yes か no にする。" ;; esac
    ensure_state
    # 読み直してから owner の欄だけを替え、一時ファイルに書いてから名前を替えて置き換える
    perl -MJSON::PP -e '
        my ($f, $v) = @ARGV;
        my $J = JSON::PP->new->utf8->canonical;
        my $d = {};
        # ファイルがあるのに開けないときと、JSON のオブジェクトとして読めないときは、ほかの欄(list_issue)を失わないように書かない
        if (-e $f) {
            open(my $in, "<:raw", $f) or exit 1;
            local $/;
            my $x = eval { $J->decode(<$in> // "") };
            close $in;
            exit 1 unless ref $x eq "HASH";
            $d = $x;
        }
        $d->{owner} = $v eq "yes" ? JSON::PP::true : JSON::PP::false;
        my $tmp = "$f.tmp.$$";
        open(my $o, ">:raw", $tmp) or exit 1;
        my $ok = print $o $J->encode($d), "\n";
        $ok = close($o) && $ok;
        exit 0 if $ok && rename($tmp, $f);
        unlink $tmp;
        exit 1;
    ' "$STATE/state.json" "$1" || fail "$STATE/state.json に owner を書けなかった。"
}

set -- "${ARGS[@]}"
cmd=$1
shift
case "$cmd" in
mark) cmd_mark "$@" ;;
pending) cmd_pending "$@" ;;
draft) cmd_draft "$@" ;;
backfill-list) cmd_backfill_list "$@" ;;
publish) cmd_publish "$@" ;;
proposals) cmd_proposals "$@" ;;
proposal) cmd_proposal "$@" ;;
owner) cmd_owner "$@" ;;
session-context) if [ -n "${KP_USAGE_CONTEXT_BODY-}" ]; then context_body "$@"; else cmd_session_context "$@"; fi ;;
*) fail "知らないサブコマンド $cmd を受けた。サブコマンドを mark・pending・draft・backfill-list・publish・proposals・proposal・owner・session-context のどれかにする。" ;;
esac
