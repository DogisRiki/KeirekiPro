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
#       作業フォルダが無くなった記録と、残った枠と、作業フォルダごとのボリュームと DB を片付け、
#       片付けたことを標準出力に出す。所有者が手で打っても使える。
#         最初に git worktree prune を打ち、ディレクトリが消えた worktree を git の記録から外す
#         sessions/ の記録のうち、folder が無くなったものを消す
#         issues/<N>.json は、folder が無くなっていても branch がローカルかリモートに残っていれば、
#           folder と session_id を空にして残す(check-start の branch_only はこれを引く)。branch がどこにも無ければ消す
#         枠は、lib.sh の取り戻しの条件に当たるものを取り戻す(kp_slot_reclaim)
#         無くなった作業フォルダの鍵のボリューム(kp-nm-<鍵> kp-gradle-project-<鍵>)と DB(kp_<鍵>)を消す。
#           Docker につながらなければ何も消さず、消していない名前を標準エラーに出す。
#           db が動いていなければ DB の片付けだけを飛ばす
#
# セッションのIDは、--session の値か環境変数 KP_SESSION_ID で渡す。どちらも無ければ、
# いまの作業フォルダのセッションの記録のうち started_at がいちばん古いもの(lib.sh の kp_session_id)。
# 作業中のセッションは、sessions/ の記録のうち、issues/ に同じ session_id か同じ folder の記録があるもの。
# このスクリプトは所有者とやり取りしない。docker を呼ぶのは prune(片付けるものがあるとき)だけ。
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

# 作業フォルダのパスの鍵(lib.sh の kp_folder_key と同じ求め方)
_kp_ss_key_of() {
    local hash
    hash=$(_kp_norm_path "$1" | git hash-object --stdin) || return 1
    printf '%s\n' "${hash:0:12}"
}

# エラーの文を1行にする(空の行を除く)
_kp_ss_one_line() {
    local s
    s=$(printf '%s\n' "$1" | grep -v '^[[:space:]]*$' | tr '\n' ' ')
    printf '%s' "${s% }"
}

# 作業フォルダが無くなった鍵のボリュームと DB を消す。
# 標準出力の「消した」には実際に消せたものだけを書き、無いもの以外の失敗(使用中など)は名前つきで標準エラーに出す。
# Docker につながらなければ何も消さず、db が動いていなければ DB の片付けだけを飛ばす。
# どちらのときも、所有者が手で消すときの名前を標準エラーに出す。
_kp_ss_remove_folder_data() { # <鍵>...
    [ $# -gt 0 ] || return 0
    local key name db out db_up=0 manual_vols="" manual_dbs="" removed=""
    for key in "$@"; do
        manual_vols+=" kp-nm-$key kp-gradle-project-$key"
        manual_dbs+=" kp_$key"
    done
    if ! out=$(docker version --format '{{.Server.Version}}' 2>&1); then
        printf '[parallel] Docker につながらないので、作業フォルダごとのボリュームと DB を消していない(鍵 %s): %s\n' \
            "$*" "$(_kp_ss_one_line "$out")" >&2
        printf '[parallel] 手で消すときの名前: ボリューム%s、DB%s\n' "$manual_vols" "$manual_dbs" >&2
        return 0
    fi
    for key in "$@"; do
        for name in "kp-nm-$key" "kp-gradle-project-$key"; do
            if out=$(docker volume rm "$name" 2>&1); then
                removed+=" $name"
            else
                case "$out" in
                    *[Nn]o\ such\ volume*) ;;
                    *) printf '[parallel] ボリューム %s を消せない: %s\n' "$name" "$(_kp_ss_one_line "$out")" >&2 ;;
                esac
            fi
        done
    done
    out=$(docker compose -p keirekipro ps --status running -q db 2>/dev/null) && [ -n "$out" ] && db_up=1
    if [ "$db_up" = 1 ]; then
        for key in "$@"; do
            db="kp_$key"
            if ! out=$(docker compose -p keirekipro exec -T db psql -U postgres -tAc \
                "SELECT 1 FROM pg_database WHERE datname='$db'" 2>&1); then
                printf '[parallel] DB %s があるかを確かめられない: %s\n' "$db" "$(_kp_ss_one_line "$out")" >&2
                continue
            fi
            [ "$(_kp_ss_one_line "$out")" = 1 ] || continue
            if out=$(docker compose -p keirekipro exec -T db psql -U postgres -c "DROP DATABASE IF EXISTS $db" 2>&1); then
                removed+=" $db"
            else
                printf '[parallel] DB %s を消せない: %s\n' "$db" "$(_kp_ss_one_line "$out")" >&2
            fi
        done
    else
        printf '[parallel] db が動いていないので、DB を消していない(手で消すときの名前: DB%s)\n' "$manual_dbs" >&2
    fi
    if [ -n "$removed" ]; then
        printf '[parallel] 片付け: 作業フォルダごとのボリュームと DB を消した:%s\n' "$removed"
    fi
}

# 作業フォルダが無くなった記録と、残った枠と、作業フォルダごとのボリュームと DB を片付ける。
# 片付けたことを標準出力に出す(check-start から呼ぶときは捨てる)。
kp_session_prune() {
    [ $# -eq 0 ] || _kp_ss_usage "prune は引数を取らない"
    local nl=$'\n'
    # alive_keys と seen は、鍵を改行で挟んで並べた一覧(連想配列を使わない)
    local state ic p key alive="" alive_keys="$nl" seen="$nl" actions kind file old value cur
    local -a keys=() folders=() gone=()
    state=$(kp_state_dir) || exit $?
    ic=$(git config --get core.ignorecase 2>/dev/null)

    # ディレクトリが消えた worktree を git の記録から外す(そのブランチを開けるようにする)
    git worktree prune 2>/dev/null

    # 残っている作業フォルダと鍵
    while IFS= read -r p; do
        key=$(_kp_ss_key_of "$p") || continue
        alive+="$p"$'\t'"$key"$'\n'
        alive_keys+="$key$nl"
    done < <(_kp_ss_worktree_paths)
    # 作業フォルダの一覧を取れなかったとき(いまの作業フォルダが一覧に無いとき)は、
    # 残っている作業フォルダの記録まで消さないよう、何もせずに終わる
    key=$(kp_folder_key) || exit $?
    case "$alive_keys" in
        *"$nl$key$nl"*) ;;
        *)
            printf '[parallel] 片付けを飛ばした: 作業フォルダの一覧(git worktree list)を取れない\n' >&2
            return 0
            ;;
    esac

    # 記録を調べ、片付けを1行ずつ出す(perl は記録を書き換えない)
    #   session <ファイル>          セッションの記録を消す
    #   clear <ファイル> <folder>   Issueの記録の folder と session_id を空にする
    #   drop <ファイル> <folder>    Issueの記録を消す
    #   key <鍵> / folder <パス>    無くなった作業フォルダ
    actions=$(printf '%s' "$alive" | perl -MJSON::PP -e '
        use strict; use warnings;
        my ($state, $ic) = @ARGV;
        my $json = JSON::PP->new->utf8;
        sub norm { my $p = $_[0] // ""; $p =~ tr/A-Z/a-z/ if $ic eq "true"; $p }
        sub str { my $v = $_[0]; defined $v && !ref $v ? $v : "" }
        sub load {
            open my $fh, "<:raw", $_[0] or return undef;
            local $/; my $text = <$fh>; close $fh;
            my $d = eval { $json->decode($text) };
            return ref $d eq "HASH" ? $d : undef;
        }
        sub out { my $line = join("\t", @_) . "\n"; utf8::encode($line) if utf8::is_utf8($line); print $line }
        sub has_ref { system("git", "show-ref", "--verify", "--quiet", $_[0]) == 0 }
        my (%alive_id, %alive_key);
        while (my $line = <STDIN>) {
            chomp $line;
            utf8::decode($line);
            my ($p, $k) = split /\t/, $line, 2;
            next unless defined $k;
            $alive_id{ norm($p) } = 1;
            $alive_key{$k} = 1;
        }
        sub files {
            my $dir = shift;
            opendir my $dh, $dir or return ();
            return map { "$dir/$_" } sort grep { /\.json\z/ } readdir $dh;
        }
        for my $file (files("$state/sessions")) {
            my $d = load($file) or next;
            my $f = str($d->{folder});
            my $k = str($d->{folder_key});
            next unless length $f || length $k;
            next if (length $f && $alive_id{ norm($f) }) || (length $k && $alive_key{$k});
            out("session", $file);
            if (length $k) { out("key", $k) } else { out("folder", $f) }
        }
        for my $file (files("$state/issues")) {
            my $d = load($file) or next;
            my $f = str($d->{folder});
            next if length $f && $alive_id{ norm($f) };
            out("folder", $f) if length $f;
            my $b = str($d->{branch});
            my $kept = length $b && (has_ref("refs/heads/$b") || has_ref("refs/remotes/origin/$b"));
            if ($kept) {
                out("clear", $file, $f) if length $f || length str($d->{session_id});
            } else {
                out("drop", $file, $f);
            }
        }
    ' -- "$state" "$ic") || _kp_die69 "[parallel] 記録を読めない: $state"

    while IFS=$'\t' read -r kind file old; do
        case "$kind" in
            session)
                rm -f "$file" && printf '[parallel] 片付け: セッションの記録 %s を消した\n' "${file##*/}"
                ;;
            clear | drop)
                # 調べている間に別のセッションが書き直した記録は変えない
                cur=$(kp_json_get "$file" folder) || continue
                [ "$cur" = "$old" ] || continue
                if [ "$kind" = clear ]; then
                    kp_json_write "$file" folder= session_id= \
                        || _kp_die69 "[parallel] Issueの記録 $file を書けない"
                    printf '[parallel] 片付け: Issueの記録 %s の作業フォルダを空にした(ブランチが残っている)\n' "${file##*/}"
                else
                    rm -f "$file" && printf '[parallel] 片付け: Issueの記録 %s を消した\n' "${file##*/}"
                fi
                ;;
            key) keys+=("$file") ;;
            folder) folders+=("$file") ;;
        esac
    done <<<"$actions"

    # 枠は lib.sh の取り戻しの条件で取り戻す(消えた作業フォルダの ui のコンテナもここで消える)
    kp_slot_reclaim || true

    for value in "${folders[@]}"; do
        key=$(_kp_ss_key_of "$value") && keys+=("$key")
    done
    for key in "${keys[@]}"; do
        # 鍵の形(16進の12文字)でないものは名前に使わない
        [[ "$key" =~ ^[0-9a-f]{12}$ ]] || continue
        case "$alive_keys$seen" in *"$nl$key$nl"*) continue ;; esac
        seen+="$key$nl"
        gone+=("$key")
    done
    _kp_ss_remove_folder_data "${gone[@]}"
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

    kp_session_prune >/dev/null || exit $?
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
