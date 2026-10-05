#!/bin/bash
# =====================================================================
# session.sh(着手のときの調べと記録のスクリプト)のテスト
#
# 実行: bash .claude/scripts/parallel/tests/test-session.sh
# 一時的な git のリポジトリ(本体)と worktree を2つ(prune のテストではもう1つ)作り、その中で session.sh を呼ぶ。
# takeover --branch のテストでは、一時的な裸のリポジトリをリモート origin にする。
# docker は、呼ばれた引数を記録するだけの偽物(PATH の先頭に置く)に差し替える。
# 本物のリポジトリの記録(.git/keirekipro-parallel)と git の設定には触れない。
# 前提: bash・perl(JSON::PP)・git。ホストの Git Bash から流す。
# =====================================================================
set -u
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR KP_SESSION_ID

SESSION="$(cd "$(dirname "$0")/.." && pwd)/session.sh"
TMP_ROOT=$(mktemp -d)
trap 'rm -rf "$TMP_ROOT"' EXIT
# git が返すパス(Windows では C:/...)と同じ形で比べられるようにする
WORK=$(cd "$TMP_ROOT" && { pwd -W 2>/dev/null || pwd; })

# --- 偽物の docker
mkdir -p "$WORK/bin"
# FAKE_DB_RUNNING を設定すると、db が動いているときの答え(コンテナのID)を返し、
#   DB があるかの問いには、FAKE_DB_ABSENT に挙げた名前のほかは「ある」(1)と答える。
# FAKE_UI_CONTAINER を設定すると、ui のコンテナを探す問いに、そのコンテナの名前を返す。
# FAKE_FOLDER_CONTAINER を設定すると、作業フォルダのラベルのコンテナを探す問いに、そのコンテナの名前を返す。
# FAKE_RM_FAIL を設定すると、rm -f(コンテナを消す)が失敗する。
# FAKE_DOCKER_FAIL を設定すると、どの呼び出しも Docker につながらないときのように終了コード1で終わる。
# FAKE_VOLUME_INUSE / FAKE_VOLUME_MISSING に挙げたボリュームの volume rm は、使用中 / 無いの文で失敗する。
cat >"$WORK/bin/docker" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" >>"$FAKE_DOCKER_LOG"
if [ -n "${FAKE_DOCKER_FAIL:-}" ]; then
    echo "Cannot connect to the Docker daemon at unix:///var/run/docker.sock. Is the docker daemon running?" >&2
    exit 1
fi
case "$*" in
    "compose -p keirekipro ps --status running -q db")
        [ -n "${FAKE_DB_RUNNING:-}" ] && echo fake-db-id
        ;;
    "compose -p keirekipro exec -T db psql -U postgres -tAc SELECT 1 FROM pg_database WHERE datname="*)
        all="$*"
        db=${all##*datname=\'}
        db=${db%\'}
        case " ${FAKE_DB_ABSENT:-} " in *" $db "*) ;; *) echo 1 ;; esac
        ;;
    "volume rm "*)
        case " ${FAKE_VOLUME_INUSE:-} " in *" $3 "*)
            echo "Error response from daemon: remove $3: volume is in use - [abc123]" >&2
            exit 1
            ;;
        esac
        case " ${FAKE_VOLUME_MISSING:-} " in *" $3 "*)
            echo "Error response from daemon: get $3: no such volume" >&2
            exit 1
            ;;
        esac
        echo "$3"
        ;;
    "ps -aq --filter label=keirekipro.slot="*" --filter label=keirekipro.kind=ui")
        [ -n "${FAKE_UI_CONTAINER:-}" ] && echo "$FAKE_UI_CONTAINER"
        ;;
    "ps -aq --filter label=keirekipro.folder="*)
        [ -n "${FAKE_FOLDER_CONTAINER:-}" ] && echo "$FAKE_FOLDER_CONTAINER"
        ;;
    "rm -f "*)
        if [ -n "${FAKE_RM_FAIL:-}" ]; then
            echo "Error response from daemon: cannot remove container: permission denied" >&2
            exit 1
        fi
        ;;
esac
exit 0
EOF
chmod +x "$WORK/bin/docker"
# PATH は : 区切りなので、C: を含まない形のパスで先頭に置く
export PATH="$TMP_ROOT/bin:$PATH"
export FAKE_DOCKER_LOG="$WORK/docker.log"

# --- 一時的なリポジトリ(本体と worktree 2つ)
MAIN_DIR="$WORK/RepoMain"
WT_DIR="$WORK/RepoWT"
WT2_DIR="$WORK/RepoWT2"
# prune のテストで作って消す worktree
WT3_DIR="$WORK/RepoWT3"
# takeover --branch のテストで作るリモート(裸のリポジトリ)
ORIGIN_DIR="$WORK/origin.git"
GITC=(-c user.name=t -c user.email=t@example.com -c commit.gpgsign=false)
git init -q "$MAIN_DIR"
git -C "$MAIN_DIR" checkout -q -B main
mkdir -p "$MAIN_DIR/.kiro/specs/alpha"
printf '{"feature_name":"alpha","issue":10}\n' >"$MAIN_DIR/.kiro/specs/alpha/spec.json"
echo seed >"$MAIN_DIR/seed.txt"
git -C "$MAIN_DIR" add -A
git -C "$MAIN_DIR" "${GITC[@]}" commit -q -m seed
git -C "$MAIN_DIR" worktree add -q "$WT_DIR" -b feat/wt
git -C "$MAIN_DIR" worktree add -q "$WT2_DIR" -b feat/wt2
MAIN=$(git -C "$MAIN_DIR" rev-parse --show-toplevel)
WT=$(git -C "$WT_DIR" rev-parse --show-toplevel)
WT2=$(git -C "$WT2_DIR" rev-parse --show-toplevel)
STATE="$(git -C "$MAIN_DIR" rev-parse --path-format=absolute --git-common-dir)/keirekipro-parallel"
SEED_SHA=$(git -C "$MAIN_DIR" rev-parse HEAD)

# 記録の中で作業フォルダを比べる形(design.md の規則どおりに求める)
fid() {
    if [ "$(git -C "$MAIN_DIR" config --get core.ignorecase)" = true ]; then
        printf '%s' "$1" | tr 'ABCDEFGHIJKLMNOPQRSTUVWXYZ' 'abcdefghijklmnopqrstuvwxyz'
    else
        printf '%s' "$1"
    fi
}
fkey() { fid "$(git -C "$1" rev-parse --show-toplevel)" | git hash-object --stdin | cut -c1-12; }
# 無くなった作業フォルダの鍵(パスから直に求める)
fkey_path() { fid "$1" | git -C "$MAIN_DIR" hash-object --stdin | cut -c1-12; }

# ss <フォルダ> <引数>...: そのフォルダで session.sh を呼ぶ
ss() {
    local dir="$1"
    shift
    (cd "$dir" && bash "$SESSION" "$@")
}

# pj <JSON> <perl の式>: JSON を $d に読み、式の値を出す(配列と表は JSON、真偽は true/false、無ければ null)
pj() {
    printf '%s' "$1" | perl -MJSON::PP -e '
        local $/; my $d = JSON::PP->new->utf8->decode(<STDIN>);
        my $v = eval $ARGV[0]; die $@ if $@;
        if (!defined $v) { print "null" }
        elsif (JSON::PP::is_bool($v)) { print $v ? "true" : "false" }
        elsif (ref $v) { print JSON::PP->new->utf8->canonical->encode($v) }
        else { utf8::encode($v) if utf8::is_utf8($v); print $v }
    ' "$2"
}

# 記録の下書き(session.sh の書き込みに頼らずに置く)
put_session() { # <session_id> <folder> <folder_key> <started_at>
    mkdir -p "$STATE/sessions"
    printf '{"folder":"%s","folder_key":"%s","last_seen":%s,"session_id":"%s","started_at":%s}\n' \
        "$2" "$3" "$(($4 + 5))" "$1" "$4" >"$STATE/sessions/$1.json"
}
put_issue() { # <N> <folder> <branch> <session_id> [<handed_over_from の JSON>]
    mkdir -p "$STATE/issues"
    printf '{"branch":"%s","folder":"%s","handed_over_from":%s,"issue":%s,"session_id":"%s","updated_at":1}\n' \
        "$3" "$2" "${5:-[]}" "$1" "$4" >"$STATE/issues/$1.json"
}
put_spec() { # <作業フォルダ> <spec の名前> <issue> [<additional_issues の JSON>]
    mkdir -p "$1/.kiro/specs/$2"
    printf '{"additional_issues":%s,"feature_name":"%s","issue":%s}\n' \
        "${4:-[]}" "$2" "$3" >"$1/.kiro/specs/$2/spec.json"
}

reset_state() {
    local d b
    rm -rf "$STATE"
    git -C "$MAIN_DIR" config --unset keirekipro.parallelSlots 2>/dev/null
    # takeover のテストで足したリモートを外す
    git -C "$MAIN_DIR" remote remove origin 2>/dev/null
    rm -rf "$ORIGIN_DIR"
    # prune のテストで作った worktree を外す
    git -C "$MAIN_DIR" worktree remove --force "$WT3_DIR" 2>/dev/null
    rm -rf "$WT3_DIR"
    git -C "$MAIN_DIR" worktree prune
    for d in "$MAIN_DIR" "$WT_DIR" "$WT2_DIR"; do
        git -C "$d" reset -q --hard
        git -C "$d" clean -fdq
    done
    # ブランチを最初のコミットに戻す(前のテストのコミットを持ち越さない)。
    # takeover のテストでブランチが別の作業フォルダに移っていることがあるので、先にすべて手放させる
    for d in "$MAIN_DIR" "$WT_DIR" "$WT2_DIR"; do
        git -C "$d" switch -q --detach 2>/dev/null
    done
    git -C "$MAIN_DIR" switch -q main 2>/dev/null
    git -C "$WT_DIR" switch -q feat/wt 2>/dev/null
    git -C "$WT2_DIR" switch -q feat/wt2 2>/dev/null
    for d in "$MAIN_DIR" "$WT_DIR" "$WT2_DIR"; do
        git -C "$d" reset -q --hard "$SEED_SHA"
    done
    for b in $(git -C "$MAIN_DIR" for-each-ref --format='%(refname)' refs/remotes 'refs/heads/feat/extra*'); do
        git -C "$MAIN_DIR" update-ref -d "$b"
    done
    : >"$FAKE_DOCKER_LOG"
    unset KP_SESSION_ID
}

# 失敗の理由を出して、そのテストを終える(テストは run_test のサブシェルで動く)
die() {
    printf '%s\n' "$*"
    exit 1
}

pass=0
fail=0
run_test() { # <テスト名> <関数>
    local name="$1" fn="$2" out
    reset_state
    if out=$("$fn" 2>&1); then
        pass=$((pass + 1))
        printf 'ok: %s\n' "$name"
    else
        fail=$((fail + 1))
        printf 'FAIL: %s\n' "$name"
        printf '%s\n' "$out" | sed 's/^/    /'
    fi
}

# check-start を呼び、終了コード0と1行の JSON であることを確かめて JSON を出す
check_start() { # <フォルダ> <引数>...
    local out rc lines
    out=$(ss "$@" 2>/dev/null)
    rc=$?
    [ "$rc" = 0 ] || die "check-start の終了コード $rc"
    lines=$(printf '%s\n' "$out" | wc -l)
    [ "$lines" -eq 1 ] || die "check-start の出力が1行でない: $out"
    pj "$out" '1' >/dev/null 2>&1 || die "check-start の出力が JSON でない: $out"
    printf '%s' "$out"
}

# =====================================================================
# check-start: 同じ作業フォルダの別のセッション(要件5.1・5.2)
# =====================================================================
# shellcheck disable=SC2016 # $d などは pj に渡す perl の式の変数で、シェルの変数ではない
t_folder_conflict() {
    local out
    put_session s-old "$MAIN" "$(fkey "$MAIN_DIR")" 100
    # s-old は着手したセッション(Issueの記録がある)
    put_issue 77 "$MAIN" main s-old
    put_session s-me "$MAIN" "$(fkey "$MAIN_DIR")" 200
    put_session s-wt "$WT" "$(fkey "$WT_DIR")" 50
    out=$(check_start "$MAIN_DIR" check-start 42 --session s-me) || die "$out"
    [ "$(pj "$out" 'scalar @{$d->{folder_conflict}}')" = 1 ] || die "folder_conflict の数が1でない: $out"
    [ "$(pj "$out" '$d->{folder_conflict}[0]{session_id}')" = s-old ] || die "s-old が出ない: $out"
    [ "$(pj "$out" '$d->{folder_conflict}[0]{started_at}')" = 100 ] || die "started_at が違う: $out"
    [ "$(pj "$out" '$d->{folder_conflict}[0]{last_seen}')" = 105 ] || die "last_seen が違う: $out"
    # 別の作業フォルダのセッションは出ない
    out=$(check_start "$WT_DIR" check-start 42 --session s-wt) || die "$out"
    [ "$(pj "$out" '$d->{folder_conflict}')" = '[]' ] || die "worktree で folder_conflict が空でない: $out"
}

# shellcheck disable=SC2016 # $d などは pj に渡す perl の式の変数で、シェルの変数ではない
t_folder_conflict_without_session() {
    local out
    put_session s-old "$MAIN" "$(fkey "$MAIN_DIR")" 100
    put_session s-new "$MAIN" "$(fkey "$MAIN_DIR")" 200
    # 同じ作業フォルダにIssueの記録があるので、どちらも作業中
    put_issue 77 "$MAIN" main s-old
    # --session が無いときは、いまの作業フォルダのいちばん古い記録を自分とみなして除く
    out=$(check_start "$MAIN_DIR" check-start 42) || die "$out"
    [ "$(pj "$out" 'join ",", map { $_->{session_id} } @{$d->{folder_conflict}}')" = s-new ] \
        || die "--session が無いときの folder_conflict が s-new だけでない: $out"
    # 環境変数 KP_SESSION_ID でも渡せる
    out=$(KP_SESSION_ID=s-new check_start "$MAIN_DIR" check-start 42) || die "$out"
    [ "$(pj "$out" 'join ",", map { $_->{session_id} } @{$d->{folder_conflict}}')" = s-old ] \
        || die "KP_SESSION_ID=s-new のときの folder_conflict が s-old だけでない: $out"
}

# shellcheck disable=SC2016 # $d などは pj に渡す perl の式の変数で、シェルの変数ではない
t_end_clears_conflict() {
    local out
    put_session s-old "$MAIN" "$(fkey "$MAIN_DIR")" 100
    put_issue 77 "$MAIN" main s-old
    put_session s-me "$MAIN" "$(fkey "$MAIN_DIR")" 200
    out=$(check_start "$MAIN_DIR" check-start 42 --session s-me) || die "$out"
    [ "$(pj "$out" 'scalar @{$d->{folder_conflict}}')" = 1 ] || die "end の前に folder_conflict が出ない: $out"
    ss "$MAIN_DIR" end s-old || die "end の終了コード $?"
    [ ! -f "$STATE/sessions/s-old.json" ] || die "end のあとも s-old の記録が残っている"
    [ -f "$STATE/sessions/s-me.json" ] || die "end が自分の記録まで消した"
    out=$(check_start "$MAIN_DIR" check-start 42 --session s-me) || die "$out"
    [ "$(pj "$out" '$d->{folder_conflict}')" = '[]' ] || die "end のあとも folder_conflict が空でない: $out"
}

# shellcheck disable=SC2016 # $d などは pj に渡す perl の式の変数で、シェルの変数ではない
t_folder_conflict_idle_ignored() {
    local out
    put_session s-old "$MAIN" "$(fkey "$MAIN_DIR")" 100
    put_session s-me "$MAIN" "$(fkey "$MAIN_DIR")" 200
    # ほかの作業フォルダのIssueの記録は、いまの作業フォルダのセッションを作業中にしない
    put_session s-wt "$WT" "$(fkey "$WT_DIR")" 50
    put_issue 78 "$WT" feat/wt s-wt
    out=$(check_start "$MAIN_DIR" check-start 42 --session s-me) || die "$out"
    [ "$(pj "$out" '$d->{folder_conflict}')" = '[]' ] || die "着手していないセッションが folder_conflict に出た: $out"
}

t_end_rejects_path() {
    local rc
    mkdir -p "$STATE/sessions"
    echo '{}' >"$STATE/keep.json"
    ss "$MAIN_DIR" end ../keep >/dev/null 2>&1
    rc=$?
    [ "$rc" != 0 ] || die "パスを含むIDを受け付けた"
    [ -f "$STATE/keep.json" ] || die "記録の置き場所の外のファイルを消した"
}

# =====================================================================
# check-start: Issueの作りかけ(要件4.1・4.2)
# =====================================================================
# shellcheck disable=SC2016 # $d などは pj に渡す perl の式の変数で、シェルの変数ではない
t_leftover_other_worktree_spec() {
    local out
    put_spec "$WT_DIR" beta 42
    # その作業フォルダのセッションの記録が無いとき: active_session は null
    out=$(check_start "$MAIN_DIR" check-start 42 --session s-me) || die "$out"
    [ "$(pj "$out" 'scalar @{$d->{leftovers}}')" = 1 ] || die "leftovers の数が1でない: $out"
    [ "$(pj "$out" '$d->{leftovers}[0]{folder}')" = "$WT" ] || die "folder が worktree でない: $out"
    [ "$(pj "$out" '$d->{leftovers}[0]{is_self}')" = false ] || die "is_self が偽でない: $out"
    [ "$(pj "$out" 'join ",", @{$d->{leftovers}[0]{kinds}}')" = spec ] || die "kinds が spec でない: $out"
    [ "$(pj "$out" '$d->{leftovers}[0]{branch}')" = feat/wt ] || die "branch が feat/wt でない: $out"
    [ "$(pj "$out" '$d->{leftovers}[0]{active_session}')" = null ] || die "記録が無いのに active_session が null でない: $out"
    # その作業フォルダに作業中のセッションの記録があるとき: active_session にその記録が出る
    put_session s-wt "$WT" "$(fkey "$WT_DIR")" 300
    put_issue 77 "$WT" feat/wt s-wt
    out=$(check_start "$MAIN_DIR" check-start 42 --session s-me) || die "$out"
    [ "$(pj "$out" '$d->{leftovers}[0]{active_session}{session_id}')" = s-wt ] || die "active_session に s-wt が出ない: $out"
    [ "$(pj "$out" '$d->{leftovers}[0]{active_session}{started_at}')" = 300 ] || die "active_session の started_at が違う: $out"
    [ "$(pj "$out" '$d->{leftovers}[0]{active_session}{last_seen}')" = 305 ] || die "active_session の last_seen が違う: $out"
    # 作業中でない(Issueの記録に同じ session_id も同じ folder も無い)セッションは active_session に出ない
    rm -f "$STATE/issues/77.json"
    out=$(check_start "$MAIN_DIR" check-start 42 --session s-me) || die "$out"
    [ "$(pj "$out" '$d->{leftovers}[0]{active_session}')" = null ] || die "作業中でないセッションが active_session に出た: $out"
}

# shellcheck disable=SC2016 # $d などは pj に渡す perl の式の変数で、シェルの変数ではない
t_leftover_committed_spec_ignored() {
    local out
    put_spec "$WT_DIR" beta 42
    git -C "$WT_DIR" add -A
    git -C "$WT_DIR" "${GITC[@]}" commit -q -m beta
    out=$(check_start "$MAIN_DIR" check-start 42 --session s-me) || die "$out"
    [ "$(pj "$out" '$d->{leftovers}')" = '[]' ] || die "コミット済みの spec が leftovers に出た: $out"
    # コミット済みでも、直してまだコミットしていなければ出る
    printf '{"feature_name":"beta","issue":42,"phase":"x"}\n' >"$WT_DIR/.kiro/specs/beta/spec.json"
    out=$(check_start "$MAIN_DIR" check-start 42 --session s-me) || die "$out"
    [ "$(pj "$out" '$d->{leftovers}[0]{folder}')" = "$WT" ] || die "直した spec が leftovers に出ない: $out"
}

# shellcheck disable=SC2016 # $d などは pj に渡す perl の式の変数で、シェルの変数ではない
t_leftover_additional_issue() {
    local out
    put_spec "$WT2_DIR" gamma 5 '[42]'
    put_spec "$WT_DIR" delta 43
    out=$(check_start "$MAIN_DIR" check-start 42 --session s-me) || die "$out"
    [ "$(pj "$out" 'join ",", map { $_->{folder} } @{$d->{leftovers}}')" = "$WT2" ] \
        || die "additional_issues に 42 を含む spec だけが出ていない: $out"
}

# shellcheck disable=SC2016 # $d などは pj に渡す perl の式の変数で、シェルの変数ではない
t_leftover_self() {
    local out
    put_spec "$MAIN_DIR" beta 42
    put_session s-me "$MAIN" "$(fkey "$MAIN_DIR")" 100
    out=$(check_start "$MAIN_DIR" check-start 42 --session s-me) || die "$out"
    [ "$(pj "$out" 'scalar @{$d->{leftovers}}')" = 1 ] || die "leftovers の数が1でない: $out"
    [ "$(pj "$out" '$d->{leftovers}[0]{folder}')" = "$MAIN" ] || die "folder がいまの作業フォルダでない: $out"
    [ "$(pj "$out" '$d->{leftovers}[0]{is_self}')" = true ] || die "is_self が真でない: $out"
    [ "$(pj "$out" '$d->{leftovers}[0]{active_session}')" = null ] || die "自分が active_session に出た: $out"
}

# shellcheck disable=SC2016 # $d などは pj に渡す perl の式の変数で、シェルの変数ではない
t_leftover_own_claim_excluded() {
    local out
    put_spec "$MAIN_DIR" beta 42
    put_session s-me "$MAIN" "$(fkey "$MAIN_DIR")" 100
    ss "$MAIN_DIR" claim 42 --branch main --session s-me || die "claim の終了コード $?"
    # Issueの記録の folder がいまの作業フォルダで session_id が自分なら、自分の作りかけとして除く
    out=$(check_start "$MAIN_DIR" check-start 42 --session s-me) || die "$out"
    [ "$(pj "$out" '$d->{leftovers}')" = '[]' ] || die "自分の作りかけが leftovers に出た: $out"
    # 別のセッションから見ると、作りかけとして出る
    out=$(check_start "$MAIN_DIR" check-start 42 --session s-other) || die "$out"
    [ "$(pj "$out" '$d->{leftovers}[0]{is_self}')" = true ] || die "別のセッションから見て is_self の作りかけが出ない: $out"
    # コミットしていない spec は、コミットしていない変更でもある
    [ "$(pj "$out" 'join ",", @{$d->{leftovers}[0]{kinds}}')" = spec,changes,branch ] || die "kinds が spec,changes,branch でない: $out"
}

# shellcheck disable=SC2016 # $d などは pj に渡す perl の式の変数で、シェルの変数ではない
t_leftover_branch_without_spec() {
    local out
    put_issue 43 "$WT" feat/wt s-wt
    out=$(check_start "$MAIN_DIR" check-start 43 --session s-me) || die "$out"
    [ "$(pj "$out" 'scalar @{$d->{leftovers}}')" = 1 ] || die "leftovers の数が1でない: $out"
    [ "$(pj "$out" '$d->{leftovers}[0]{folder}')" = "$WT" ] || die "folder が worktree でない: $out"
    [ "$(pj "$out" 'join ",", @{$d->{leftovers}[0]{kinds}}')" = branch ] || die "kinds が branch でない: $out"
    [ "$(pj "$out" '$d->{leftovers}[0]{branch}')" = feat/wt ] || die "branch が違う: $out"
    [ "$(pj "$out" '$d->{branch_only}')" = '[]' ] || die "開かれているブランチが branch_only に出た: $out"
    # コミットしていない変更があれば changes も付く
    echo change >"$WT_DIR/work.txt"
    out=$(check_start "$MAIN_DIR" check-start 43 --session s-me) || die "$out"
    [ "$(pj "$out" 'join ",", @{$d->{leftovers}[0]{kinds}}')" = changes,branch ] || die "kinds が changes,branch でない: $out"
    # ほかのIssueの番号では出ない
    out=$(check_start "$MAIN_DIR" check-start 44 --session s-me) || die "$out"
    [ "$(pj "$out" '$d->{leftovers}')" = '[]' ] || die "ほかのIssueの番号で leftovers が出た: $out"
}

# shellcheck disable=SC2016 # $d などは pj に渡す perl の式の変数で、シェルの変数ではない
t_leftover_handed_over_excluded() {
    local out
    put_spec "$WT_DIR" beta 42
    put_spec "$MAIN_DIR" beta 42
    put_issue 42 "$MAIN" main s-me "[\"$WT\"]"
    out=$(check_start "$WT2_DIR" check-start 42 --session s-wt2) || die "$out"
    [ "$(pj "$out" 'join ",", map { $_->{folder} } @{$d->{leftovers}}')" = "$MAIN" ] \
        || die "handed_over_from の作業フォルダが除かれていない: $out"
}

# shellcheck disable=SC2016 # $d などは pj に渡す perl の式の変数で、シェルの変数ではない
t_branch_only() {
    local out
    git -C "$MAIN_DIR" branch -q feat/extra "$SEED_SHA"
    put_issue 42 "" feat/extra ""
    out=$(check_start "$MAIN_DIR" check-start 42 --session s-me) || die "$out"
    [ "$(pj "$out" '$d->{branch_only}')" = '[{"branch":"feat/extra","where":"local"}]' ] || die "ローカルのブランチが出ない: $out"
    [ "$(pj "$out" '$d->{leftovers}')" = '[]' ] || die "どこでも開かれていないブランチが leftovers に出た: $out"
    git -C "$MAIN_DIR" branch -q -D feat/extra
    git -C "$MAIN_DIR" update-ref refs/remotes/origin/feat/extra "$SEED_SHA"
    out=$(check_start "$MAIN_DIR" check-start 42 --session s-me) || die "$out"
    [ "$(pj "$out" '$d->{branch_only}')" = '[{"branch":"feat/extra","where":"remote"}]' ] || die "リモートのブランチが出ない: $out"
    git -C "$MAIN_DIR" update-ref -d refs/remotes/origin/feat/extra
    out=$(check_start "$MAIN_DIR" check-start 42 --session s-me) || die "$out"
    [ "$(pj "$out" '$d->{branch_only}')" = '[]' ] || die "どこにも無いブランチが branch_only に出た: $out"
}

# =====================================================================
# check-start: 作業中のセッションの数(要件3.6)
# =====================================================================
# shellcheck disable=SC2016 # $d などは pj に渡す perl の式の変数で、シェルの変数ではない
t_capacity() {
    local out
    put_session s-me "$MAIN" "$(fkey "$MAIN_DIR")" 100
    put_issue 51 "$MAIN" main s-me
    put_session s-wt "$WT" "$(fkey "$WT_DIR")" 200
    put_issue 50 "$WT" feat/wt s-wt
    # Issueの記録の無いセッション(着手していない)は作業中に数えない
    put_session s-idle "$WT2" "$(fkey "$WT2_DIR")" 300
    out=$(check_start "$MAIN_DIR" check-start 42 --session s-me) || die "$out"
    [ "$(pj "$out" '$d->{capacity}{limit}')" = 1 ] || die "limit が1でない: $out"
    [ "$(pj "$out" '$d->{capacity}{active}')" = "[{\"folder\":\"$WT\",\"issue\":50,\"last_seen\":205}]" ] \
        || die "active が自分以外の作業中のセッションだけでない: $out"
    git -C "$MAIN_DIR" config keirekipro.parallelSlots 2
    out=$(check_start "$MAIN_DIR" check-start 42 --session s-me) || die "$out"
    [ "$(pj "$out" '$d->{capacity}{limit}')" = 2 ] || die "設定の数が limit に出ない: $out"
    # 同じ folder のIssueの記録があれば、session_id が違っても作業中とみなす
    put_issue 52 "$WT2" feat/wt2 ""
    out=$(check_start "$MAIN_DIR" check-start 42 --session s-me) || die "$out"
    [ "$(pj "$out" 'join ",", map { $_->{issue} } @{$d->{capacity}{active}}')" = 50,52 ] \
        || die "同じ folder のIssueの記録があるセッションが active に出ない: $out"
}

# =====================================================================
# claim
# =====================================================================
# shellcheck disable=SC2016 # $d などは pj に渡す perl の式の変数で、シェルの変数ではない
t_claim() {
    local f got
    put_session s-me "$WT" "$(fkey "$WT_DIR")" 100
    ss "$WT_DIR" claim 42 --branch feat/wt --session s-me || die "claim の終了コード $?"
    f="$STATE/issues/42.json"
    [ -f "$f" ] || die "issues/42.json が無い"
    got=$(pj "$(cat "$f")" 'join "|", $d->{issue}, $d->{folder}, $d->{branch}, $d->{session_id}, scalar @{$d->{handed_over_from}}')
    [ "$got" = "42|$WT|feat/wt|s-me|0" ] || die "記録の中身が違う: $(cat "$f")"
    case "$(pj "$(cat "$f")" '$d->{updated_at}')" in '' | *[!0-9]*) die "updated_at が UNIX 秒でない: $(cat "$f")" ;; esac
    # すでにあれば folder branch session_id updated_at を書き直し、handed_over_from は残す
    put_issue 42 "$WT2" feat/old s-old "[\"$WT2\"]"
    ss "$MAIN_DIR" claim 42 --branch main --session s-new || die "2回目の claim の終了コード $?"
    got=$(pj "$(cat "$f")" 'join "|", $d->{issue}, $d->{folder}, $d->{branch}, $d->{session_id}, @{$d->{handed_over_from}}')
    [ "$got" = "42|$MAIN|main|s-new|$WT2" ] || die "書き直した記録が違う: $(cat "$f")"
    [ "$(pj "$(cat "$f")" '$d->{updated_at}')" != 1 ] || die "updated_at が書き直されていない"
    # --session が無いときは、いまの作業フォルダのいちばん古い記録のID
    ss "$WT_DIR" claim 43 --branch feat/wt || die "--session の無い claim の終了コード $?"
    [ "$(pj "$(cat "$STATE/issues/43.json")" '$d->{session_id}')" = s-me ] || die "--session が無いときのIDが違う"
}

t_claim_usage() {
    local rc
    ss "$MAIN_DIR" claim 42 >/dev/null 2>&1
    rc=$?
    [ "$rc" != 0 ] || die "--branch の無い claim を受け付けた"
    ss "$MAIN_DIR" claim abc --branch x >/dev/null 2>&1
    rc=$?
    [ "$rc" != 0 ] || die "数でないIssueの番号を受け付けた"
    [ ! -d "$STATE/issues" ] || [ -z "$(ls "$STATE/issues")" ] || die "誤った呼び方で記録を書いた"
}

# =====================================================================
# spec-names(要件1.1)
# =====================================================================
t_spec_names() {
    local out
    put_spec "$WT_DIR" beta 42
    put_spec "$WT2_DIR" gamma 43
    out=$(ss "$MAIN_DIR" spec-names) || die "spec-names の終了コード $?"
    [ "$out" = "$(printf 'alpha\nbeta\ngamma')" ] || die "spec の名前の一覧が違う: $out"
    # worktree から呼んでも同じ
    out=$(ss "$WT2_DIR" spec-names) || die "spec-names の終了コード $?"
    [ "$out" = "$(printf 'alpha\nbeta\ngamma')" ] || die "worktree から呼んだ一覧が違う: $out"
}

# =====================================================================
# prune(要件4.5)と docker
# =====================================================================
t_prune_callable() {
    local before rc
    put_session s-x "$WT" "$(fkey "$WT_DIR")" 100
    put_issue 42 "$WT" feat/wt s-x
    before=$(cat "$STATE/issues/42.json")
    ss "$MAIN_DIR" prune >/dev/null || die "prune の終了コード $?"
    [ -f "$STATE/sessions/s-x.json" ] || die "prune が記録を消した"
    [ "$(cat "$STATE/issues/42.json")" = "$before" ] || die "prune が残っている作業フォルダのIssueの記録を変えた: $(cat "$STATE/issues/42.json")"
    [ ! -s "$FAKE_DOCKER_LOG" ] || die "片付けるものが無いのに docker が呼ばれた: $(cat "$FAKE_DOCKER_LOG")"
    ss "$MAIN_DIR" prune extra >/dev/null 2>&1
    rc=$?
    [ "$rc" = 64 ] || die "引数の付いた prune の終了コードが64でない: $rc"
}

# WT3 を feat/extra で作り、Issue 42 を claim してセッションの記録を置く
make_wt3_claimed() {
    git -C "$MAIN_DIR" worktree add -q "$WT3_DIR" -b feat/extra || die "worktree を作れない"
    WT3=$(git -C "$WT3_DIR" rev-parse --show-toplevel)
    WT3_KEY=$(fkey "$WT3_DIR")
    put_session s-3 "$WT3" "$WT3_KEY" 100
    ss "$WT3_DIR" claim 42 --branch feat/extra --session s-3 || die "claim が失敗した"
}

# shellcheck disable=SC2016 # $d などは pj に渡す perl の式の変数で、シェルの変数ではない
t_prune_branch_kept() {
    local out f
    # db が動いている(記録の片付けはボリュームと DB を消し終えた作業フォルダだけ)
    export FAKE_DB_RUNNING=1
    make_wt3_claimed
    git -C "$MAIN_DIR" worktree remove "$WT3_DIR" || die "git worktree remove が失敗した"
    out=$(check_start "$MAIN_DIR" check-start 42 --session s-me) || die "$out"
    f="$STATE/issues/42.json"
    [ -f "$f" ] || die "ブランチが残っているのに issues/42.json が消えた"
    [ "$(pj "$(cat "$f")" 'join "|", $d->{issue}, $d->{folder}, $d->{branch}, $d->{session_id}')" = "42||feat/extra|" ] \
        || die "Issueの記録の folder と session_id が空になっていない: $(cat "$f")"
    [ ! -f "$STATE/sessions/s-3.json" ] || die "消えた作業フォルダのセッションの記録が残っている"
    [ "$(pj "$out" '$d->{branch_only}')" = '[{"branch":"feat/extra","where":"local"}]' ] || die "branch_only にブランチが出ない: $out"
    [ "$(pj "$out" '$d->{leftovers}')" = '[]' ] || die "消えた作業フォルダが leftovers に出た: $out"
    # リモートにだけ残っているときも残す
    git -C "$MAIN_DIR" update-ref refs/remotes/origin/feat/extra "$SEED_SHA"
    git -C "$MAIN_DIR" branch -q -D feat/extra
    out=$(check_start "$MAIN_DIR" check-start 42 --session s-me) || die "$out"
    [ -f "$f" ] || die "リモートにブランチが残っているのに issues/42.json が消えた"
    [ "$(pj "$out" '$d->{branch_only}')" = '[{"branch":"feat/extra","where":"remote"}]' ] || die "branch_only にリモートのブランチが出ない: $out"
}

# shellcheck disable=SC2016 # $d などは pj に渡す perl の式の変数で、シェルの変数ではない
t_prune_branch_gone() {
    local out
    # db が動いている(記録の片付けはボリュームと DB を消し終えた作業フォルダだけ)
    export FAKE_DB_RUNNING=1
    make_wt3_claimed
    git -C "$MAIN_DIR" worktree remove "$WT3_DIR" || die "git worktree remove が失敗した"
    ss "$MAIN_DIR" prune >/dev/null || die "prune の終了コード $?"
    [ -f "$STATE/issues/42.json" ] || die "ブランチが残っているのに issues/42.json が消えた"
    git -C "$MAIN_DIR" branch -q -D feat/extra
    out=$(check_start "$MAIN_DIR" check-start 42 --session s-me) || die "$out"
    [ ! -f "$STATE/issues/42.json" ] || die "ブランチも消したのに issues/42.json が残っている: $(cat "$STATE/issues/42.json")"
    [ "$(pj "$out" '$d->{branch_only}')" = '[]' ] || die "消したブランチが branch_only に出た: $out"
    # 作業フォルダとブランチが一度に無くなったときも消す
    put_issue 43 "$WORK/RepoGone" feat/none s-gone
    ss "$MAIN_DIR" prune >/dev/null || die "prune の終了コード $?"
    [ ! -f "$STATE/issues/43.json" ] || die "作業フォルダもブランチも無い issues/43.json が残っている"
}

# shellcheck disable=SC2016 # $d などは pj に渡す perl の式の変数で、シェルの変数ではない
t_prune_worktree_prune() {
    # db が動いている(記録の片付けはボリュームと DB を消し終えた作業フォルダだけ)
    export FAKE_DB_RUNNING=1
    make_wt3_claimed
    # ディレクトリだけを消した worktree(git では prunable)
    rm -rf "$WT3_DIR"
    git -C "$MAIN_DIR" worktree list --porcelain | grep -qx "worktree $WT3" || die "前提: 消した worktree が git の記録に残っていない"
    ss "$MAIN_DIR" prune >/dev/null || die "prune の終了コード $?"
    ! git -C "$MAIN_DIR" worktree list --porcelain | grep -qx "worktree $WT3" || die "git worktree prune で外れていない"
    git -C "$WT_DIR" switch -q feat/extra || die "残ったブランチに git switch できない"
    [ "$(pj "$(cat "$STATE/issues/42.json")" '$d->{folder}')" = "" ] || die "Issueの記録の folder が空になっていない"
}

t_prune_sessions() {
    local gone_key
    # db が動いている(記録の片付けはボリュームと DB を消し終えた作業フォルダだけ)
    export FAKE_DB_RUNNING=1
    gone_key=$(fkey_path "$WORK/RepoGone")
    put_session s-gone "$WORK/RepoGone" "$gone_key" 100
    put_session s-wt "$WT" "$(fkey "$WT_DIR")" 200
    put_session s-main "$MAIN" "$(fkey "$MAIN_DIR")" 300
    ss "$WT_DIR" prune >/dev/null || die "prune の終了コード $?"
    [ ! -f "$STATE/sessions/s-gone.json" ] || die "消えた作業フォルダのセッションの記録が残っている"
    [ -f "$STATE/sessions/s-wt.json" ] || die "worktree のセッションの記録が消えた"
    [ -f "$STATE/sessions/s-main.json" ] || die "本体フォルダのセッションの記録が消えた"
}

t_prune_volumes_and_db() {
    local k1 k2 k_wt k_main line
    k1=$(fkey_path "$WORK/RepoGone")
    k2=$(fkey_path "$WORK/RepoGone2")
    k_wt=$(fkey "$WT_DIR")
    k_main=$(fkey "$MAIN_DIR")
    put_session s-gone "$WORK/RepoGone" "$k1" 100
    put_issue 44 "$WORK/RepoGone2" feat/none s-gone2
    put_session s-wt "$WT" "$k_wt" 200
    put_issue 45 "$WT" feat/wt s-wt
    FAKE_DB_RUNNING=1 ss "$MAIN_DIR" prune >/dev/null || die "prune の終了コード $?"
    for line in "volume rm kp-nm-$k1" "volume rm kp-gradle-project-$k1" \
        "volume rm kp-nm-$k2" "volume rm kp-gradle-project-$k2" \
        "compose -p keirekipro exec -T db psql -U postgres -c DROP DATABASE IF EXISTS kp_$k1" \
        "compose -p keirekipro exec -T db psql -U postgres -c DROP DATABASE IF EXISTS kp_$k2"; do
        grep -qxF "$line" "$FAKE_DOCKER_LOG" || die "docker に '$line' が渡っていない: $(cat "$FAKE_DOCKER_LOG")"
    done
    ! grep -qe "$k_wt" -e "$k_main" "$FAKE_DOCKER_LOG" || die "残っている作業フォルダのボリュームか DB を消した: $(cat "$FAKE_DOCKER_LOG")"
    [ "$(grep -c "volume rm kp-nm-$k1" "$FAKE_DOCKER_LOG")" = 1 ] || die "同じ鍵のボリュームを2回以上消した"
}

t_prune_db_not_running() {
    local k1
    k1=$(fkey_path "$WORK/RepoGone")
    put_session s-gone "$WORK/RepoGone" "$k1" 100
    ss "$MAIN_DIR" prune >/dev/null || die "prune の終了コード $?"
    ! grep -q "DROP DATABASE" "$FAKE_DOCKER_LOG" || die "db が動いていないのに DROP DATABASE を打った: $(cat "$FAKE_DOCKER_LOG")"
    grep -qxF "volume rm kp-nm-$k1" "$FAKE_DOCKER_LOG" || die "db が動いていないときにボリュームの片付けまで飛ばした: $(cat "$FAKE_DOCKER_LOG")"
    [ -f "$STATE/sessions/s-gone.json" ] || die "db が動いていない(DB を消し終えていない)のに記録を片付けた"
}

t_prune_docker_unreachable() {
    local k1 out err
    k1=$(fkey_path "$WORK/RepoGone")
    put_session s-gone "$WORK/RepoGone" "$k1" 100
    out=$(FAKE_DOCKER_FAIL=1 FAKE_DB_RUNNING=1 ss "$MAIN_DIR" prune 2>"$TMP_ROOT/err.txt") || die "prune の終了コード $?"
    err=$(cat "$TMP_ROOT/err.txt")
    ! printf '%s' "$out" | grep -q "ボリューム" || die "Docker につながらないのにボリュームを消したと出した: $out"
    printf '%s' "$err" | grep -q "Docker につながらない" || die "Docker につながらないことを標準エラーに出さない: $err"
    printf '%s' "$err" | grep -q "鍵 $k1" || die "標準エラーに鍵が出ない: $err"
    printf '%s' "$err" | grep -q "kp-nm-$k1 kp-gradle-project-$k1" || die "標準エラーに消せなかったボリュームの名前が出ない: $err"
    printf '%s' "$err" | grep -q "kp_$k1" || die "標準エラーに消せなかった DB の名前が出ない: $err"
    ! grep -qE "volume rm|DROP DATABASE" "$FAKE_DOCKER_LOG" || die "Docker につながらないのに消そうとした: $(cat "$FAKE_DOCKER_LOG")"
    [ -f "$STATE/sessions/s-gone.json" ] || die "Docker につながらない(ボリュームと DB を消し終えていない)のに記録を片付けた"
}

t_prune_volume_failures_reported() {
    local k1 out err
    k1=$(fkey_path "$WORK/RepoGone")
    put_session s-gone "$WORK/RepoGone" "$k1" 100
    out=$(FAKE_DB_RUNNING=1 FAKE_DB_ABSENT="kp_$k1" FAKE_VOLUME_INUSE="kp-nm-$k1" \
        FAKE_VOLUME_MISSING="kp-gradle-project-$k1" ss "$MAIN_DIR" prune 2>"$TMP_ROOT/err.txt") \
        || die "prune の終了コード $?"
    err=$(cat "$TMP_ROOT/err.txt")
    # 使用中で消せなかったボリュームは、名前つきで標準エラーに出す
    printf '%s' "$err" | grep -q "kp-nm-$k1 を消せない: .*volume is in use" || die "使用中のボリュームを標準エラーに出さない: $err"
    # 無いものは失敗として出さない
    ! printf '%s' "$err" | grep -q "kp-gradle-project-$k1" || die "無いボリュームを失敗として出した: $err"
    ! printf '%s' "$err" | grep -q "kp_$k1" || die "無い DB を失敗として出した: $err"
    # 消せたものが無いので、「消した」は出さない
    ! printf '%s' "$out" | grep -q "ボリュームと DB を消した" || die "消せなかったのに消したと出した: $out"
    ! grep -q "DROP DATABASE" "$FAKE_DOCKER_LOG" || die "無い DB に DROP DATABASE を打った"
    # 一部が消せたときは、消せたものだけを出す
    put_session s-gone "$WORK/RepoGone" "$k1" 100
    out=$(FAKE_DB_RUNNING=1 FAKE_VOLUME_INUSE="kp-nm-$k1" ss "$MAIN_DIR" prune 2>/dev/null) || die "prune の終了コード $?"
    printf '%s' "$out" | grep -qx "\[parallel\] 片付け: 作業フォルダごとのボリュームと DB を消した: kp-gradle-project-$k1 kp_$k1" \
        || die "消せたものだけを出していない: $out"
}

t_prune_slots() {
    local now k_gone
    now=$(date +%s)
    k_gone=$(fkey_path "$WORK/RepoGone")
    mkdir -p "$STATE/slots/1" "$STATE/slots/2" "$STATE/slots/3"
    # 古い check の枠(動いているコンテナは無い)
    printf '{"folder":"%s","folder_key":"%s","kind":"check","command":"x","started_at":1,"session_id":"s-wt"}\n' \
        "$WT" "$(fkey "$WT_DIR")" >"$STATE/slots/1/owner.json"
    # 消えた作業フォルダのセッションが持っていた ui の枠
    printf '{"folder":"%s","folder_key":"%s","kind":"ui","command":"ui","started_at":%s,"session_id":"s-gone"}\n' \
        "$WORK/RepoGone" "$k_gone" "$now" >"$STATE/slots/2/owner.json"
    put_session s-gone "$WORK/RepoGone" "$k_gone" 100
    # 始めたばかりの check の枠は取り戻さない
    printf '{"folder":"%s","folder_key":"%s","kind":"check","command":"x","started_at":%s,"session_id":"s-wt"}\n' \
        "$WT" "$(fkey "$WT_DIR")" "$now" >"$STATE/slots/3/owner.json"
    FAKE_UI_CONTAINER=kp-ui-2-backend ss "$MAIN_DIR" prune >/dev/null || die "prune の終了コード $?"
    [ ! -d "$STATE/slots/1" ] || die "古い check の枠が取り戻されていない"
    [ ! -d "$STATE/slots/2" ] || die "消えた作業フォルダの ui の枠が取り戻されていない"
    [ -d "$STATE/slots/3" ] || die "始めたばかりの check の枠を取り戻した"
    # ui のコンテナを消してから、そのボリュームを消す
    awk -v a="rm -f kp-ui-2-backend" -v b="volume rm kp-nm-$k_gone" \
        '$0 == a && !ra { ra = NR } $0 == b && !rb { rb = NR } END { exit !(ra && rb && ra < rb) }' "$FAKE_DOCKER_LOG" \
        || die "ui のコンテナを消してからボリュームを消していない: $(cat "$FAKE_DOCKER_LOG")"
}

# shellcheck disable=SC2016 # $d などは pj に渡す perl の式の変数で、シェルの変数ではない
t_prune_skips_without_worktree_list() {
    local real_git
    real_git=$(command -v git)
    mkdir -p "$TMP_ROOT/gitfail"
    # worktree list だけが失敗する git
    cat >"$TMP_ROOT/gitfail/git" <<EOF
#!/bin/bash
case " \$* " in *" worktree list "*) exit 128 ;; esac
exec "$real_git" "\$@"
EOF
    chmod +x "$TMP_ROOT/gitfail/git"
    put_session s-wt "$WT" "$(fkey "$WT_DIR")" 100
    put_issue 42 "$WT" feat/wt s-wt
    (PATH="$TMP_ROOT/gitfail:$PATH" ss "$MAIN_DIR" prune >/dev/null 2>&1) || die "prune の終了コード $?"
    [ -f "$STATE/sessions/s-wt.json" ] || die "作業フォルダの一覧を取れないときにセッションの記録を消した"
    [ "$(pj "$(cat "$STATE/issues/42.json")" '$d->{folder}')" = "$WT" ] || die "作業フォルダの一覧を取れないときにIssueの記録を変えた"
    [ ! -s "$FAKE_DOCKER_LOG" ] || die "作業フォルダの一覧を取れないときに docker を呼んだ: $(cat "$FAKE_DOCKER_LOG")"
}

t_prune_quiet_in_check_start() {
    local out
    # db が動いている(記録の片付けはボリュームと DB を消し終えた作業フォルダだけ)
    export FAKE_DB_RUNNING=1
    put_session s-gone "$WORK/RepoGone" "$(fkey_path "$WORK/RepoGone")" 100
    out=$(check_start "$MAIN_DIR" check-start 42 --session s-me) || die "$out"
    [ ! -f "$STATE/sessions/s-gone.json" ] || die "check-start が最初に prune を行っていない"
    # 手で打った prune は、片付けたことを標準出力に出す
    put_session s-gone "$WORK/RepoGone" "$(fkey_path "$WORK/RepoGone")" 100
    out=$(ss "$MAIN_DIR" prune) || die "prune の終了コード $?"
    printf '%s' "$out" | grep -q '^\[parallel\] 片付け' || die "prune が片付けたことを出さない: $out"
}

# 消し終えていない作業フォルダの記録を残し、次の prune がもう一度消しにいく(要件3.6・4.5)
t_prune_retry_after_docker_back() {
    local k1 s_before i_before err line
    k1=$(fkey_path "$WORK/RepoGone")
    put_session s-gone "$WORK/RepoGone" "$k1" 100
    put_issue 42 "$WORK/RepoGone" feat/wt s-gone
    # folder が空で、ブランチがどこにも無いIssueの記録(鍵が無いので、鍵の片付けを待たずに消す)
    put_issue 46 "" feat/none ""
    s_before=$(cat "$STATE/sessions/s-gone.json")
    i_before=$(cat "$STATE/issues/42.json")
    FAKE_DOCKER_FAIL=1 ss "$MAIN_DIR" prune >/dev/null 2>"$TMP_ROOT/err.txt" || die "prune の終了コード $?"
    err=$(cat "$TMP_ROOT/err.txt")
    [ "$(cat "$STATE/sessions/s-gone.json" 2>/dev/null)" = "$s_before" ] \
        || die "Docker につながらないのにセッションの記録が書き換わった: $(cat "$STATE/sessions/s-gone.json" 2>&1)"
    [ "$(cat "$STATE/issues/42.json" 2>/dev/null)" = "$i_before" ] \
        || die "Docker につながらないのにIssueの記録が書き換わった: $(cat "$STATE/issues/42.json" 2>&1)"
    [ ! -f "$STATE/issues/46.json" ] || die "folder が空でブランチがどこにも無いIssueの記録を消していない"
    printf '%s' "$err" | grep -q "kp-nm-$k1 kp-gradle-project-$k1" || die "標準エラーに消せなかったボリュームの名前が出ない: $err"
    printf '%s' "$err" | grep -q "kp_$k1" || die "標準エラーに消せなかった DB の名前が出ない: $err"
    printf '%s' "$err" | grep -q "次の片付け.*もう一度消しにいく" || die "次の片付けがもう一度消しにいくことを出さない: $err"
    ! printf '%s' "$err" | grep -q "手で消す" || die "手で消すことを求める文が残っている: $err"
    # Docker が戻ってから打ち直すと、同じ鍵のボリュームと DB を消して記録が片付く
    : >"$FAKE_DOCKER_LOG"
    FAKE_DB_RUNNING=1 ss "$MAIN_DIR" prune >/dev/null || die "打ち直した prune の終了コード $?"
    for line in "volume rm kp-nm-$k1" "volume rm kp-gradle-project-$k1" \
        "compose -p keirekipro exec -T db psql -U postgres -c DROP DATABASE IF EXISTS kp_$k1"; do
        grep -qxF "$line" "$FAKE_DOCKER_LOG" || die "打ち直しで docker に '$line' が渡っていない: $(cat "$FAKE_DOCKER_LOG")"
    done
    [ ! -f "$STATE/sessions/s-gone.json" ] || die "打ち直したあともセッションの記録が残っている"
    [ "$(pj "$(cat "$STATE/issues/42.json")" "join '|', \$d->{folder}, \$d->{branch}, \$d->{session_id}")" = "|feat/wt|" ] \
        || die "打ち直したあと、Issueの記録の folder と session_id が空になっていない: $(cat "$STATE/issues/42.json")"
}

t_prune_kept_not_active() {
    local out
    export FAKE_DOCKER_FAIL=1
    put_session s-gone "$WORK/RepoGone" "$(fkey_path "$WORK/RepoGone")" 100
    put_issue 50 "$WORK/RepoGone" feat/none s-gone
    put_session s-wt "$WT" "$(fkey "$WT_DIR")" 200
    put_issue 51 "$WT" feat/wt s-wt
    out=$(check_start "$MAIN_DIR" check-start 42 --session s-me) || die "$out"
    [ -f "$STATE/sessions/s-gone.json" ] || die "消せなかった作業フォルダのセッションの記録が残っていない"
    [ "$(pj "$out" "join ',', map { \$_->{issue} } @{\$d->{capacity}{active}}")" = 51 ] \
        || die "capacity.active に、作業フォルダが無くなったセッションが出たか、作業中のセッションが出ない: $out"
}

t_prune_branch_only_while_kept() {
    local out
    make_wt3_claimed
    git -C "$MAIN_DIR" worktree remove "$WT3_DIR" || die "git worktree remove が失敗した"
    export FAKE_DOCKER_FAIL=1
    out=$(check_start "$MAIN_DIR" check-start 42 --session s-me) || die "$out"
    [ "$(pj "$(cat "$STATE/issues/42.json")" "\$d->{folder}")" = "$WT3" ] || die "Issueの記録が書き換わった: $(cat "$STATE/issues/42.json")"
    [ -f "$STATE/sessions/s-3.json" ] || die "消せなかった作業フォルダのセッションの記録が残っていない"
    [ "$(pj "$out" "\$d->{branch_only}")" = '[{"branch":"feat/extra","where":"local"}]' ] || die "branch_only にブランチが出ない: $out"
    [ "$(pj "$out" "\$d->{leftovers}")" = '[]' ] || die "消えた作業フォルダが leftovers に出た: $out"
}

# 無くなった作業フォルダの鍵の枠を書く
put_gone_slots() { # <鍵> <始めた時刻>
    mkdir -p "$STATE/slots/1" "$STATE/slots/2" "$STATE/slots/3"
    # 無くなった作業フォルダの、始めたばかりの check の枠(lib.sh の取り戻しの条件には当たらない)
    printf '{"folder":"%s","folder_key":"%s","kind":"check","command":"x","started_at":%s,"session_id":"s-gone"}\n' \
        "$WORK/RepoGone" "$1" "$2" >"$STATE/slots/1/owner.json"
    # 無くなった作業フォルダの ui の枠(持ち主のセッションの記録は残っている)
    printf '{"folder":"%s","folder_key":"%s","kind":"ui","command":"ui","started_at":%s,"session_id":"s-gone"}\n' \
        "$WORK/RepoGone" "$1" "$2" >"$STATE/slots/2/owner.json"
    # 残っている作業フォルダの、始めたばかりの check の枠
    printf '{"folder":"%s","folder_key":"%s","kind":"check","command":"x","started_at":%s,"session_id":"s-wt"}\n' \
        "$WT" "$(fkey "$WT_DIR")" "$2" >"$STATE/slots/3/owner.json"
}

t_prune_frees_slots_while_kept() {
    local k_gone
    k_gone=$(fkey_path "$WORK/RepoGone")
    put_session s-gone "$WORK/RepoGone" "$k_gone" 100
    put_gone_slots "$k_gone" "$(date +%s)"
    # db が動いていないので、記録は残る
    FAKE_FOLDER_CONTAINER=kp-check-gone ss "$MAIN_DIR" prune >/dev/null 2>&1 || die "prune の終了コード $?"
    [ -f "$STATE/sessions/s-gone.json" ] || die "前提: DB を消し終えていないのに記録を片付けた"
    grep -qxF "ps -aq --filter label=keirekipro.folder=$k_gone" "$FAKE_DOCKER_LOG" \
        || die "無くなった作業フォルダのラベルのコンテナを探していない: $(cat "$FAKE_DOCKER_LOG")"
    ! grep -qF "label=keirekipro.folder=$(fkey "$WT_DIR")" "$FAKE_DOCKER_LOG" \
        || die "残っている作業フォルダのラベルのコンテナに触れた: $(cat "$FAKE_DOCKER_LOG")"
    [ ! -d "$STATE/slots/1" ] || die "無くなった作業フォルダの check の枠を取り戻していない"
    [ ! -d "$STATE/slots/2" ] || die "無くなった作業フォルダの ui の枠を取り戻していない"
    [ -d "$STATE/slots/3" ] || die "残っている作業フォルダの枠を取り戻した"
    # コンテナを消してから、ボリュームを消す
    awk -v a="rm -f kp-check-gone" -v b="volume rm kp-nm-$k_gone" \
        '$0 == a && !ra { ra = NR } $0 == b && !rb { rb = NR } END { exit !(ra && rb && ra < rb) }' "$FAKE_DOCKER_LOG" \
        || die "ラベルのコンテナを消してからボリュームを消していない: $(cat "$FAKE_DOCKER_LOG")"
}

t_prune_unreachable_keeps_slots() {
    local k_gone
    k_gone=$(fkey_path "$WORK/RepoGone")
    put_session s-gone "$WORK/RepoGone" "$k_gone" 100
    # 古い(lib.sh の取り戻しの条件の時間を過ぎた)枠
    put_gone_slots "$k_gone" 1
    FAKE_DOCKER_FAIL=1 FAKE_FOLDER_CONTAINER=kp-check-gone ss "$MAIN_DIR" prune >/dev/null 2>&1 || die "prune の終了コード $?"
    [ -d "$STATE/slots/1" ] || die "Docker につながらない(コンテナを消せない)のに check の枠を取り戻した"
    [ -d "$STATE/slots/2" ] || die "Docker につながらない(コンテナを消せない)のに ui の枠を取り戻した"
    [ -d "$STATE/slots/3" ] || die "Docker につながらない(コンテナを消せない)のに残っている作業フォルダの枠を取り戻した"
    # Docker にはつながるが、docker rm -f でコンテナを消せないときも取り戻さない
    rm -rf "$STATE/slots"
    put_gone_slots "$k_gone" "$(date +%s)"
    FAKE_RM_FAIL=1 FAKE_FOLDER_CONTAINER=kp-check-gone FAKE_UI_CONTAINER=kp-ui-2-backend \
        ss "$MAIN_DIR" prune >/dev/null 2>"$TMP_ROOT/err.txt" || die "prune の終了コード $?"
    grep -qxF "rm -f kp-check-gone" "$FAKE_DOCKER_LOG" || die "前提: ラベルのコンテナに docker rm -f を打っていない: $(cat "$FAKE_DOCKER_LOG")"
    [ -d "$STATE/slots/1" ] || die "docker rm -f でコンテナを消せないのに check の枠を取り戻した"
    [ -d "$STATE/slots/2" ] || die "docker rm -f でコンテナを消せないのに ui の枠を取り戻した"
    grep -q "コンテナを消せない" "$TMP_ROOT/err.txt" || die "コンテナを消せなかったことを標準エラーに出さない: $(cat "$TMP_ROOT/err.txt")"
}

t_check_start_reports_kept() {
    local k1 out err lines
    k1=$(fkey_path "$WORK/RepoGone")
    put_session s-gone "$WORK/RepoGone" "$k1" 100
    out=$(FAKE_DOCKER_FAIL=1 ss "$MAIN_DIR" check-start 42 --session s-me 2>"$TMP_ROOT/err.txt") || die "check-start の終了コード $?"
    err=$(cat "$TMP_ROOT/err.txt")
    lines=$(printf '%s\n' "$out" | wc -l)
    [ "$lines" -eq 1 ] || die "check-start の標準出力が1行でない: $out"
    [ "$(pj "$out" "\$d->{capacity}{active}")" = '[]' ] || die "check-start の標準出力の JSON が読めないか、capacity.active が空でない: $out"
    printf '%s' "$err" | grep -q "kp-nm-$k1 kp-gradle-project-$k1" || die "check-start の標準エラーに消せなかったボリュームの名前が出ない: $err"
    printf '%s' "$err" | grep -q "kp_$k1" || die "check-start の標準エラーに消せなかった DB の名前が出ない: $err"
    printf '%s' "$err" | grep -q "次の片付け.*もう一度消しにいく" || die "check-start の標準エラーに、次の片付けがもう一度消しにいくことが出ない: $err"
}

t_no_docker_in_check_start() {
    local out
    put_spec "$WT_DIR" beta 42
    out=$(check_start "$MAIN_DIR" check-start 42 --session s-me) || die "$out"
    ss "$MAIN_DIR" claim 42 --branch main --session s-me || die "claim が失敗した"
    ss "$MAIN_DIR" spec-names >/dev/null || die "spec-names が失敗した"
    [ ! -s "$FAKE_DOCKER_LOG" ] || die "docker が呼ばれた: $(cat "$FAKE_DOCKER_LOG")"
}

# =====================================================================
# takeover(要件1.1・1.2・4.3〜4.6)
# =====================================================================
# 作業フォルダのいまのブランチ(detached なら空)
cur_branch() { git -C "$1" symbolic-ref -q --short HEAD; }
# 作業フォルダのコミットしていない変更と git の管理外のファイル
wt_status() { git -C "$1" status --porcelain --untracked-files=all; }
# Issueの記録の欄を | でつないで出す(handed_over_from は , でつなぐ)
# shellcheck disable=SC2016 # $d などは pj に渡す perl の式の変数で、シェルの変数ではない
issue_fields() { # <N>
    pj "$(cat "$STATE/issues/$1.json")" \
        'join "|", $d->{issue}, $d->{folder}, $d->{branch}, $d->{session_id}, join(",", @{$d->{handed_over_from}})'
}

# WT で Issue 42 を進めていた形: feat/wt にコミットが1つあり、コミットしていない spec と変更と、
# 索引に載せた git の管理外のファイル(中身は2進)が残っている。WT のセッション s-wt は作業中
make_wt_leftover() {
    echo committed >"$WT_DIR/wt-commit.txt"
    git -C "$WT_DIR" add -A
    git -C "$WT_DIR" "${GITC[@]}" commit -q -m wt-commit
    put_session s-wt "$WT" "$(fkey "$WT_DIR")" 100
    put_issue 42 "$WT" feat/wt s-wt
    put_spec "$WT_DIR" beta 42
    printf 'seed\nwt-change\n' >"$WT_DIR/seed.txt"
    printf '\000\001\002\377' >"$WT_DIR/bin.dat"
    git -C "$WT_DIR" add bin.dat
}

t_takeover_copies_from_other_worktree() {
    local out before head
    make_wt_leftover
    before=$(wt_status "$WT_DIR")
    head=$(git -C "$WT_DIR" rev-parse HEAD)
    out=$(ss "$WT2_DIR" takeover 42 --from "$WT" --session s-me) || die "takeover の終了コード $?: $out"
    # ブランチと、コミットしていない spec と変更が写る
    [ "$(cur_branch "$WT2_DIR")" = feat/wt ] || die "いまの作業フォルダが feat/wt に切り替わっていない: $(cur_branch "$WT2_DIR")"
    [ "$(git -C "$WT2_DIR" rev-parse HEAD)" = "$head" ] || die "いまの作業フォルダの HEAD が前の作業フォルダの HEAD でない"
    for f in .kiro/specs/beta/spec.json seed.txt bin.dat wt-commit.txt; do
        cmp -s "$WT_DIR/$f" "$WT2_DIR/$f" || die "$f が写っていない"
    done
    # 前の作業フォルダの中身と索引は消えない
    [ "$(wt_status "$WT_DIR")" = "$before" ] || die "前の作業フォルダの変更が変わった: $(wt_status "$WT_DIR")"
    [ "$(cat "$WT_DIR/seed.txt")" = "$(printf 'seed\nwt-change')" ] || die "前の作業フォルダの seed.txt が変わった"
    [ -f "$WT_DIR/.kiro/specs/beta/spec.json" ] || die "前の作業フォルダの spec が消えた"
    # Issueの記録が、いまの作業フォルダとセッションに書き直され、前の作業フォルダが handed_over_from に入る
    [ "$(issue_fields 42)" = "42|$WT2|feat/wt|s-me|$WT" ] || die "Issueの記録が違う: $(cat "$STATE/issues/42.json")"
    # 写したファイルの一覧といまのブランチを出す
    for f in .kiro/specs/beta/spec.json seed.txt bin.dat; do
        printf '%s' "$out" | grep -qF "$f" || die "写したファイルの一覧に $f が無い: $out"
    done
    printf '%s' "$out" | grep -q "いまのブランチ: feat/wt\$" || die "いまのブランチが出ない: $out"
}

t_takeover_releases_branch() {
    local head
    make_wt_leftover
    head=$(git -C "$WT_DIR" rev-parse HEAD)
    ss "$WT2_DIR" takeover 42 --from "$WT" --session s-me >/dev/null || die "takeover の終了コード $?"
    [ -z "$(cur_branch "$WT_DIR")" ] || die "前の作業フォルダがブランチを手放していない: $(cur_branch "$WT_DIR")"
    [ "$(git -C "$WT_DIR" rev-parse HEAD)" = "$head" ] || die "前の作業フォルダの HEAD が動いた"
    [ "$(git -C "$WT_DIR" worktree list --porcelain | grep -c '^branch refs/heads/feat/wt$')" = 1 ] \
        || die "feat/wt を開いている作業フォルダが1つでない"
    [ "$(cur_branch "$WT2_DIR")" = feat/wt ] || die "いまの作業フォルダが feat/wt を開いていない"
}

t_takeover_keeps_newer_main() {
    local new_main
    # 新しい main: seed.txt を直し、newmain.txt を足す
    printf 'seed-new\n' >"$MAIN_DIR/seed.txt"
    echo newmain >"$MAIN_DIR/newmain.txt"
    git -C "$MAIN_DIR" add -A
    git -C "$MAIN_DIR" "${GITC[@]}" commit -q -m newmain
    new_main=$(git -C "$MAIN_DIR" rev-parse HEAD)
    # いまの作業フォルダ(WT)は新しい main から切ったブランチ、前の作業フォルダ(WT2)は古い main のまま。
    # Issueの記録は無い(移行の前からある作りかけ)
    git -C "$WT_DIR" reset -q --hard "$new_main"
    put_spec "$WT2_DIR" beta 42
    ss "$WT_DIR" takeover 42 --from "$WT2" --session s-me >/dev/null || die "takeover の終了コード $?"
    [ "$(cur_branch "$WT_DIR")" = feat/wt ] || die "いまのブランチが変わった: $(cur_branch "$WT_DIR")"
    [ "$(cat "$WT_DIR/seed.txt")" = seed-new ] || die "新しい main の seed.txt の直しが取り消された: $(cat "$WT_DIR/seed.txt")"
    [ -f "$WT_DIR/newmain.txt" ] || die "新しい main の newmain.txt が消された"
    cmp -s "$WT2_DIR/.kiro/specs/beta/spec.json" "$WT_DIR/.kiro/specs/beta/spec.json" || die "spec が写っていない"
    [ "$(git -C "$WT_DIR" status --porcelain --untracked-files=all | sed 's/^...//')" = .kiro/specs/beta/spec.json ] \
        || die "spec のほかの変更が入った: $(wt_status "$WT_DIR")"
    # 前の作業フォルダはIssueのブランチを開いていないので、ブランチも中身もそのまま
    [ "$(cur_branch "$WT2_DIR")" = feat/wt2 ] || die "前の作業フォルダのブランチが変わった"
    [ -f "$WT2_DIR/.kiro/specs/beta/spec.json" ] || die "前の作業フォルダの spec が消えた"
    # Issueの記録が無ければ作る(branch は空)
    [ "$(issue_fields 42)" = "42|$WT||s-me|$WT2" ] || die "作ったIssueの記録が違う: $(cat "$STATE/issues/42.json")"
}

t_takeover_not_ancestor() {
    local err rc wt2_head
    # 前の作業フォルダ(WT2)のブランチに、いまの作業フォルダ(WT)に無いコミットがある
    echo only >"$WT2_DIR/wt2-only.txt"
    git -C "$WT2_DIR" add -A
    git -C "$WT2_DIR" "${GITC[@]}" commit -q -m wt2-only
    wt2_head=$(git -C "$WT2_DIR" rev-parse HEAD)
    put_spec "$WT2_DIR" beta 42
    err=$(ss "$WT_DIR" takeover 42 --from "$WT2" --session s-me 2>&1 >/dev/null)
    rc=$?
    [ "$rc" = 1 ] || die "終了コードが1でない: $rc: $err"
    [ -z "$(wt_status "$WT_DIR")" ] || die "何かを写した: $(wt_status "$WT_DIR")"
    [ "$(cur_branch "$WT_DIR")" = feat/wt ] || die "いまのブランチが変わった"
    [ "$(cur_branch "$WT2_DIR")" = feat/wt2 ] || die "前の作業フォルダのブランチが変わった"
    [ -f "$WT2_DIR/.kiro/specs/beta/spec.json" ] || die "前の作業フォルダの spec が消えた"
    [ ! -f "$STATE/issues/42.json" ] || die "止まったのにIssueの記録を書いた"
    # 次の手: いまの作業フォルダのブランチに前の HEAD を取り込んでから、もう一度 /start を打つ
    printf '%s' "$err" | grep -q "含まれていない" || die "土台が含まれていないことを出さない: $err"
    printf '%s' "$err" | grep -q "取り込んでから" || die "次の手(取り込む)を出さない: $err"
    printf '%s' "$err" | grep -qF "/start" || die "次の手(/start)を出さない: $err"
    printf '%s' "$err" | grep -qF "$wt2_head" || die "前の作業フォルダの HEAD を出さない: $err"
}

# shellcheck disable=SC2016 # $d などは pj に渡す perl の式の変数で、シェルの変数ではない
t_takeover_from_self() {
    local out before
    put_session s-old "$WT" "$(fkey "$WT_DIR")" 100
    put_issue 42 "$WT" feat/wt s-old
    put_spec "$WT_DIR" beta 42
    echo change >"$WT_DIR/work.txt"
    before=$(wt_status "$WT_DIR")
    out=$(ss "$WT_DIR" takeover 42 --from "$WT" --session s-new) || die "takeover の終了コード $?: $out"
    [ "$(wt_status "$WT_DIR")" = "$before" ] || die "作りかけが変わった: $(wt_status "$WT_DIR")"
    [ "$(cur_branch "$WT_DIR")" = feat/wt ] || die "ブランチが変わった"
    [ "$(issue_fields 42)" = "42|$WT|feat/wt|s-new|" ] || die "Issueの記録が session_id だけの書き換えでない: $(cat "$STATE/issues/42.json")"
    [ "$(pj "$(cat "$STATE/issues/42.json")" '$d->{updated_at}')" != 1 ] || die "updated_at が書き直されていない"
    printf '%s' "$out" | grep -qF .kiro/specs/beta || die "作りかけの一覧に spec が無い: $out"
    printf '%s' "$out" | grep -qF work.txt || die "作りかけの一覧に work.txt が無い: $out"
    printf '%s' "$out" | grep -q "いまのブランチ: feat/wt\$" || die "いまのブランチが出ない: $out"
    out=$(check_start "$WT_DIR" check-start 42 --session s-new) || die "$out"
    [ "$(pj "$out" '$d->{leftovers}')" = '[]' ] || die "引き継いだ作りかけが leftovers に出た: $out"
    # Issueの記録のブランチがいまのブランチでなければ、コミットしていない変更を持ったまま切り替える
    git -C "$MAIN_DIR" branch -q feat/extra "$SEED_SHA"
    put_issue 43 "$WT" feat/extra s-old
    ss "$WT_DIR" takeover 43 --from "$WT_DIR" --session s-new >/dev/null || die "ブランチの違う takeover の終了コード $?"
    [ "$(cur_branch "$WT_DIR")" = feat/extra ] || die "Issueの記録のブランチに切り替わっていない: $(cur_branch "$WT_DIR")"
    [ "$(wt_status "$WT_DIR")" = "$before" ] || die "切り替えで作りかけが変わった: $(wt_status "$WT_DIR")"
}

t_takeover_branch_remote() {
    local remote_sha rc
    # リモートにだけ feat/extra がある(リモートのブランチの記録もまだ無い)
    git init -q --bare "$ORIGIN_DIR"
    git -C "$MAIN_DIR" remote add origin "$ORIGIN_DIR"
    remote_sha=$(git -C "$MAIN_DIR" "${GITC[@]}" commit-tree -p "$SEED_SHA" -m remote "$SEED_SHA^{tree}")
    git -C "$MAIN_DIR" push -q "$ORIGIN_DIR" "$remote_sha:refs/heads/feat/extra" || die "リモートに push できない"
    ! git -C "$MAIN_DIR" show-ref --quiet feat/extra || die "前提: ローカルに feat/extra の記録がある"
    put_issue 42 "" feat/extra ""
    # いまの作業フォルダがきれいでなければ、何もせずに終了コード1
    echo dirty >"$WT2_DIR/dirty.txt"
    ss "$WT2_DIR" takeover 42 --branch feat/extra --session s-me >/dev/null 2>&1
    rc=$?
    [ "$rc" = 1 ] || die "きれいでないときの終了コードが1でない: $rc"
    [ "$(cur_branch "$WT2_DIR")" = feat/wt2 ] || die "きれいでないのに切り替えた"
    ! git -C "$MAIN_DIR" show-ref --verify --quiet refs/heads/feat/extra || die "きれいでないのにブランチを作った"
    rm -f "$WT2_DIR/dirty.txt"
    # リモートから取得して切り替える
    ss "$WT2_DIR" takeover 42 --branch feat/extra --session s-me >/dev/null || die "takeover の終了コード $?"
    [ "$(cur_branch "$WT2_DIR")" = feat/extra ] || die "feat/extra に切り替わっていない: $(cur_branch "$WT2_DIR")"
    [ "$(git -C "$WT2_DIR" rev-parse HEAD)" = "$remote_sha" ] || die "リモートのブランチのコミットでない"
    [ "$(git -C "$WT2_DIR" rev-parse --abbrev-ref 'feat/extra@{upstream}')" = origin/feat/extra ] || die "リモートのブランチを追っていない"
    [ "$(issue_fields 42)" = "42|$WT2|feat/extra|s-me|" ] || die "Issueの記録が違う: $(cat "$STATE/issues/42.json")"
    # ローカルにあるブランチには、そのまま切り替える
    git -C "$MAIN_DIR" branch -q feat/extra2 "$SEED_SHA"
    put_issue 43 "" feat/extra2 ""
    ss "$MAIN_DIR" takeover 43 --branch feat/extra2 --session s-x >/dev/null || die "ローカルのブランチの takeover の終了コード $?"
    [ "$(cur_branch "$MAIN_DIR")" = feat/extra2 ] || die "ローカルの feat/extra2 に切り替わっていない"
}

# shellcheck disable=SC2016 # $d などは pj に渡す perl の式の変数で、シェルの変数ではない
t_takeover_then_check_start() {
    local out
    make_wt_leftover
    put_session s-me "$WT2" "$(fkey "$WT2_DIR")" 200
    ss "$WT2_DIR" takeover 42 --from "$WT" --session s-me >/dev/null || die "takeover の終了コード $?"
    out=$(check_start "$WT2_DIR" check-start 42 --session s-me) || die "$out"
    [ "$(pj "$out" '$d->{leftovers}')" = '[]' ] || die "引き継いだあとに前の worktree か自分の作りかけが出た: $out"
    [ "$(pj "$out" '$d->{branch_only}')" = '[]' ] || die "引き継いだブランチが branch_only に出た: $out"
    # さらに別のセッションから見ると、引き継いだセッションの作業フォルダだけが出る
    out=$(check_start "$MAIN_DIR" check-start 42 --session s-x) || die "$out"
    [ "$(pj "$out" 'join ",", map { $_->{folder} } @{$d->{leftovers}}')" = "$WT2" ] || die "引き継いだ作業フォルダだけが出ていない: $out"
    [ "$(pj "$out" '$d->{leftovers}[0]{active_session}{session_id}')" = s-me ] || die "引き継いだセッションが active_session に出ない: $out"
}

# shellcheck disable=SC2016 # $d などは pj に渡す perl の式の変数で、シェルの変数ではない
t_takeover_back_unhides_receiver() {
    local out
    make_wt_leftover
    # 前に WT2 から WT へ引き継いでいた(WT2 が handed_over_from に入っている)
    put_issue 42 "$WT" feat/wt s-wt "[\"$WT2\"]"
    ss "$WT2_DIR" takeover 42 --from "$WT" --session s-me >/dev/null || die "takeover の終了コード $?"
    [ "$(issue_fields 42)" = "42|$WT2|feat/wt|s-me|$WT" ] || die "引き継いだ先が handed_over_from から外れていない: $(cat "$STATE/issues/42.json")"
    out=$(check_start "$MAIN_DIR" check-start 42 --session s-x) || die "$out"
    [ "$(pj "$out" 'join ",", map { $_->{folder} } @{$d->{leftovers}}')" = "$WT2" ] || die "引き継いだ先の作りかけが隠れた: $out"
}

t_takeover_apply_conflict_restores() {
    local err rc
    # いまの作業フォルダ(WT)は seed.txt を直したコミットを持ち、前の作業フォルダ(WT2)は同じ行を別に直している
    printf 'seed-wt\n' >"$WT_DIR/seed.txt"
    git -C "$WT_DIR" add -A
    git -C "$WT_DIR" "${GITC[@]}" commit -q -m seed-wt
    printf 'seed-wt2\n' >"$WT2_DIR/seed.txt"
    put_spec "$WT2_DIR" beta 42
    err=$(ss "$WT_DIR" takeover 42 --from "$WT2" --session s-me 2>&1 >/dev/null)
    rc=$?
    [ "$rc" = 1 ] || die "終了コードが1でない: $rc: $err"
    [ -z "$(wt_status "$WT_DIR")" ] || die "いまの作業フォルダが元に戻っていない: $(wt_status "$WT_DIR")"
    [ "$(cat "$WT_DIR/seed.txt")" = seed-wt ] || die "いまの作業フォルダの seed.txt が戻っていない"
    [ ! -e "$WT_DIR/.kiro/specs/beta" ] || die "写したファイルが消えていない"
    [ "$(cur_branch "$WT_DIR")" = feat/wt ] || die "いまのブランチが変わった"
    [ "$(cat "$WT2_DIR/seed.txt")" = seed-wt2 ] || die "前の作業フォルダの seed.txt が変わった"
    [ -f "$WT2_DIR/.kiro/specs/beta/spec.json" ] || die "前の作業フォルダの spec が消えた"
    [ ! -f "$STATE/issues/42.json" ] || die "失敗したのにIssueの記録を書いた"
}

t_takeover_apply_failure_reopens_branch() {
    local real_git rc
    make_wt_leftover
    real_git=$(command -v git)
    mkdir -p "$TMP_ROOT/gitapplyfail"
    # apply だけが失敗する git
    cat >"$TMP_ROOT/gitapplyfail/git" <<EOF
#!/bin/bash
case " \$* " in *" apply "*) echo "error: patch failed" >&2; exit 1 ;; esac
exec "$real_git" "\$@"
EOF
    chmod +x "$TMP_ROOT/gitapplyfail/git"
    (PATH="$TMP_ROOT/gitapplyfail:$PATH" ss "$WT2_DIR" takeover 42 --from "$WT" --session s-me >/dev/null 2>&1)
    rc=$?
    [ "$rc" = 1 ] || die "終了コードが1でない: $rc"
    [ "$(cur_branch "$WT2_DIR")" = feat/wt2 ] || die "いまの作業フォルダが前のブランチに戻っていない: $(cur_branch "$WT2_DIR")"
    [ -z "$(wt_status "$WT2_DIR")" ] || die "いまの作業フォルダに写したものが残っている: $(wt_status "$WT2_DIR")"
    [ "$(cur_branch "$WT_DIR")" = feat/wt ] || die "前の作業フォルダがブランチを開き直していない"
    [ -f "$WT_DIR/.kiro/specs/beta/spec.json" ] || die "前の作業フォルダの spec が消えた"
    [ "$(issue_fields 42)" = "42|$WT|feat/wt|s-wt|" ] || die "失敗したのにIssueの記録を書き直した: $(cat "$STATE/issues/42.json")"
}

t_takeover_dirty_refused() {
    local rc exclude
    make_wt_leftover
    # 無視されているファイルは、きれいさの確かめに数えない
    exclude="$(git -C "$MAIN_DIR" rev-parse --path-format=absolute --git-common-dir)/info/exclude"
    mkdir -p "${exclude%/*}"
    echo ignored.txt >>"$exclude"
    echo x >"$WT2_DIR/ignored.txt"
    echo x >"$WT2_DIR/untracked.txt"
    ss "$WT2_DIR" takeover 42 --from "$WT" --session s-me >/dev/null 2>&1
    rc=$?
    [ "$rc" = 1 ] || die "git の管理外のファイルがあるときの終了コードが1でない: $rc"
    [ "$(cur_branch "$WT_DIR")" = feat/wt ] || die "止まったのに前の作業フォルダのブランチを手放させた"
    [ "$(cur_branch "$WT2_DIR")" = feat/wt2 ] || die "止まったのに切り替えた"
    [ "$(issue_fields 42)" = "42|$WT|feat/wt|s-wt|" ] || die "止まったのにIssueの記録を書き直した"
    rm -f "$WT2_DIR/untracked.txt"
    ss "$WT2_DIR" takeover 42 --from "$WT" --session s-me >/dev/null || die "無視されているファイルだけのときに止まった: $?"
    rm -f "$WT2_DIR/ignored.txt"
}

t_takeover_usage() {
    local rc
    put_issue 42 "$WT" feat/wt s-wt
    for args in "takeover 42" "takeover 42 --from $WT --branch feat/wt" "takeover --from $WT" \
        "takeover 42 --from $WORK/NoSuchFolder" "takeover 42 --branch"; do
        # shellcheck disable=SC2086
        ss "$WT2_DIR" $args >/dev/null 2>&1
        rc=$?
        [ "$rc" = 64 ] || die "'$args' の終了コードが64でない: $rc"
    done
    [ "$(cur_branch "$WT2_DIR")" = feat/wt2 ] || die "誤った呼び方で切り替えた"
    [ "$(issue_fields 42)" = "42|$WT|feat/wt|s-wt|" ] || die "誤った呼び方でIssueの記録を書き直した"
}

echo "--- check-start: 同じ作業フォルダの別のセッション(要件5.1・5.2)"
run_test "同じ作業フォルダに別の作業中のセッションの記録があると folder_conflict に出る" t_folder_conflict
run_test "同じ作業フォルダの、Issueの記録の無いセッション(着手していない記録)は folder_conflict に出ない" t_folder_conflict_idle_ignored
run_test "--session が無いときは、いまの作業フォルダのいちばん古い記録を自分として除く" t_folder_conflict_without_session
run_test "end のあとの check-start では folder_conflict が空になる" t_end_clears_conflict
run_test "end はパスを含むIDを受け付けない" t_end_rejects_path

echo "--- check-start: Issueの作りかけ(要件4.1・4.2)"
run_test "別の worktree のコミットしていない spec が leftovers に出て、セッションの記録の有無が active_session に出る" t_leftover_other_worktree_spec
run_test "コミット済みの spec は leftovers に出ない" t_leftover_committed_spec_ignored
run_test "additional_issues に N を含む spec も leftovers に出る" t_leftover_additional_issue
run_test "いまの作業フォルダの作りかけは is_self が真で出る" t_leftover_self
run_test "自分が claim した作りかけは leftovers に出ない" t_leftover_own_claim_excluded
run_test "spec の無いIssueもIssueの記録のブランチで見つかる" t_leftover_branch_without_spec
run_test "handed_over_from の作業フォルダは leftovers に出ない" t_leftover_handed_over_excluded
run_test "どこでも開かれていないIssueのブランチが branch_only に出る" t_branch_only

echo "--- check-start: 作業中のセッションの数(要件3.6)"
run_test "capacity に自分以外の作業中のセッションが出る" t_capacity

echo "--- claim・spec-names"
run_test "claim がIssueの記録を書き、すでにあれば書き直す" t_claim
run_test "claim は誤った呼び方で記録を書かない" t_claim_usage
run_test "spec-names がほかの worktree の spec の名前も出す" t_spec_names
run_test "check-start・claim・spec-names は docker を呼ばない" t_no_docker_in_check_start

echo "--- prune(要件4.5)"
run_test "prune は、作業フォルダが残っている記録を変えず、片付けるものが無ければ docker を呼ばない" t_prune_callable
run_test "worktree を git worktree remove で消したあとも、ブランチが残っていれば issues の記録が folder を空にして残り、check-start の branch_only に出る" t_prune_branch_kept
run_test "ブランチも消したあとは記録が消える" t_prune_branch_gone
run_test "ディレクトリだけを消した worktree は git worktree prune で外れ、そのブランチに git switch できる" t_prune_worktree_prune
run_test "消えた作業フォルダのセッションの記録が消え、残っている作業フォルダの記録は残る" t_prune_sessions
run_test "消えた作業フォルダの鍵のボリュームと DB が消え、残っている作業フォルダのものは消えない" t_prune_volumes_and_db
run_test "db が動いていなければ DB の片付けを飛ばしてボリュームは消し、記録は残す" t_prune_db_not_running
run_test "Docker につながらなければボリュームも DB も消さず、鍵と名前を標準エラーに出し、記録は残す" t_prune_docker_unreachable
run_test "使用中で消せなかったボリュームを名前つきで標準エラーに出し、消せたものだけを消したと出す" t_prune_volume_failures_reported
run_test "取り戻しの条件に当たる残った枠を取り戻し、ui のコンテナを消してからボリュームを消す" t_prune_slots
run_test "check-start は最初に prune を行い、手で打った prune は片付けたことを出す" t_prune_quiet_in_check_start
run_test "作業フォルダの一覧を取れないときは、記録もボリュームも消さない" t_prune_skips_without_worktree_list
run_test "Docker につながらないときは記録が書き換わらずに残って名前が標準エラーに出て、Docker が戻ってから打ち直すとボリュームと DB を消して記録が片付く" t_prune_retry_after_docker_back
run_test "消せなかった作業フォルダのセッションの記録は残り、check-start の capacity.active に出ない" t_prune_kept_not_active
run_test "Docker につながらず記録が残っているときも、ブランチは check-start の branch_only に出る" t_prune_branch_only_while_kept
run_test "記録が残っていても、prune は無くなった作業フォルダのラベルのコンテナを消し、その鍵の枠を取り戻す" t_prune_frees_slots_while_kept
run_test "Docker につながらないときと docker rm -f でコンテナを消せないときは、無くなった作業フォルダの鍵の枠を取り戻さない" t_prune_unreachable_keeps_slots
run_test "記録が残っているときに check-start を呼ぶと、標準エラーに消せなかった名前が出て、標準出力の JSON は正しく読める" t_check_start_reports_kept

echo "--- takeover(要件1.1・1.2・4.3〜4.6)"
run_test "別の worktree のコミットしていない spec とブランチが写り、前の worktree の中身は消えない" t_takeover_copies_from_other_worktree
run_test "前の worktree はブランチを手放して detached になる" t_takeover_releases_branch
run_test "古い main にいた前の作業フォルダからの引き継ぎで、新しい main のコミットが取り消されない" t_takeover_keeps_newer_main
run_test "前の HEAD がいまの HEAD の先祖でなければ、何も写さずに終了コード1で止まり、次の手を出す" t_takeover_not_ancestor
run_test "--from がいまの作業フォルダのとき、作りかけが残ったまま記録の session_id だけが書き換わる" t_takeover_from_self
run_test "--branch でリモートにだけあるブランチを取得して切り替える" t_takeover_branch_remote
run_test "引き継いだあとの check-start は前の worktree も自分の作りかけも出さない" t_takeover_then_check_start
run_test "引き継ぎを戻したときは、引き継いだ先の作業フォルダが handed_over_from から外れる" t_takeover_back_unhides_receiver
run_test "写しが食い違って git apply が失敗したら、いまの作業フォルダを元に戻して終了コード1で終わる" t_takeover_apply_conflict_restores
run_test "git apply が失敗したら、前の作業フォルダにブランチを開き直させる" t_takeover_apply_failure_reopens_branch
run_test "いまの作業フォルダに無視されていない git の管理外のファイルがあれば、何もせずに終了コード1で終わる" t_takeover_dirty_refused
run_test "takeover は誤った呼び方で何も変えない" t_takeover_usage

echo
echo "結果: 成功 $pass / 失敗 $fail"
[ "$fail" -eq 0 ]
