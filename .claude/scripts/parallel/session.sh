#!/bin/bash
# =====================================================================
# 着手のときの調べと記録のスクリプト(session.sh)
#
# 使い方: bash .claude/scripts/parallel/session.sh <サブコマンド> ...
#   check-start <N> [--session <ID>]
#       Issue #N に着手してよいかを調べ、標準出力に JSON を1行出す(終了コード0)。
#         folder_conflict  いまの作業フォルダの、ほかの作業中のセッションの記録(session_id started_at last_seen)
#         leftovers        Issue #N の作りかけ(folder is_self kinds branch active_session)
#         branch_only      Issue #N のブランチのうち、どの作業フォルダでも開かれていないもの(branch where)
#         capacity         limit(設定の数)と active(ほかに作業中のセッション。issue folder last_seen)
#       最初に prune を行う。
#   claim <N> --branch <ブランチ> [--session <ID>]
#       Issueの記録 issues/<N>.json を書く。すでにあれば folder branch session_id updated_at を書き直す。
#   end <session_id>
#       所有者が「やめた」と答えたセッションの記録 sessions/<session_id>.json を消す。
#   spec-names
#       すべての作業フォルダの .kiro/specs/ のディレクトリ名を、重ならないように1行ずつ出す。
#   prune
#       作業フォルダが無くなった記録と残った枠の片付け。いまは何もせずに終了コード0で終わる
#       (片付けの中身は、別の小タスクで足す)。
#
# セッションのIDは、--session の値か環境変数 KP_SESSION_ID で渡す。どちらも無ければ、
# いまの作業フォルダのセッションの記録のうち started_at がいちばん古いもの(lib.sh の kp_session_id)。
# 作業中のセッションは、sessions/ の記録のうち、issues/ に同じ session_id か同じ folder の記録があるもの。
# このスクリプトは所有者とやり取りせず、docker を呼ばない。
#
# 終了コード: 0(成功)、64(呼び方の誤り)、69(git のリポジトリの外、設定の値の誤り、記録を書けない)。
# 前提: bash・perl(JSON::PP)・git。jq には依存しない。
# =====================================================================

KP_SESSION_SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=lib.sh
. "$KP_SESSION_SCRIPT_DIR/lib.sh"

_kp_ss_usage() {
    printf '[parallel] session.sh の呼び方の誤り: %s\n' "$*" >&2
    exit 64
}

# Issueの番号を確かめ、先頭の0を除いて出す
_kp_ss_issue_number() {
    case "$1" in
        '' | *[!0-9]*) _kp_ss_usage "Issueの番号 '$1' が数でない" ;;
    esac
    printf '%s\n' "$((10#$1))"
}

# 開かれている作業フォルダ(フォルダがあるもの)の最上位を1行ずつ出す
_kp_ss_worktree_paths() {
    local line path
    git worktree list --porcelain 2>/dev/null | while IFS= read -r line; do
        case "$line" in
            'worktree '*)
                path=${line#worktree }
                [ -d "$path" ] && printf '%s\n' "$path"
                ;;
        esac
    done
}

kp_session_prune() {
    return 0
}

kp_session_check_start() {
    local n="" session="" state sid limit me key ic
    while [ $# -gt 0 ]; do
        case "$1" in
            --session)
                [ $# -ge 2 ] || _kp_ss_usage "--session の値が無い"
                session=$2
                shift 2
                ;;
            -*) _kp_ss_usage "知らないオプション $1" ;;
            *)
                [ -z "$n" ] || _kp_ss_usage "引数が多い: $1"
                n=$(_kp_ss_issue_number "$1") || exit $?
                shift
                ;;
        esac
    done
    [ -n "$n" ] || _kp_ss_usage "check-start <N> [--session <ID>]"

    kp_session_prune || exit $?
    state=$(kp_state_dir) || exit $?
    sid=$(kp_session_id "${session:-${KP_SESSION_ID:-}}") || exit $?
    limit=$(kp_slots) || exit $?
    me=$(kp_folder) || exit $?
    key=$(kp_folder_key) || exit $?
    ic=$(git config --get core.ignorecase 2>/dev/null)

    perl -MJSON::PP -e '
        use strict; use warnings;
        my ($state, $n, $sid, $limit, $me, $me_key, $ic) = @ARGV;
        utf8::decode($_) for ($state, $sid, $me);
        my $json = JSON::PP->new->utf8;

        sub norm { my $p = $_[0] // ""; $p =~ tr/A-Z/a-z/ if $ic eq "true"; $p }
        sub load {
            open my $fh, "<:raw", $_[0] or return undef;
            local $/; my $text = <$fh>; close $fh;
            my $d = eval { $json->decode($text) };
            return ref $d eq "HASH" ? $d : undef;
        }
        sub load_dir {
            my $dir = shift;
            opendir my $dh, $dir or return ();
            my @out;
            for my $name (sort readdir $dh) {
                next unless $name =~ /\.json\z/;
                my $d = load("$dir/$name") or next;
                push @out, $d;
            }
            return @out;
        }
        # git を呼んで標準出力を返す(標準エラーは捨てる)。失敗したら undef
        sub git_out {
            my @args = @_;
            my $pid = open(my $fh, "-|");
            return undef unless defined $pid;
            if (!$pid) {
                open STDERR, ">", "/dev/null";
                exec "git", @args;
                exit 127;
            }
            local $/; my $out = <$fh>;
            close $fh;
            return undef if $?;
            return $out // "";
        }
        sub issue_matches {
            my ($v) = @_;
            return 0 unless defined $v && !ref $v;
            (my $s = $v) =~ s/\A#//;
            return $s =~ /\A0*([0-9]+)\z/ && $1 == $n;
        }
        sub str { my $v = $_[0]; defined $v && !ref $v ? $v : "" }

        my $me_id = norm($me);

        # 開かれている作業フォルダ(フォルダがあるもの)と、そこで開かれているブランチ
        my @worktrees;
        my $list = git_out("worktree", "list", "--porcelain") // "";
        utf8::decode($list);
        my $cur;
        for my $line (split /\n/, $list) {
            if ($line =~ /\Aworktree (.+)\z/) {
                $cur = { path => $1, branch => undef };
                push @worktrees, $cur;
            } elsif ($cur && $line =~ m{\Abranch refs/heads/(.+)\z}) {
                $cur->{branch} = $1;
            } elsif ($cur && $line eq "bare") {
                $cur->{bare} = 1;
            }
        }
        @worktrees = grep { !$_->{bare} && -d $_->{path} } @worktrees;

        my @sessions = load_dir("$state/sessions");
        my @issues = load_dir("$state/issues");
        my $iss = load("$state/issues/$n.json");

        # 作業中のセッション: issues/ に同じ session_id か同じ folder の記録があるもの
        my (%issue_by_sid, %issue_by_folder);
        for my $d (sort { (str($a->{updated_at}) || 0) <=> (str($b->{updated_at}) || 0) } @issues) {
            my $s = str($d->{session_id});
            my $f = norm(str($d->{folder}));
            $issue_by_sid{$s} = $d->{issue} if length $s;
            $issue_by_folder{$f} = $d->{issue} if length $f;
        }
        sub is_active {
            my ($s, $by_sid, $by_folder) = @_;
            my $id = str($s->{session_id});
            my $f = norm(str($s->{folder}));
            return (length $id && exists $by_sid->{$id}) || (length $f && exists $by_folder->{$f});
        }
        # セッションの記録がその作業フォルダのものか(いまの作業フォルダは鍵でも比べる。kp_session_id と同じ規則)
        sub in_folder {
            my ($s, $fid) = @_;
            return 1 if norm(str($s->{folder})) eq $fid;
            return $fid eq $me_id && str($s->{folder_key}) eq $me_key;
        }
        sub by_start { (str($a->{started_at}) || 0) <=> (str($b->{started_at}) || 0) or str($a->{session_id}) cmp str($b->{session_id}) }
        sub brief { my $s = shift; +{ map { $_ => $s->{$_} } qw(session_id started_at last_seen) } }

        # folder_conflict(作業中のセッションだけ。要件3.6・5.1)
        my @conflict = map { brief($_) }
            sort by_start grep { in_folder($_, $me_id) && str($_->{session_id}) ne $sid
                && is_active($_, \%issue_by_sid, \%issue_by_folder) } @sessions;

        # leftovers
        my %handed = map { (norm(str($_)) => 1) } (ref $iss && ref $iss->{handed_over_from} eq "ARRAY" ? @{ $iss->{handed_over_from} } : ());
        my $iss_branch = $iss ? str($iss->{branch}) : "";
        my $own = $iss && length $sid && norm(str($iss->{folder})) eq $me_id && str($iss->{session_id}) eq $sid;
        my @leftovers;
        for my $w (@worktrees) {
            my $fid = norm($w->{path});
            next if $handed{$fid};
            next if $own && $fid eq $me_id;
            my (%kind);
            my @names;
            if (opendir my $sd, "$w->{path}/.kiro/specs") {
                @names = sort grep { !/\A\.\.?\z/ && -d "$w->{path}/.kiro/specs/$_" } readdir $sd;
                closedir $sd;
            }
            for my $name (@names) {
                my $d = load("$w->{path}/.kiro/specs/$name/spec.json") or next;
                my $hit = issue_matches($d->{issue});
                if (!$hit && ref $d->{additional_issues} eq "ARRAY") {
                    $hit = grep { issue_matches($_) } @{ $d->{additional_issues} };
                }
                next unless $hit;
                my $st = git_out("-C", $w->{path}, "status", "--porcelain", "--", ".kiro/specs/$name");
                $kind{spec} = 1 if defined $st && length $st;
            }
            if (length $iss_branch && defined $w->{branch} && $w->{branch} eq $iss_branch) {
                $kind{branch} = 1;
                my $st = git_out("-C", $w->{path}, "status", "--porcelain");
                $kind{changes} = 1 if defined $st && length $st;
            }
            next unless %kind;
            my ($active) = sort by_start
                grep { in_folder($_, $fid) && str($_->{session_id}) ne $sid && is_active($_, \%issue_by_sid, \%issue_by_folder) } @sessions;
            push @leftovers, {
                folder => $w->{path},
                is_self => ($fid eq $me_id ? JSON::PP::true : JSON::PP::false),
                kinds => [ grep { $kind{$_} } qw(spec changes branch) ],
                branch => $w->{branch},
                active_session => ($active ? brief($active) : undef),
            };
        }

        # branch_only
        my @branch_only;
        if (length $iss_branch && !grep { defined $_->{branch} && $_->{branch} eq $iss_branch } @worktrees) {
            if (defined git_out("show-ref", "--verify", "--quiet", "refs/heads/$iss_branch")) {
                push @branch_only, { branch => $iss_branch, where => "local" };
            } elsif (defined git_out("show-ref", "--verify", "--quiet", "refs/remotes/origin/$iss_branch")) {
                push @branch_only, { branch => $iss_branch, where => "remote" };
            }
        }

        # capacity
        my @active;
        for my $s (sort by_start grep { str($_->{session_id}) ne $sid && is_active($_, \%issue_by_sid, \%issue_by_folder) } @sessions) {
            my $id = str($s->{session_id});
            my $issue = length $id && exists $issue_by_sid{$id} ? $issue_by_sid{$id} : $issue_by_folder{ norm(str($s->{folder})) };
            push @active, { issue => $issue, folder => $s->{folder}, last_seen => $s->{last_seen} };
        }

        print JSON::PP->new->utf8->canonical->encode({
            folder_conflict => \@conflict,
            leftovers => \@leftovers,
            branch_only => \@branch_only,
            capacity => { limit => $limit + 0, active => \@active },
        }), "\n";
    ' -- "$state" "$n" "$sid" "$limit" "$me" "$key" "$ic" || exit 69
}

kp_session_claim() {
    local n="" branch="" session="" have_branch=0 state folder sid f now
    while [ $# -gt 0 ]; do
        case "$1" in
            --branch)
                [ $# -ge 2 ] || _kp_ss_usage "--branch の値が無い"
                branch=$2
                have_branch=1
                shift 2
                ;;
            --session)
                [ $# -ge 2 ] || _kp_ss_usage "--session の値が無い"
                session=$2
                shift 2
                ;;
            -*) _kp_ss_usage "知らないオプション $1" ;;
            *)
                [ -z "$n" ] || _kp_ss_usage "引数が多い: $1"
                n=$(_kp_ss_issue_number "$1") || exit $?
                shift
                ;;
        esac
    done
    [ -n "$n" ] && [ "$have_branch" = 1 ] && [ -n "$branch" ] \
        || _kp_ss_usage "claim <N> --branch <ブランチ> [--session <ID>]"

    state=$(kp_state_dir) || exit $?
    folder=$(kp_folder) || exit $?
    sid=$(kp_session_id "${session:-${KP_SESSION_ID:-}}") || exit $?
    mkdir -p "$state/issues" 2>/dev/null || _kp_die69 "記録の置き場所 $state/issues を作れない"
    f="$state/issues/$n.json"
    now=$(date +%s)
    if [ -f "$f" ]; then
        kp_json_write "$f" folder="$folder" branch="$branch" session_id="$sid" updated_at:="$now" \
            || _kp_die69 "Issueの記録 $f を書けない"
    else
        kp_json_write "$f" issue:="$n" folder="$folder" branch="$branch" session_id="$sid" \
            updated_at:="$now" 'handed_over_from:=[]' \
            || _kp_die69 "Issueの記録 $f を書けない"
    fi
}

kp_session_end() {
    local id="${1:-}" state
    [ $# -eq 1 ] && [ -n "$id" ] || _kp_ss_usage "end <session_id>"
    case "$id" in
        . | .. | */* | *\\*) _kp_ss_usage "セッションのID '$id' にパスの区切りが含まれる" ;;
    esac
    state=$(kp_state_dir) || exit $?
    rm -f "$state/sessions/$id.json" || _kp_die69 "セッションの記録 $state/sessions/$id.json を消せない"
}

kp_session_spec_names() {
    [ $# -eq 0 ] || _kp_ss_usage "spec-names は引数を取らない"
    kp_state_dir >/dev/null || exit $?
    local w d
    _kp_ss_worktree_paths | while IFS= read -r w; do
        for d in "$w"/.kiro/specs/*/; do
            [ -d "$d" ] || continue
            basename "$d"
        done
    done | LC_ALL=C sort -u
}

kp_session_main() {
    local cmd="${1:-}"
    [ $# -gt 0 ] && shift
    case "$cmd" in
        check-start) kp_session_check_start "$@" ;;
        claim) kp_session_claim "$@" ;;
        end) kp_session_end "$@" ;;
        spec-names) kp_session_spec_names "$@" ;;
        prune) kp_session_prune "$@" ;;
        *) _kp_ss_usage "サブコマンドは check-start / claim / end / spec-names / prune のどれか" ;;
    esac
}

# 読み込まれただけ(source)のときは本体の処理を動かさない
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    kp_session_main "$@"
fi
