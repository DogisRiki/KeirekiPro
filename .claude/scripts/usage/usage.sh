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
#   proposals
#     まだ答えていない案を、github.pl proposals-open の JSON の1行で出す
#   proposal <案の ID> filed|declined
#     案を、案の索引と issues/<N>.json の proposals_pending から外す
#   owner yes|no
#     state.json の owner を真か偽にする
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
[ ${#ARGS[@]} -gt 0 ] || fail "サブコマンドを mark・pending・proposals・proposal・owner のどれかにする。"

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
    local sys since list
    sys=$(system_time) || exit 1
    if [ -z "$sys" ]; then
        printf '{"issues":[]}\n'
        return 0
    fi
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
        my ($state, $sys) = @ARGV;
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
        my %out;
        for my $i (@$issues) {
            next unless ref $i eq "HASH" && defined $i->{number} && !ref $i->{number} && $i->{number} =~ /\A[1-9][0-9]{0,9}\z/;
            my $n = $i->{number} + 0;
            my $at = epoch($i->{closedAt});
            next unless defined $at && $at >= $from;
            my $st = read_json("$state/issues/$n.json");
            next if defined $st->{skip} && defined $st->{closed_at} && !ref $st->{closed_at} && $st->{closed_at} eq $i->{closedAt};
            if (defined $st->{reported_at}) {
                $out{$n} = 1 if has($st->{list_pending}) || has($st->{proposals_pending});
            } elsif ($recv{$n}) {
                $out{$n} = 1;
            }
        }
        print $J->encode({ issues => [ map { $_ + 0 } sort { $a <=> $b } keys %out ] }), "\n";
    ' "$STATE" "$sys" 2>"$STATE/.perl-err.$$" || {
        local why
        why=$(tail -n 1 "$STATE/.perl-err.$$" 2>/dev/null)
        rm -f "$STATE/.perl-err.$$"
        fail "まだ出していない Issue を決められなかった(${why:-理由の出力なし})。"
    }
    rm -f "$STATE/.perl-err.$$"
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
proposals) cmd_proposals "$@" ;;
proposal) cmd_proposal "$@" ;;
owner) cmd_owner "$@" ;;
*) fail "知らないサブコマンド $cmd を受けた。サブコマンドを mark・pending・proposals・proposal・owner のどれかにする。" ;;
esac
