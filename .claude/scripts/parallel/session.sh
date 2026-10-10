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
#         capacity         limit(設定の数)と active(ほかに作業中のセッションのうち、返答している途中のもの。issue folder last_seen)
#       最初に prune を行う(prune の標準出力は捨て、消せなかった名前などの標準エラーはそのまま出す)。
#   claim <N> --branch <ブランチ> [--session <ID>]
#       Issueの記録 issues/<N>.json を書く。すでにあれば folder branch session_id updated_at を書き直す。
#   end <session_id>
#       所有者が「やめた」と答えたセッションの記録 sessions/<session_id>.json を消す。
#   takeover <N> (--from <作業フォルダ> | --branch <ブランチ>) [--session <ID>]
#       Issue #N の作りかけを、いまの作業フォルダに引き継ぐ。Issueの記録のブランチを B とする。
#         --from がいまの作業フォルダ: 写しもブランチの手放しもしない。いまのブランチが B でなければ git switch B
#         --from がほかの作業フォルダ: いまの作業フォルダがきれいでなければ何もせずに終了コード1。
#           前の作業フォルダの中身を一時的な索引で1つのコミット S にまとめ(前の索引と中身は変えない)、
#           前の作業フォルダが B を開いていれば手放させて(detached)いまの作業フォルダで B を開く。
#           開いていなければ、前の HEAD がいまの HEAD の先祖でないときに、何も写さずに終了コード1で
#           次の手(前の HEAD を取り込んでから /start を打ち直す)を出す。
#           git diff --binary <前の HEAD> S | git apply --3way で写す。写せなければいまの作業フォルダを元に戻し、
#           前の作業フォルダに B を開き直させて終了コード1
#         --branch: いまの作業フォルダがきれいでなければ何もせずに終了コード1。B がローカルにあれば git switch B、
#           無ければリモート(origin)から取得して git switch -c B --track origin/B
#       どれも、Issueの記録の folder と session_id をいまのものに書き直す(無ければ作る。branch は空)。
#       前の作業フォルダがほかの作業フォルダなら handed_over_from に足す。
#       標準出力に、写したファイル(--from がいまの作業フォルダのときは作りかけ)の一覧と、いまのブランチを出す。
#   spec-names
#       すべての作業フォルダの .kiro/specs/ のディレクトリ名を、重ならないように1行ずつ出す。
#   prune
#       作業フォルダが無くなった記録と、残った枠と、作業フォルダごとのボリュームと DB を片付け、
#       片付けたことを標準出力に出す。所有者が手で打っても使える。
#         最初に git worktree prune を打ち、ディレクトリが消えた worktree を git の記録から外す
#         枠は、lib.sh の取り戻しの条件に当たるものを取り戻す(kp_slot_reclaim)
#         sessions/ と issues/ の記録から、folder が無くなったもの(lib.sh の kp_folder_gone)を探し、
#           無くなった作業フォルダの鍵(セッションの記録の folder_key か、folder から求めた鍵)ごとに、
#           ラベル keirekipro.folder=<鍵> のコンテナを docker rm -f で消し、owner.json の folder_key が
#           その鍵の枠を種類によらず取り戻す(コンテナを消せなければ枠は取り戻さない)。
#           続けてボリューム(kp-nm-<鍵> kp-gradle-project-<鍵>)と DB(kp_<鍵>)を消す
#         ボリュームと DB を消し終えた鍵の作業フォルダについてだけ、記録を片付ける。
#           セッションの記録は消す。issues/<N>.json は、branch がローカルかリモートに残っていれば
#           folder と session_id を空にして残し(check-start の branch_only はこれを引く)、branch がどこにも無ければ消す
#         消し終えていない鍵(Docker につながらない、db が動いていない、消せなかった)の記録は書き換えずに残し、
#           消せなかった名前と理由を標準エラーに出す。次の prune がもう一度消しにいく
#         folder が空の issues/<N>.json は鍵が無いので、鍵の片付けを待たずに同じ規則で扱う
#
# セッションのIDは、--session の値か環境変数 KP_SESSION_ID で渡す。どちらも無ければ、
# いまの作業フォルダのセッションの記録のうち started_at がいちばん古いもの(lib.sh の kp_session_id)。
# 作業中のセッションは、sessions/ の記録のうち、issues/ に同じ session_id か同じ folder の記録があるもの。
# ただし、folder の作業フォルダが無くなったセッションの記録(prune が消し終えるまで残す記録)は数えない。
# capacity は、作業中のセッションのうち、記録の responding が真のもの(session-registry.sh が、返答を始めたときに
# 真にし、返答を終えたときと返答を終えて入力を待っているときに偽にする)だけを数える。欄が無い記録は数えない。
# folder_conflict と leftovers の active_session は、responding によらず作業中のセッションを出す。
# このスクリプトは所有者とやり取りしない。docker を呼ぶのは prune(片付けるものがあるとき)だけ。
#
# 終了コード: 0(成功)、1(takeover が引き継げなかった)、64(呼び方の誤り)、
#             69(git のリポジトリの外、設定の値の誤り、記録を書けない)。
# 前提: bash・perl(JSON::PP)・git。jq には依存しない。
# =====================================================================

KP_SESSION_SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=.claude/scripts/parallel/lib.sh
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

# 消せなかったボリュームと DB の名前を標準エラーに出し、次の片付けがもう一度消しにいくことを添える
_kp_ss_report_left() { # <ボリュームの名前(先頭に空白)> <DB の名前(先頭に空白)>
    local what=""
    [ -n "$1" ] && what="ボリューム$1"
    [ -n "$2" ] && what+="${what:+、}DB$2"
    printf '[parallel] 消せなかった名前: %s。その作業フォルダの記録を残したので、次の片付け(/start のときの check-start か、session.sh prune)が自動でもう一度消しにいく\n' \
        "$what" >&2
}

# 鍵のラベル(keirekipro.folder=<鍵>)のコンテナを docker rm -f で消す。
# 消せなければ、理由を標準出力に出して終了コード1。
_kp_ss_remove_folder_containers() { # <鍵>
    local out
    local -a ids=()
    out=$(docker ps -aq --filter "label=keirekipro.folder=$1" 2>&1) || {
        printf '%s' "$out"
        return 1
    }
    # コンテナの ID か名前の形の行だけを使う(注意の文などを混ぜない)
    mapfile -t ids < <(printf '%s\n' "$out" | tr -d '\r' | grep -E '^[[:alnum:]_.-]+$')
    [ "${#ids[@]}" -gt 0 ] || return 0
    out=$(docker rm -f "${ids[@]}" 2>&1) || {
        printf '%s' "$out"
        return 1
    }
}

# 鍵の作業フォルダが持つ枠を、種類によらず取り戻す。
# lib.sh の取り戻しと同じ錠を使い、名前を変えてから持ち主を確かめる(確かめている間に取り直された枠を消さないため)。
_kp_ss_reclaim_key_slots() { # <記録の置き場所> <鍵>
    local state="$1" key="$2" k dir trash lock
    [ -d "$state/slots" ] || return 0
    lock="$state/slots/.reclaim.lock"
    _kp_lock "$lock" || return 1
    for k in $(_kp_slot_numbers "$state"); do
        dir="$state/slots/$k"
        [ "$(kp_json_get "$dir/owner.json" folder_key 2>/dev/null)" = "$key" ] || continue
        trash="$state/slots/.reclaim-$k-$$"
        mv "$dir" "$trash" 2>/dev/null || continue
        if [ "$(kp_json_get "$trash/owner.json" folder_key 2>/dev/null)" != "$key" ]; then
            mv -T "$trash" "$dir" 2>/dev/null
            continue
        fi
        rm -rf "$trash"
        printf '[parallel] 片付け: 作業フォルダが無くなった枠 %s を取り戻した\n' "$k"
    done
    rmdir "$lock" 2>/dev/null
    return 0
}

# 作業フォルダが無くなった鍵ごとに、ラベルのコンテナを消して枠を取り戻し、ボリュームと DB を消す。
# 消し終えた鍵を _KP_SS_DONE(鍵を改行で挟んで並べた一覧)に入れる。
# ボリュームは、docker volume rm が成功したときと、ボリュームが無かったときに消し終えたとみなす。
# DB は、db の中にその DB が無かったときと、DROP DATABASE が成功したときに消し終えたとみなす。
# Docker につながらないときと db が動いていないときは、消し終えていないとみなす。
# 標準出力の「消した」には実際に消せたものだけを書き、消せなかった名前と理由は標準エラーに出す。
_kp_ss_remove_folder_data() { # <記録の置き場所> <鍵>...
    local state="$1"
    shift
    local nl=$'\n' key name db out ok db_up=0 removed="" left_vols="" left_dbs=""
    _KP_SS_DONE=$nl
    [ $# -gt 0 ] || return 0
    if ! out=$(docker version --format '{{.Server.Version}}' 2>&1); then
        for key in "$@"; do
            left_vols+=" kp-nm-$key kp-gradle-project-$key"
            left_dbs+=" kp_$key"
        done
        printf '[parallel] Docker につながらないので、作業フォルダごとのコンテナとボリュームと DB を消していない(鍵 %s): %s\n' \
            "$*" "$(_kp_ss_one_line "$out")" >&2
        _kp_ss_report_left "$left_vols" "$left_dbs"
        return 0
    fi
    out=$(docker compose -p keirekipro ps --status running -q db 2>/dev/null) && [ -n "$out" ] && db_up=1
    [ "$db_up" = 1 ] || printf '[parallel] db が動いていないので、DB を消していない\n' >&2
    for key in "$@"; do
        ok=1
        # 先にコンテナを消す(ボリュームを使っているコンテナが残っていると消せないため)
        if out=$(_kp_ss_remove_folder_containers "$key"); then
            _kp_ss_reclaim_key_slots "$state" "$key"
        else
            printf '[parallel] 作業フォルダ(鍵 %s)のコンテナを消せないので、その鍵の枠を取り戻していない: %s\n' \
                "$key" "$(_kp_ss_one_line "$out")" >&2
        fi
        for name in "kp-nm-$key" "kp-gradle-project-$key"; do
            if out=$(docker volume rm "$name" 2>&1); then
                removed+=" $name"
            else
                case "$out" in
                    *[Nn]o\ such\ volume*) ;;
                    *)
                        printf '[parallel] ボリューム %s を消せない: %s\n' "$name" "$(_kp_ss_one_line "$out")" >&2
                        left_vols+=" $name"
                        ok=0
                        ;;
                esac
            fi
        done
        db="kp_$key"
        if [ "$db_up" != 1 ]; then
            left_dbs+=" $db"
            ok=0
        elif ! out=$(docker compose -p keirekipro exec -T db psql -U postgres -tAc \
            "SELECT 1 FROM pg_database WHERE datname='$db'" 2>&1); then
            printf '[parallel] DB %s があるかを確かめられない: %s\n' "$db" "$(_kp_ss_one_line "$out")" >&2
            left_dbs+=" $db"
            ok=0
        elif [ "$(_kp_ss_one_line "$out")" = 1 ]; then
            if out=$(docker compose -p keirekipro exec -T db psql -U postgres -c "DROP DATABASE IF EXISTS $db" 2>&1); then
                removed+=" $db"
            else
                printf '[parallel] DB %s を消せない: %s\n' "$db" "$(_kp_ss_one_line "$out")" >&2
                left_dbs+=" $db"
                ok=0
            fi
        fi
        [ "$ok" = 1 ] && _KP_SS_DONE+="$key$nl"
    done
    if [ -n "$removed" ]; then
        printf '[parallel] 片付け: 作業フォルダごとのボリュームと DB を消した:%s\n' "$removed"
    fi
    if [ -n "$left_vols$left_dbs" ]; then
        _kp_ss_report_left "$left_vols" "$left_dbs"
    fi
    return 0
}

# 作業フォルダが無くなった1つの記録を片付ける
#   S: セッションの記録を消す
#   I: Issueの記録は、branch がローカルかリモートに残っていれば folder と session_id を空にして残し、
#      どこにも無ければ消す。調べている間に別のセッションが書き直した記録(folder が変わったもの)は変えない
_kp_ss_tidy_record() { # <S|I> <ファイル> <folder> <branch> <session_id>
    local cur
    case "$1" in
        S)
            rm -f "$2" && printf '[parallel] 片付け: セッションの記録 %s を消した\n' "${2##*/}"
            ;;
        I)
            cur=$(kp_json_get "$2" folder) || return 0
            [ "$cur" = "$3" ] || return 0
            if [ -n "$4" ] && { git show-ref --verify --quiet "refs/heads/$4" \
                || git show-ref --verify --quiet "refs/remotes/origin/$4"; }; then
                [ -n "$3$5" ] || return 0
                kp_json_write "$2" folder= session_id= \
                    || _kp_die69 "[parallel] Issueの記録 $2 を書けない"
                printf '[parallel] 片付け: Issueの記録 %s の作業フォルダを空にした(ブランチが残っている)\n' "${2##*/}"
            else
                rm -f "$2" && printf '[parallel] 片付け: Issueの記録 %s を消した\n' "${2##*/}"
            fi
            ;;
    esac
    return 0
}

# 作業フォルダが無くなった記録と、残った枠と、作業フォルダごとのボリュームと DB を片付ける。
# 片付けたことを標準出力に出す(check-start から呼ぶときは捨てる)。
kp_session_prune() {
    [ $# -eq 0 ] || _kp_ss_usage "prune は引数を取らない"
    local nl=$'\n' sep=$'\x1f'
    # gone_keys は、鍵を改行で挟んで並べた一覧(連想配列を使わない)
    local state alive rc records kind file f b sid key entry gone_keys="$nl"
    local -a gone=() pending=()
    state=$(kp_state_dir) || exit $?

    # ディレクトリが消えた worktree を git の記録から外す(そのブランチを開けるようにする)
    git worktree prune 2>/dev/null

    # 残っている作業フォルダと鍵。一覧を取れなかったとき(いまの作業フォルダが一覧に無いときも)は、
    # 残っている作業フォルダの記録まで消さないよう、何もせずに終わる
    alive=$(kp_live_folders)
    rc=$?
    case "$rc" in
        0) ;;
        69) exit 69 ;;
        *)
            printf '[parallel] 片付けを飛ばした: 作業フォルダの一覧(git worktree list)を取れない\n' >&2
            return 0
            ;;
    esac

    # 記録を1行ずつ出す(perl は記録を読むだけ。欄は \x1f で区切る)
    #   S <ファイル> <folder> <folder_key>
    #   I <ファイル> <folder> <branch> <session_id>
    records=$(perl -MJSON::PP -e '
        use strict; use warnings;
        my ($state) = @ARGV;
        my $json = JSON::PP->new->utf8;
        sub str { my $v = $_[0]; defined $v && !ref $v ? $v : "" }
        sub load {
            open my $fh, "<:raw", $_[0] or return undef;
            local $/; my $text = <$fh>; close $fh;
            my $d = eval { $json->decode($text) };
            return ref $d eq "HASH" ? $d : undef;
        }
        sub out { my $line = join("\x1f", @_) . "\n"; utf8::encode($line) if utf8::is_utf8($line); print $line }
        sub files {
            my $dir = shift;
            opendir my $dh, $dir or return ();
            return map { "$dir/$_" } sort grep { /\.json\z/ } readdir $dh;
        }
        for my $file (files("$state/sessions")) {
            my $d = load($file) or next;
            out("S", $file, str($d->{folder}), str($d->{folder_key}));
        }
        for my $file (files("$state/issues")) {
            my $d = load($file) or next;
            out("I", $file, str($d->{folder}), str($d->{branch}), str($d->{session_id}));
        }
    ' -- "$state") || _kp_die69 "[parallel] 記録を読めない: $state"

    # 作業フォルダが無くなった記録と、その鍵を集める。Issueの記録の handed_over_from からは鍵を求めない
    while IFS="$sep" read -r -u 3 kind file f b sid; do
        case "$kind" in
            S)
                # b はセッションの記録の folder_key
                kp_folder_gone "$f" "$b" "$alive" || continue
                key=$b
                [ -n "$key" ] || key=$(_kp_ss_key_of "$f") || continue
                ;;
            I)
                if [ -z "$f" ]; then
                    # folder が空のIssueの記録は鍵が無いので、鍵の片付けを待たずに扱う
                    _kp_ss_tidy_record I "$file" "" "$b" "$sid"
                    continue
                fi
                kp_folder_gone "$f" "" "$alive" || continue
                key=$(_kp_ss_key_of "$f") || continue
                ;;
            *) continue ;;
        esac
        # 鍵の形(16進の12文字)でない記録は、消すボリュームと DB の名前が無いので、そのまま片付ける
        if ! [[ "$key" =~ ^[0-9a-f]{12}$ ]]; then
            _kp_ss_tidy_record "$kind" "$file" "$f" "$b" "$sid"
            continue
        fi
        case "$gone_keys" in
            *"$nl$key$nl"*) ;;
            *)
                gone_keys+="$key$nl"
                gone+=("$key")
                ;;
        esac
        pending+=("$key$sep$kind$sep$file$sep$f$sep$b$sep$sid")
    done 3<<<"$records"

    # 枠は lib.sh の取り戻しの条件で取り戻す
    kp_slot_reclaim || true

    # 鍵ごとにコンテナを消して枠を取り戻し、ボリュームと DB を消す
    _kp_ss_remove_folder_data "$state" "${gone[@]}"

    # ボリュームと DB を消し終えた鍵の作業フォルダについてだけ、記録を片付ける。
    # 消し終えていない鍵の記録は書き換えずに残す(次の prune がもう一度消しにいく)
    for entry in "${pending[@]}"; do
        IFS="$sep" read -r key kind file f b sid <<<"$entry"
        case "$_KP_SS_DONE" in
            *"$nl$key$nl"*) _kp_ss_tidy_record "$kind" "$file" "$f" "$b" "$sid" ;;
        esac
    done
    return 0
}

kp_session_check_start() {
    local n="" session="" state sid limit me key ic alive rc file gone_sessions=""
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

    # 作業フォルダが無くなったセッションの記録(prune が消し終えるまで残す記録)は作業中に数えない。
    # 作業フォルダの一覧を取れないときは、どの記録も無くなったとはみなさない(作業中のセッションを見落とさないため)
    alive=$(kp_live_folders)
    rc=$?
    [ "$rc" = 69 ] && exit 69
    if [ "$rc" = 0 ]; then
        for file in "$state"/sessions/*.json; do
            [ -f "$file" ] || continue
            kp_folder_gone "$(kp_json_get "$file" folder)" "$(kp_json_get "$file" folder_key)" "$alive" \
                && gone_sessions+="${file##*/}"$'\n'
        done
    fi

    perl -MJSON::PP -e '
        use strict; use warnings;
        my ($state, $n, $sid, $limit, $me, $me_key, $ic, $gone_list) = @ARGV;
        utf8::decode($_) for ($state, $sid, $me);
        my $json = JSON::PP->new->utf8;

        sub norm { my $p = $_[0] // ""; $p =~ tr/A-Z/a-z/ if $ic eq "true"; $p }
        sub load {
            open my $fh, "<:raw", $_[0] or return undef;
            local $/; my $text = <$fh>; close $fh;
            my $d = eval { $json->decode($text) };
            return ref $d eq "HASH" ? $d : undef;
        }
        # 作業フォルダが無くなったセッションの記録のファイル名
        my %gone_session = map { ($_ => 1) } grep { length } split /\n/, $gone_list;
        sub load_dir {
            my ($dir, $skip) = @_;
            opendir my $dh, $dir or return ();
            my @out;
            for my $name (sort readdir $dh) {
                next unless $name =~ /\.json\z/;
                next if $skip && $skip->{$name};
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

        my @sessions = load_dir("$state/sessions", \%gone_session);
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
        # 返答している途中か(記録の responding が真。欄が無い記録は返答していないとみなす)
        sub responding { my $v = $_[0]->{responding}; JSON::PP::is_bool($v) && $v }
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

        # capacity(作業中のセッションのうち、返答している途中のものだけ)
        my @active;
        for my $s (sort by_start grep { str($_->{session_id}) ne $sid && is_active($_, \%issue_by_sid, \%issue_by_folder) && responding($_) } @sessions) {
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
    ' -- "$state" "$n" "$sid" "$limit" "$me" "$key" "$ic" "$gone_sessions" || exit 69
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

# 作業フォルダに、git の管理下の変更か、無視されていない git の管理外のファイルがあれば真
# (git status を打てないときも、きれいとはみなさない)
_kp_ss_dirty() { # <作業フォルダ>
    local out
    out=$(git -C "$1" status --porcelain --untracked-files=normal 2>/dev/null) || return 0
    [ -n "$out" ]
}

# いまの作業フォルダのブランチ(detached なら空)
_kp_ss_branch() { # <作業フォルダ>
    git -C "$1" symbolic-ref -q --short HEAD 2>/dev/null
}

# 引き継いだあとの handed_over_from を JSON で出す。
# いまの作業フォルダを除き、前の作業フォルダ(空でなければ)を足す。比べるときは core.ignorecase に従う
_kp_ss_handed_json() { # <Issueの記録> <いまの作業フォルダ> <前の作業フォルダ>
    perl -MJSON::PP -e '
        use strict; use warnings;
        my ($file, $me, $prev, $ic) = @ARGV;
        utf8::decode($_) for ($me, $prev);
        sub norm { my $p = $_[0] // ""; $p =~ tr/A-Z/a-z/ if $ic eq "true"; $p }
        my @old;
        if (open my $fh, "<:raw", $file) {
            local $/; my $text = <$fh>; close $fh;
            my $d = eval { JSON::PP->new->utf8->decode($text) };
            @old = grep { defined $_ && !ref $_ && length $_ } @{ $d->{handed_over_from} }
                if ref $d eq "HASH" && ref $d->{handed_over_from} eq "ARRAY";
        }
        my @out = grep { norm($_) ne norm($me) } @old;
        push @out, $prev if length $prev && norm($prev) ne norm($me) && !grep { norm($_) eq norm($prev) } @out;
        print JSON::PP->new->utf8->encode(\@out);
    ' -- "$1" "$2" "$3" "$(git config --get core.ignorecase 2>/dev/null)"
}

# Issueの記録の folder と session_id をいまのものに書き直す(無ければ作る。branch は空)。
# <ブランチ> が空でなければ branch も書き直す。<前の作業フォルダ> が空でなければ handed_over_from に足す
_kp_ss_write_takeover() { # <Issueの記録> <N> <いまの作業フォルダ> <セッションのID> <ブランチ> <前の作業フォルダ>
    local f="$1" n="$2" me="$3" sid="$4" branch="$5" prev="$6" handed now
    handed=$(_kp_ss_handed_json "$f" "$me" "$prev") || _kp_die69 "[parallel] Issueの記録 $f を読めない"
    now=$(date +%s)
    if [ -f "$f" ]; then
        if [ -n "$branch" ]; then
            kp_json_write "$f" folder="$me" branch="$branch" session_id="$sid" updated_at:="$now" \
                "handed_over_from:=$handed" || _kp_die69 "[parallel] Issueの記録 $f を書けない"
        else
            kp_json_write "$f" folder="$me" session_id="$sid" updated_at:="$now" \
                "handed_over_from:=$handed" || _kp_die69 "[parallel] Issueの記録 $f を書けない"
        fi
    else
        mkdir -p "${f%/*}" 2>/dev/null || _kp_die69 "[parallel] 記録の置き場所 ${f%/*} を作れない"
        kp_json_write "$f" issue:="$n" folder="$me" branch="$branch" session_id="$sid" updated_at:="$now" \
            "handed_over_from:=$handed" || _kp_die69 "[parallel] Issueの記録 $f を書けない"
    fi
}

# 引き継ぎの結果を標準出力に出す
_kp_ss_takeover_report() { # <1行目> <一覧の見出し> <一覧(1行に1つ)>
    local cur line
    printf '[parallel] %s\n' "$1"
    printf '[parallel] %s:\n' "$2"
    if [ -n "$3" ]; then
        while IFS= read -r line; do
            printf '  %s\n' "$line"
        done <<<"$3"
    else
        printf '  (なし)\n'
    fi
    cur=$(_kp_ss_branch .)
    [ -n "$cur" ] || cur="(ブランチ無し: $(git rev-parse --short HEAD 2>/dev/null))"
    printf '[parallel] いまのブランチ: %s\n' "$cur"
}

# 引き継ぎが失敗したことを出して、終了コード1で終わる
_kp_ss_takeover_fail() {
    printf '[parallel] 引き継げない: %s\n' "$*" >&2
    exit 1
}

# takeover --from <いまの作業フォルダ>: 写しもブランチの手放しもせず、記録だけを書き直す
_kp_ss_takeover_self() { # <N> <Issueの記録> <いまの作業フォルダ> <セッションのID> <Issueの記録のブランチ>
    local n="$1" f="$2" me="$3" sid="$4" b="$5" out list
    if [ -n "$b" ] && [ "$(_kp_ss_branch .)" != "$b" ]; then
        # コミットしていない変更は git がそのまま持ち越す。持ち越せなければ git switch が失敗する
        out=$(git switch -q "$b" 2>&1) \
            || _kp_ss_takeover_fail "ブランチ $b に切り替えられない: $(_kp_ss_one_line "$out")"
    fi
    _kp_ss_write_takeover "$f" "$n" "$me" "$sid" "" ""
    list=$(git status --porcelain --untracked-files=all 2>/dev/null)
    _kp_ss_takeover_report "引き継ぎ: Issue #$n の作りかけを、いまの作業フォルダのまま引き継いだ" \
        "作りかけ(コミットしていない変更)" "$list"
}

# takeover --from <ほかの作業フォルダ>: 前の作業フォルダの作りかけを、いまの作業フォルダに写す
_kp_ss_takeover_other() { # <N> <Issueの記録> <いまの作業フォルダ> <セッションのID> <Issueの記録のブランチ> <前の作業フォルダ>
    local n="$1" f="$2" me="$3" sid="$4" b="$5" prev="$6"
    local prev_head gitdir idx tree snap orig orig_branch prev_branch released=0 patch names out
    # 2. いまの作業フォルダがきれいでなければ、何もしない
    if _kp_ss_dirty .; then
        _kp_ss_takeover_fail "いまの作業フォルダ $me に、コミットしていない変更か git の管理外のファイルがある。片付けてから、もう一度 takeover を打つ"
    fi
    prev_head=$(git -C "$prev" rev-parse --verify -q HEAD) \
        || _kp_ss_takeover_fail "前の作業フォルダ $prev の HEAD を読めない"

    # 3. 一時的な索引で、前の作業フォルダの中身を1つのコミット S にまとめる(前の索引と中身は変えない)
    gitdir=$(git -C "$prev" rev-parse --path-format=absolute --git-dir 2>/dev/null) \
        || _kp_ss_takeover_fail "前の作業フォルダ $prev の git のディレクトリを読めない"
    idx="${gitdir//\\//}/kp-takeover-index.$$"
    rm -f "$idx"
    if out=$(GIT_INDEX_FILE="$idx" git -C "$prev" read-tree "$prev_head" 2>&1 \
        && GIT_INDEX_FILE="$idx" git -C "$prev" add -A 2>&1 \
        && GIT_INDEX_FILE="$idx" git -C "$prev" write-tree 2>&1); then
        tree=$(printf '%s\n' "$out" | tail -n 1)
    else
        rm -f "$idx"
        _kp_ss_takeover_fail "前の作業フォルダ $prev の中身をまとめられない: $(_kp_ss_one_line "$out")"
    fi
    rm -f "$idx"
    # S はどのブランチにも載せない一時的なコミットなので、作者は固定の名前にする
    snap=$(GIT_AUTHOR_NAME=keirekipro-parallel GIT_AUTHOR_EMAIL=keirekipro-parallel@localhost \
        GIT_COMMITTER_NAME=keirekipro-parallel GIT_COMMITTER_EMAIL=keirekipro-parallel@localhost \
        git commit-tree --no-gpg-sign -p "$prev_head" -m "keirekipro-parallel takeover #$n" "$tree" 2>&1) \
        || _kp_ss_takeover_fail "前の作業フォルダ $prev の中身をまとめられない: $(_kp_ss_one_line "$snap")"

    # 4. 前の作業フォルダが Issueのブランチを開いていれば手放させ、いまの作業フォルダで開く。
    #    開いていなければ、前の HEAD がいまの HEAD の先祖であることを確かめる
    orig_branch=$(_kp_ss_branch .)
    orig=$(git rev-parse HEAD)
    prev_branch=$(_kp_ss_branch "$prev")
    if [ -n "$b" ] && [ "$prev_branch" = "$b" ]; then
        out=$(git -C "$prev" switch -q --detach 2>&1) \
            || _kp_ss_takeover_fail "前の作業フォルダ $prev にブランチ $b を手放させられない: $(_kp_ss_one_line "$out")"
        released=1
        if ! out=$(git switch -q "$b" 2>&1); then
            git -C "$prev" switch -q "$b" 2>/dev/null
            _kp_ss_takeover_fail "ブランチ $b に切り替えられない: $(_kp_ss_one_line "$out")"
        fi
    elif ! git merge-base --is-ancestor "$prev_head" HEAD 2>/dev/null; then
        _kp_ss_takeover_fail "前の作業フォルダの土台(${prev} の HEAD ${prev_head})が、いまのブランチ ${orig_branch:-(ブランチ無し)} に含まれていない。何も写していない。" \
            "次の手: いまの作業フォルダのブランチに前の作業フォルダの HEAD(前の土台 ${prev_head})を取り込んでから、もう一度 /start を打つ"
    fi

    # 5. 前の HEAD を土台にした差分で、コミットしていない変更と spec を写す
    names=$(git diff --no-renames --name-only "$prev_head" "$snap" 2>/dev/null)
    if [ -n "$names" ]; then
        patch="$(git rev-parse --path-format=absolute --git-dir)/kp-takeover-patch.$$"
        patch=${patch//\\//}
        if ! out=$( { git diff --no-renames --binary "$prev_head" "$snap" >"$patch" \
            && git apply --3way "$patch"; } 2>&1); then
            rm -f "$patch"
            # いまの作業フォルダは引き継ぎの前にきれいだったので、写したものだけを戻す。
            # git apply --3way は写したファイルを索引に載せるので、git reset --hard が写したファイルを消す
            git reset -q --hard 2>/dev/null
            if [ "$released" = 1 ]; then
                if [ -n "$orig_branch" ]; then
                    git checkout -q -f "$orig_branch" 2>/dev/null
                else
                    git checkout -q -f --detach "$orig" 2>/dev/null
                fi
                git -C "$prev" switch -q "$b" 2>/dev/null
            fi
            _kp_ss_takeover_fail "前の作業フォルダ $prev の作りかけを写せない(いまの作業フォルダを元に戻した): $(_kp_ss_one_line "$out")"
        fi
        rm -f "$patch"
    fi

    # 7. Issueの記録を書き直し、前の作業フォルダを handed_over_from に足す
    if [ "$released" = 1 ]; then
        _kp_ss_write_takeover "$f" "$n" "$me" "$sid" "$b" "$prev"
    else
        _kp_ss_write_takeover "$f" "$n" "$me" "$sid" "" "$prev"
    fi
    # 8. 写したファイルの一覧といまのブランチを出す
    _kp_ss_takeover_report "引き継ぎ: Issue #$n の作りかけを $prev から写した" "写したファイル" "$names"
}

# takeover --branch <ブランチ>: どこでも開かれていないIssueのブランチに切り替える
_kp_ss_takeover_branch() { # <N> <Issueの記録> <いまの作業フォルダ> <セッションのID> <ブランチ>
    local n="$1" f="$2" me="$3" sid="$4" b="$5" out
    if _kp_ss_dirty .; then
        _kp_ss_takeover_fail "いまの作業フォルダ $me に、コミットしていない変更か git の管理外のファイルがある。片付けてから、もう一度 takeover を打つ"
    fi
    if [ "$(_kp_ss_branch .)" != "$b" ]; then
        if git show-ref --verify --quiet "refs/heads/$b"; then
            out=$(git switch -q "$b" 2>&1) \
                || _kp_ss_takeover_fail "ブランチ $b に切り替えられない: $(_kp_ss_one_line "$out")"
        else
            # ローカルに無ければ、リモートから取得する(取得できなくても、リモートのブランチの記録があれば使う)
            if ! out=$(git fetch -q origin "+refs/heads/$b:refs/remotes/origin/$b" 2>&1); then
                git show-ref --verify --quiet "refs/remotes/origin/$b" \
                    || _kp_ss_takeover_fail "ブランチ $b がローカルにも無く、リモートからも取得できない: $(_kp_ss_one_line "$out")"
                printf '[parallel] リモートからブランチ %s を取得できないので、手元にあるリモートのブランチの記録を使う: %s\n' \
                    "$b" "$(_kp_ss_one_line "$out")" >&2
            fi
            out=$(git switch -q -c "$b" --track "origin/$b" 2>&1) \
                || _kp_ss_takeover_fail "リモートのブランチ origin/$b に切り替えられない: $(_kp_ss_one_line "$out")"
        fi
    fi
    _kp_ss_write_takeover "$f" "$n" "$me" "$sid" "$b" ""
    _kp_ss_takeover_report "引き継ぎ: Issue #$n のブランチ $b に切り替えた" "写したファイル" ""
}

kp_session_takeover() {
    local n="" from="" branch="" session="" have_from=0 have_branch=0
    local usage="takeover <N> (--from <作業フォルダ> | --branch <ブランチ>) [--session <ID>]"
    local state me sid f b="" prev common mine
    while [ $# -gt 0 ]; do
        case "$1" in
            --from)
                [ $# -ge 2 ] || _kp_ss_usage "--from の値が無い"
                from=$2
                have_from=1
                shift 2
                ;;
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
    [ -n "$n" ] && [ $((have_from + have_branch)) = 1 ] && [ -n "$from$branch" ] || _kp_ss_usage "$usage"

    state=$(kp_state_dir) || exit $?
    me=$(kp_folder) || exit $?
    sid=$(kp_session_id "${session:-${KP_SESSION_ID:-}}") || exit $?
    cd "$me" || _kp_die69 "[parallel] いまの作業フォルダ $me に移れない"
    f="$state/issues/$n.json"
    if [ -f "$f" ]; then
        b=$(kp_json_get "$f" branch) || _kp_die69 "[parallel] Issueの記録 $f を読めない"
    fi

    if [ "$have_branch" = 1 ]; then
        _kp_ss_takeover_branch "$n" "$f" "$me" "$sid" "$branch"
        return 0
    fi

    # --from は、このリポジトリの作業フォルダの最上位に読み替える
    prev=$(git -C "$from" rev-parse --show-toplevel 2>/dev/null) \
        || _kp_ss_usage "--from の '$from' が git の作業フォルダでない"
    prev=${prev//\\//}
    common=$(git -C "$prev" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)
    mine=$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null)
    [ "$(_kp_norm_path "${common//\\//}")" = "$(_kp_norm_path "${mine//\\//}")" ] \
        || _kp_ss_usage "--from の '$from' がこのリポジトリの作業フォルダでない"

    if [ "$(_kp_norm_path "$prev")" = "$(_kp_norm_path "$me")" ]; then
        _kp_ss_takeover_self "$n" "$f" "$me" "$sid" "$b"
    else
        _kp_ss_takeover_other "$n" "$f" "$me" "$sid" "$b" "$prev"
    fi
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
        takeover) kp_session_takeover "$@" ;;
        *) _kp_ss_usage "サブコマンドは check-start / claim / end / takeover / spec-names / prune のどれか" ;;
    esac
}

# 読み込まれただけ(source)のときは本体の処理を動かさない
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    kp_session_main "$@"
fi
