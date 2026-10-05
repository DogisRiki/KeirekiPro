#!/bin/bash
# =====================================================================
# 並行作業の記録の場所と枠の数え方をまとめた関数群(lib.sh)
#
# 読み込み方: スクリプトは `. "$(dirname "$0")/lib.sh"`、
#             フックは `. "$(dirname "$0")/../scripts/parallel/lib.sh"`。
# 記録は本体の .git/keirekipro-parallel/ の下に置き、時刻は UNIX 秒で持つ。
#   slots/<k>/owner.json   枠の持ち主(folder folder_key kind command started_at session_id)
#   sessions/<id>.json     セッションの記録(session-registry.sh が書く)
#   issues/<N>.json        Issueの記録(session.sh が書く)
# この関数群は、コンテナを作らず、所有者に何も出さない(失敗の理由だけを標準エラーに出す)。
# git のリポジトリの外で呼ばれたときと、設定の値が正しくないときは、終了コード69で終わる。
#
# 前提: bash・perl(JSON::PP)・git・docker。jq には依存しない。
#   使う git のコマンドで最も新しいのは `git rev-parse --path-format=absolute`(git 2.31 以上)。
#   Windows では Git for Windows(Git Bash 同梱)がこれらを提供する。macOS / Linux は標準。
# 枠を取る関数は、セッションのIDを環境変数 KP_SESSION_ID(--session の値)から受け取る。
# =====================================================================

# Git Bash が / で始まる引数を Windows のパスに書き換えないようにする
export MSYS_NO_PATHCONV=1

# 枠の取り戻しの条件の、check の枠が古いとみなすまでの秒数
KP_CHECK_STALE_SECONDS=120

_kp_die69() {
    printf '%s\n' "$*" >&2
    exit 69
}

# 記録の置き場所(どの作業フォルダから呼んでも同じ)
kp_state_dir() {
    local common
    common=$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null) \
        || _kp_die69 "git のリポジトリの外で呼ばれた"
    printf '%s/keirekipro-parallel\n' "${common//\\//}"
}

# 作業フォルダの最上位(区切りは /)
kp_folder() {
    local top
    top=$(git rev-parse --show-toplevel 2>/dev/null) \
        || _kp_die69 "git のリポジトリの外で呼ばれた"
    printf '%s\n' "${top//\\//}"
}

# パスを、記録の中で比べるための形にする(core.ignorecase が true のときだけ小文字にする)
_kp_norm_path() {
    if [ "$(git config --get core.ignorecase 2>/dev/null)" = true ]; then
        printf '%s' "$1" | tr 'ABCDEFGHIJKLMNOPQRSTUVWXYZ' 'abcdefghijklmnopqrstuvwxyz'
    else
        printf '%s' "$1"
    fi
}

kp_folder_id() {
    local f
    f=$(kp_folder) || exit $?
    _kp_norm_path "$f"
    printf '\n'
}

# 鍵: kp_folder_id を git hash-object にかけた値の先頭12文字
kp_folder_key() {
    local id hash
    id=$(kp_folder_id) || exit $?
    hash=$(printf '%s' "$id" | git hash-object --stdin) || _kp_die69 "鍵を求められない"
    printf '%s\n' "${hash:0:12}"
}

# 本体フォルダ: 記録の置き場所がある git の共通ディレクトリ(.git)の親
kp_main_folder() {
    local state
    state=$(kp_state_dir) || exit $?
    state=$(dirname "$state")
    dirname "$state"
}

# パスを、core.ignorecase の値(先に1回だけ読んだもの)に合わせて比べる形にする
_kp_norm_with() { # <core.ignorecase の値> <パス>
    if [ "$1" = true ]; then
        printf '%s' "$2" | tr 'ABCDEFGHIJKLMNOPQRSTUVWXYZ' 'abcdefghijklmnopqrstuvwxyz'
    else
        printf '%s' "$2"
    fi
}

# 残っている作業フォルダの一覧: git worktree list --porcelain の作業フォルダのうち、
# ディレクトリがあり bare でないものを、1行ずつ「<作業フォルダ><タブ><鍵>」で出す。
# 一覧を取れないとき(git worktree list が失敗したとき、いまの作業フォルダが一覧に無いとき)は、
# 何も出さずに終了コード2で終わる(残っている作業フォルダまで無くなったとみなさないため)。
kp_live_folders() {
    local me list paths p hash ic out="" found=0
    me=$(kp_folder_key) || exit $?
    list=$(git worktree list --porcelain 2>/dev/null) || return 2
    paths=$(printf '%s\n' "$list" | perl -e '
        my ($path, $bare);
        my $flush = sub { print "$path\n" if defined $path && !$bare; ($path, $bare) = (undef, 0) };
        while (my $line = <STDIN>) {
            chomp $line;
            if ($line =~ /\Aworktree (.+)\z/) { $flush->(); $path = $1 }
            elsif ($line eq "bare") { $bare = 1 }
        }
        $flush->();
    ') || return 2
    ic=$(git config --get core.ignorecase 2>/dev/null)
    while IFS= read -r p; do
        [ -n "$p" ] && [ -d "$p" ] || continue
        hash=$(_kp_norm_with "$ic" "$p" | git hash-object --stdin) || return 2
        out+="$p"$'\t'"${hash:0:12}"$'\n'
        [ "${hash:0:12}" = "$me" ] && found=1
    done <<<"$paths"
    [ "$found" = 1 ] || return 2
    printf '%s' "$out"
}

# 記録の作業フォルダが無くなったか: kp_folder_gone <作業フォルダ> <鍵> [<kp_live_folders の出力>]
# 残っている作業フォルダの一覧(kp_live_folders)に、記録の作業フォルダか鍵のどちらも当たらなければ、
# 無くなったとみなす(session.sh の prune と同じ判定)。一覧を3つ目の引数で渡せば、一覧を取り直さない。
# 終了コード: 0(無くなった)、1(残っている。作業フォルダも鍵も空のときも1)、2(一覧を取れない)。
kp_folder_gone() {
    local folder="${1:-}" key="${2:-}" live rc ic id p k
    [ -n "$folder" ] || [ -n "$key" ] || return 1
    if [ $# -ge 3 ]; then
        live=$3
    else
        live=$(kp_live_folders)
        rc=$?
        [ "$rc" = 69 ] && exit 69
        [ "$rc" = 0 ] || return 2
    fi
    # 一覧には必ずいまの作業フォルダが入るので、空の一覧では判定しない
    [ -n "$live" ] || return 2
    ic=$(git config --get core.ignorecase 2>/dev/null)
    id=$(_kp_norm_with "$ic" "$folder")
    while IFS=$'\t' read -r p k; do
        [ -n "$p" ] || [ -n "$k" ] || continue
        [ -n "$folder" ] && [ "$(_kp_norm_with "$ic" "$p")" = "$id" ] && return 1
        [ -n "$key" ] && [ "$k" = "$key" ] && return 1
    done <<<"$live"
    return 0
}

# JSON の1つのキーの値を出す。文字列と数はそのまま、真偽は true/false、配列と表は JSON で出す。
# キーが無ければ何も出さない。ファイルが無いか読めなければ終了コード1。
kp_json_get() {
    perl -MJSON::PP -e '
        my ($file, $key) = @ARGV;
        open my $fh, "<:raw", $file or exit 1;
        local $/; my $text = <$fh>; close $fh;
        my $d = eval { JSON::PP->new->utf8->decode($text) };
        exit 1 unless ref $d eq "HASH";
        my $v = $d->{$key};
        exit 0 unless defined $v;
        if (JSON::PP::is_bool($v)) { print $v ? "true" : "false" }
        elsif (ref $v) { print JSON::PP->new->utf8->canonical->encode($v) }
        else { utf8::encode($v) if utf8::is_utf8($v); print $v }
    ' -- "$1" "$2"
}

# JSON に書く。<キー>=<値> は文字列、<キー>:=<JSON> は数・配列などをそのまま書く。
# ファイルがあれば中身を残して書き足す。同じディレクトリの一時ファイルに書いてから名前を変える。
kp_json_write() {
    perl -MJSON::PP -e '
        my $file = shift;
        my $json = JSON::PP->new->utf8->canonical;
        my $d = {};
        if (open my $fh, "<:raw", $file) {
            local $/; my $text = <$fh>; close $fh;
            my $old = eval { $json->decode($text) };
            $d = $old if ref $old eq "HASH";
        }
        for my $kv (@ARGV) {
            if ($kv =~ /\A([^=:]+):=(.*)\z/s) {
                my ($k, $raw) = ($1, $2);
                my $v = eval { JSON::PP->new->utf8->allow_nonref->decode($raw) };
                die "kp_json_write: JSON として読めない値: $kv\n" if $@;
                $d->{$k} = $v;
            } elsif ($kv =~ /\A([^=]+)=(.*)\z/s) {
                my ($k, $v) = ($1, $2);
                utf8::decode($v);
                $d->{$k} = $v;
            } else {
                die "kp_json_write: <キー>=<値> の形でない: $kv\n";
            }
        }
        my $tmp = "$file.tmp.$$";
        open my $out, ">:raw", $tmp or die "kp_json_write: 書けない: $tmp: $!\n";
        print $out $json->encode($d), "\n";
        close $out or do { unlink $tmp; die "kp_json_write: 書けない: $tmp\n" };
        rename $tmp, $file or do { unlink $tmp; die "kp_json_write: 名前を変えられない: $file\n" };
    ' -- "$@"
}

# セッションのID: 渡された値か、いまの作業フォルダのセッションの記録のうち started_at がいちばん古いもの
kp_session_id() {
    if [ -n "${1:-}" ]; then
        printf '%s\n' "$1"
        return 0
    fi
    local state key
    state=$(kp_state_dir) || exit $?
    key=$(kp_folder_key) || exit $?
    [ -d "$state/sessions" ] || return 0
    perl -MJSON::PP -e '
        my ($dir, $key) = @ARGV;
        opendir my $dh, $dir or exit 0;
        my @found;
        for my $name (sort readdir $dh) {
            next unless $name =~ /\.json\z/;
            open my $fh, "<:raw", "$dir/$name" or next;
            local $/; my $text = <$fh>; close $fh;
            my $d = eval { JSON::PP->new->utf8->decode($text) };
            next unless ref $d eq "HASH";
            next unless defined $d->{folder_key} && $d->{folder_key} eq $key;
            next unless defined $d->{session_id} && length $d->{session_id};
            push @found, $d;
        }
        exit 0 unless @found;
        my ($first) = sort { ($a->{started_at} // 0) <=> ($b->{started_at} // 0)
                             or $a->{session_id} cmp $b->{session_id} } @found;
        my $id = $first->{session_id};
        utf8::encode($id) if utf8::is_utf8($id);
        print "$id\n";
    ' -- "$state/sessions" "$key"
}

# 設定の数(git config keirekipro.parallelSlots。無ければ1)
kp_slots() {
    local v
    v=$(git config --get keirekipro.parallelSlots 2>/dev/null)
    if [ -z "$v" ]; then
        printf '1\n'
        return 0
    fi
    case "$v" in
        *[!0-9]*) _kp_die69 "keirekipro.parallelSlots の値 $v は1以上の整数ではない" ;;
    esac
    v=$((10#$v))
    [ "$v" -ge 1 ] || _kp_die69 "keirekipro.parallelSlots の値 $(git config --get keirekipro.parallelSlots) は1以上の整数ではない"
    printf '%s\n' "$v"
}

# 埋まっている枠の番号を小さい順に出す
_kp_slot_numbers() {
    local d name
    for d in "$1"/slots/*/; do
        [ -d "$d" ] || continue
        name=$(basename "$d")
        case "$name" in
            '' | *[!0-9]*) continue ;;
        esac
        printf '%s\n' "$name"
    done | sort -n
}

# ファイルかディレクトリの更新時刻(UNIX 秒)
_kp_mtime() {
    perl -e 'my @s = stat $ARGV[0]; print @s ? $s[9] : 0' -- "$1"
}

# 枠の持ち主を書く
_kp_write_owner() { # <枠のディレクトリ> <種類> <説明> <作業フォルダ> <鍵> <セッションのID>
    kp_json_write "$1/owner.json" folder="$4" folder_key="$5" kind="$2" command="$3" \
        started_at:="$(date +%s)" session_id="$6"
}

# 枠 k が取り戻しの条件に当たるかを確かめ、当たれば(ui なら枠のコンテナを消してから)取り戻す。
# 条件: check は始めて120秒より長く、枠のラベルの動いているコンテナが無いとき。
#       ui は持ち主のセッションの記録が無いときと、記録の作業フォルダが無くなっているとき(kp_folder_gone)。
#       ui の枠のコンテナを docker rm -f で消せなければ取り戻さない。
# 取り戻したら終了コード0。
_kp_reclaim_one() { # <記録の置き場所> <k>
    local state="$1" k="$2" dir owner kind started sid now ids before trash
    dir="$state/slots/$k"
    owner="$dir/owner.json"
    [ -d "$dir" ] || return 1
    now=$(date +%s)
    if [ -f "$owner" ]; then
        kind=$(kp_json_get "$owner" kind)
        started=$(kp_json_get "$owner" started_at)
        sid=$(kp_json_get "$owner" session_id)
    else
        # 枠を取った直後で持ち主をまだ書いていない枠。作った時刻で古さを決める
        kind=check
        started=$(_kp_mtime "$dir")
        sid=
    fi
    case "$started" in '' | *[!0-9]*) started=0 ;; esac
    before=$(cat "$owner" 2>/dev/null)
    case "$kind" in
        ui)
            # 持ち主のセッションの記録が残っていれば、記録の作業フォルダが無くなっているときだけ取り戻す
            # (サブシェルで呼ぶ: 終了コード69で exit しても取り戻しの錠を残さないため)
            if [ -n "$sid" ] && [ -f "$state/sessions/$sid.json" ]; then
                ( kp_folder_gone "$(kp_json_get "$state/sessions/$sid.json" folder)" \
                    "$(kp_json_get "$state/sessions/$sid.json" folder_key)" ) || return 1
            fi
            ids=$(docker ps -aq --filter "label=keirekipro.slot=$k" --filter label=keirekipro.kind=ui) || return 1
            if [ -n "$ids" ]; then
                # shellcheck disable=SC2086
                docker rm -f $ids >/dev/null || return 1
            fi
            ;;
        *)
            [ $((now - started)) -gt "$KP_CHECK_STALE_SECONDS" ] || return 1
            ids=$(docker ps -q --filter "label=keirekipro.slot=$k" --filter status=running) || return 1
            [ -z "$ids" ] || return 1
            ;;
    esac
    # 名前を変えてから中身を確かめる(確かめている間に持ち主が返し、別のセッションが取り直した枠を消さないため)
    trash="$state/slots/.reclaim-$k-$$"
    mv "$dir" "$trash" 2>/dev/null || return 1
    if [ "$(cat "$trash/owner.json" 2>/dev/null)" != "$before" ]; then
        mv -T "$trash" "$dir" 2>/dev/null
        return 1
    fi
    rm -rf "$trash"
    return 0
}

# 取り戻しの錠(取り戻すセッションどうしが同じ枠を同時に調べて消し合わないため)
_kp_lock() {
    local lock="$1" i=0
    while ! mkdir "$lock" 2>/dev/null; do
        if [ $(($(date +%s) - $(_kp_mtime "$lock"))) -gt 60 ]; then
            rm -rf "$lock"
            continue
        fi
        i=$((i + 1))
        [ "$i" -le 150 ] || return 1
        sleep 0.1
    done
    return 0
}

# 取り戻しの条件に当たる枠をすべて取り戻す(設定の数より大きい番号の枠も対象にする)
kp_slot_reclaim() {
    local state k lock
    state=$(kp_state_dir) || exit $?
    [ -d "$state/slots" ] || return 0
    lock="$state/slots/.reclaim.lock"
    _kp_lock "$lock" || return 1
    for k in $(_kp_slot_numbers "$state"); do
        _kp_reclaim_one "$state" "$k" || true
    done
    rmdir "$lock" 2>/dev/null
    return 0
}

# 1から設定の数までの順に枠を作り、作れた最初の番号を出す
_kp_try_slots() { # <記録の置き場所> <設定の数> <種類> <説明> <作業フォルダ> <鍵> <セッションのID>
    local k
    for ((k = 1; k <= $2; k++)); do
        if mkdir "$1/slots/$k" 2>/dev/null; then
            _kp_write_owner "$1/slots/$k" "$3" "$4" "$5" "$6" "$7" || {
                rm -rf "$1/slots/$k"
                return 1
            }
            printf '%s\n' "$k"
            return 0
        fi
    done
    return 1
}

# 枠を取る: kp_slot_acquire <種類 check|ui> <コマンドの説明>
# 取れたら枠の番号を出して終了コード0。取れなければ終了コード1。
kp_slot_acquire() {
    local kind="$1" desc="${2:-}" state n folder key sid k
    case "$kind" in
        check | ui) ;;
        *) _kp_die69 "枠の種類 $kind は check か ui ではない" ;;
    esac
    state=$(kp_state_dir) || exit $?
    n=$(kp_slots) || exit $?
    folder=$(kp_folder) || exit $?
    key=$(kp_folder_key) || exit $?
    sid=$(kp_session_id "${KP_SESSION_ID:-}") || exit $?
    mkdir -p "$state/slots" 2>/dev/null || _kp_die69 "記録の置き場所 $state/slots を作れない"

    # いまの作業フォルダが持つ ui の枠は、取り直したものとして同じ番号を返す
    if [ "$kind" = ui ]; then
        for k in $(_kp_slot_numbers "$state"); do
            [ "$(kp_json_get "$state/slots/$k/owner.json" kind)" = ui ] || continue
            [ "$(kp_json_get "$state/slots/$k/owner.json" folder_key)" = "$key" ] || continue
            _kp_write_owner "$state/slots/$k" "$kind" "$desc" "$folder" "$key" "$sid" || return 1
            printf '%s\n' "$k"
            return 0
        done
    fi

    _kp_try_slots "$state" "$n" "$kind" "$desc" "$folder" "$key" "$sid" && return 0
    kp_slot_reclaim || return 1
    _kp_try_slots "$state" "$n" "$kind" "$desc" "$folder" "$key" "$sid" && return 0
    return 1
}

# 枠を返す: 持ち主の作業フォルダがいまの作業フォルダのときだけ消す。消したら終了コード0。
kp_slot_release() {
    local k="$1" state key owner
    state=$(kp_state_dir) || exit $?
    key=$(kp_folder_key) || exit $?
    owner="$state/slots/$k/owner.json"
    [ -f "$owner" ] || return 1
    [ "$(kp_json_get "$owner" folder_key)" = "$key" ] || return 1
    rm -rf "$state/slots/$k"
}

# 枠の持ち主の一覧: 埋まっている枠ごとに1行、タブ区切りで
#   <枠の番号> <作業フォルダ> <Issueの番号> <種類> <始めた時刻>
# を出す。Issueの番号は、Issueの記録の作業フォルダから引く(無ければ空)。
kp_slot_holders() {
    local state ic
    state=$(kp_state_dir) || exit $?
    [ -d "$state/slots" ] || return 0
    ic=$(git config --get core.ignorecase 2>/dev/null)
    perl -MJSON::PP -e '
        my ($state, $ic) = @ARGV;
        my $json = JSON::PP->new->utf8;
        sub load {
            open my $fh, "<:raw", $_[0] or return undef;
            local $/; my $text = <$fh>; close $fh;
            my $d = eval { $json->decode($text) };
            return ref $d eq "HASH" ? $d : undef;
        }
        sub norm { my $p = $_[0] // ""; $p =~ tr/A-Z/a-z/ if $ic eq "true"; $p }
        my %issue;
        my %updated;
        if (opendir my $dh, "$state/issues") {
            for my $name (sort readdir $dh) {
                next unless $name =~ /\.json\z/;
                my $d = load("$state/issues/$name") or next;
                my $f = norm($d->{folder});
                next unless length $f && defined $d->{issue};
                my $u = $d->{updated_at} // 0;
                next if exists $updated{$f} && $updated{$f} > $u;
                ($issue{$f}, $updated{$f}) = ($d->{issue}, $u);
            }
        }
        opendir my $sh, "$state/slots" or exit 0;
        my @nums = sort { $a <=> $b } grep { /\A[0-9]+\z/ && -d "$state/slots/$_" } readdir $sh;
        for my $k (@nums) {
            my $d = load("$state/slots/$k/owner.json") // {};
            my $started = $d->{started_at} // (stat "$state/slots/$k")[9];
            my $folder = $d->{folder} // "";
            my $n = $issue{norm($folder)} // "";
            my $line = join("\t", $k, $folder, $n, $d->{kind} // "", $started) . "\n";
            utf8::encode($line) if utf8::is_utf8($line);
            print $line;
        }
    ' -- "$state" "$ic"
}
