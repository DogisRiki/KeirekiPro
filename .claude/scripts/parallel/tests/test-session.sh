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
put_session() { # <session_id> <folder> <folder_key> <started_at> [<responding: true(既定)|false|none(欄が無い)>]
    local responding="${5:-true}" field=""
    [ "$responding" = none ] || field=",\"responding\":$responding"
    mkdir -p "$STATE/sessions"
    printf '{"folder":"%s","folder_key":"%s","last_seen":%s%s,"session_id":"%s","started_at":%s}\n' \
        "$2" "$3" "$(($4 + 5))" "$field" "$1" "$4" >"$STATE/sessions/$1.json"
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
    # check-spec のテストで置いた差分の設定を外す
    git -C "$MAIN_DIR" config --unset diff.interHunkContext 2>/dev/null
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
    # コミットしていない spec は、コミットしていない変更でもある。s-me の記録は着手の記録なので started も付く
    [ "$(pj "$out" 'join ",", @{$d->{leftovers}[0]{kinds}}')" = started,spec,changes,branch ] || die "kinds が started,spec,changes,branch でない: $out"
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

# shellcheck disable=SC2016 # $d などは pj に渡す perl の式の変数で、シェルの変数ではない
t_capacity_only_responding() {
    local out
    put_session s-me "$MAIN" "$(fkey "$MAIN_DIR")" 100
    # 返答を終えて入力を待っているセッションと、印の欄が無い記録(印を付ける前からのセッション)
    put_session s-wt "$WT" "$(fkey "$WT_DIR")" 200 false
    put_issue 50 "$WT" feat/wt s-wt
    put_session s-wt2 "$WT2" "$(fkey "$WT2_DIR")" 300 none
    put_issue 52 "$WT2" feat/wt2 s-wt2
    out=$(check_start "$MAIN_DIR" check-start 42 --session s-me) || die "$out"
    [ "$(pj "$out" '$d->{capacity}{active}')" = '[]' ] || die "返答していないセッションが active に出た: $out"
    # 返答を始めたセッションだけが出る
    put_session s-wt "$WT" "$(fkey "$WT_DIR")" 200 true
    out=$(check_start "$MAIN_DIR" check-start 42 --session s-me) || die "$out"
    [ "$(pj "$out" 'join ",", map { $_->{issue} } @{$d->{capacity}{active}}')" = 50 ] \
        || die "返答しているセッションだけが active に出ない: $out"
}

# shellcheck disable=SC2016 # $d などは pj に渡す perl の式の変数で、シェルの変数ではない
t_conflict_and_leftover_ignore_responding() {
    local out
    # 返答を終えたセッションも、同じ作業フォルダの確認と作りかけの確認では作業中に数える(#520 のやらないこと)
    put_session s-old "$MAIN" "$(fkey "$MAIN_DIR")" 100 false
    put_issue 77 "$MAIN" main s-old
    put_session s-me "$MAIN" "$(fkey "$MAIN_DIR")" 200
    put_spec "$WT_DIR" beta 42
    put_session s-wt "$WT" "$(fkey "$WT_DIR")" 50 none
    put_issue 78 "$WT" feat/wt s-wt
    out=$(check_start "$MAIN_DIR" check-start 42 --session s-me) || die "$out"
    [ "$(pj "$out" 'join ",", map { $_->{session_id} } @{$d->{folder_conflict}}')" = s-old ] \
        || die "返答を終えたセッションが folder_conflict に出ない: $out"
    [ "$(pj "$out" '$d->{leftovers}[0]{active_session}{session_id}')" = s-wt ] \
        || die "印の欄が無いセッションが leftovers の active_session に出ない: $out"
    [ "$(pj "$out" '$d->{capacity}{active}')" = '[]' ] || die "返答していないセッションが active に出た: $out"
}

# =====================================================================
# claim
# =====================================================================
# shellcheck disable=SC2016 # $d などは pj に渡す perl の式の変数で、シェルの変数ではない
t_claim() {
    local f got before rc
    put_session s-me "$WT" "$(fkey "$WT_DIR")" 100
    ss "$WT_DIR" claim 42 --branch feat/wt --session s-me || die "claim の終了コード $?"
    f="$STATE/issues/42.json"
    [ -f "$f" ] || die "issues/42.json が無い"
    got=$(pj "$(cat "$f")" 'join "|", $d->{issue}, $d->{folder}, $d->{branch}, $d->{session_id}, scalar @{$d->{handed_over_from}}')
    [ "$got" = "42|$WT|feat/wt|s-me|0" ] || die "記録の中身が違う: $(cat "$f")"
    case "$(pj "$(cat "$f")" '$d->{updated_at}')" in '' | *[!0-9]*) die "updated_at が UNIX 秒でない: $(cat "$f")" ;; esac
    # folder と session_id が空の記録(prune が残した記録)なら、folder branch session_id updated_at を書き直し、
    # handed_over_from は残す
    put_issue 42 "" feat/old "" "[\"$WT2\"]"
    ss "$MAIN_DIR" claim 42 --branch main --session s-new || die "2回目の claim の終了コード $?"
    got=$(pj "$(cat "$f")" 'join "|", $d->{issue}, $d->{folder}, $d->{branch}, $d->{session_id}, @{$d->{handed_over_from}}')
    [ "$got" = "42|$MAIN|main|s-new|$WT2" ] || die "書き直した記録が違う: $(cat "$f")"
    [ "$(pj "$(cat "$f")" '$d->{updated_at}')" != 1 ] || die "updated_at が書き直されていない"
    # ほかの作業フォルダとセッションの記録なら、書き直さずに終了コード1で断る
    put_issue 42 "$WT2" feat/old s-old "[\"$WT2\"]"
    before=$(cat "$f")
    ss "$MAIN_DIR" claim 42 --branch main --session s-new >/dev/null 2>&1
    rc=$?
    [ "$rc" = 1 ] || die "ほかの作業フォルダとセッションの記録への claim の終了コードが1でない: $rc"
    [ "$(cat "$f")" = "$before" ] || die "ほかの作業フォルダとセッションの記録を書き直した: $(cat "$f")"
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
    ss "$MAIN_DIR" prune >/dev/null || die "prune の終了コード $?"
    [ ! -f "$STATE/issues/42.json" ] || die "ブランチも消したのに issues/42.json が残っている: $(cat "$STATE/issues/42.json")"
    # check-start は、何も見つからなければこのセッションの予約(branch が空)を書く
    out=$(check_start "$MAIN_DIR" check-start 42 --session s-me) || die "$out"
    [ "$(pj "$out" '$d->{branch_only}')" = '[]' ] || die "消したブランチが branch_only に出た: $out"
    [ "$(pj "$(cat "$STATE/issues/42.json")" 'join "|", $d->{issue}, $d->{folder}, $d->{branch}, $d->{session_id}')" = "42|$MAIN||s-me" ] \
        || die "check-start のあとの記録がこのセッションの予約でない: $(cat "$STATE/issues/42.json")"
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
# 記録の錠(session-overlap-guard 要件3.1)
# =====================================================================
LOCK="$STATE/records.lock"

# sleep を待たずに終える偽物(錠を待つ150回の試しを、待ち時間なしで流す)
mkdir -p "$TMP_ROOT/fastsleep"
printf '#!/bin/bash\nexit 0\n' >"$TMP_ROOT/fastsleep/sleep"
chmod +x "$TMP_ROOT/fastsleep/sleep"

t_lock_held_refused() {
    local out err rc start
    put_spec "$WT_DIR" beta 42
    # ほかのセッションが持っている錠(60秒より新しい)
    mkdir -p "$LOCK"
    start=$SECONDS
    out=$(PATH="$TMP_ROOT/fastsleep:$PATH" ss "$MAIN_DIR" check-start 42 --session s-me 2>"$WORK/err.txt")
    rc=$?
    err=$(cat "$WORK/err.txt")
    [ "$rc" = 69 ] || die "錠がほかに持たれたままなのに終了コードが69でない: $rc: $out $err"
    [ -z "$out" ] || die "錠を取れないのに JSON を出した: $out"
    case "$err" in *'[parallel]'*records.lock*) ;; *) die "標準エラーに [parallel] で始まる錠の理由が無い: $err" ;; esac
    [ -d "$LOCK" ] || die "ほかのセッションの錠を消した"
    [ ! -f "$STATE/issues/42.json" ] || die "錠を取れないのに着手の予約を書いた: $(cat "$STATE/issues/42.json")"
    [ $((SECONDS - start)) -le 20 ] || die "錠を待つのに20秒より長くかかった: $((SECONDS - start))秒"
}

t_lock_stale_broken() {
    local out
    # 60秒より古い錠は、持ち主が落ちて残ったものとみなして壊し、取り直す
    mkdir -p "$LOCK"
    perl -e 'my $t = time - 120; utime $t, $t, $ARGV[0] or die "utime: $!\n"' "$LOCK" || die "錠の時刻を古くできない"
    out=$(check_start "$MAIN_DIR" check-start 42 --session s-me) || die "古い錠があると check-start が成り立たない: $out"
    [ ! -e "$LOCK" ] || die "check-start が錠を返していない"
    # 錠が無いときも、終わったあとに錠を残さない
    out=$(check_start "$WT_DIR" check-start 42 --session s-me) || die "$out"
    [ ! -e "$LOCK" ] || die "check-start が錠を返していない(錠が無かったとき)"
}

t_lock_released_on_failure() {
    local real_perl out rc
    real_perl=$(command -v perl)
    mkdir -p "$TMP_ROOT/perlfail"
    # check-start の調べの perl(folder_conflict を出すもの)だけが失敗する perl
    cat >"$TMP_ROOT/perlfail/perl" <<EOF
#!/bin/bash
case "\$*" in *folder_conflict*) echo "fake perl failure" >&2; exit 1 ;; esac
exec "$real_perl" "\$@"
EOF
    chmod +x "$TMP_ROOT/perlfail/perl"
    out=$(PATH="$TMP_ROOT/perlfail:$PATH" ss "$MAIN_DIR" check-start 42 --session s-me 2>/dev/null)
    rc=$?
    [ "$rc" = 69 ] || die "調べが失敗したのに終了コードが69でない: $rc: $out"
    [ -z "$out" ] || die "調べが失敗したのに JSON を出した: $out"
    [ ! -e "$LOCK" ] || die "調べが失敗したときに錠を残した"
}

# =====================================================================
# check-start の着手の予約(session-overlap-guard 要件1・要件3.1)
# =====================================================================
# Issueの記録の updated_at を書き換える(打ち直しで updated_at が変わることを確かめるため)
# shellcheck disable=SC2016 # perl のコードなので、$ を展開しない
set_updated_at() { # <N> <UNIX 秒>
    perl -MJSON::PP -e '
        my ($file, $at) = @ARGV;
        my $j = JSON::PP->new->utf8->canonical;
        open my $in, "<:raw", $file or die "$file: $!\n";
        my $d = do { local $/; $j->decode(<$in>) };
        close $in;
        $d->{updated_at} = 0 + $at;
        open my $out, ">:raw", $file or die "$file: $!\n";
        print $out $j->encode($d), "\n";
        close $out or die "$file: $!\n";
    ' -- "$STATE/issues/$1.json" "$2" || die "updated_at を書き換えられない"
}

# shellcheck disable=SC2016 # $d などは pj に渡す perl の式の変数で、シェルの変数ではない
t_reserve_when_nothing_found() {
    local out f
    put_session s-me "$WT" "$(fkey "$WT_DIR")" 100
    out=$(check_start "$WT_DIR" check-start 42 --session s-me) || die "$out"
    [ "$(pj "$out" '$d->{leftovers}')" = '[]' ] || die "前提: leftovers が空でない: $out"
    f="$STATE/issues/42.json"
    [ -f "$f" ] || die "何も見つからないのに着手の予約を書いていない"
    [ "$(issue_fields 42)" = "42|$WT||s-me|" ] || die "予約の中身が違う: $(cat "$f")"
    [ "$(pj "$(cat "$f")" 'ref $d->{handed_over_from}')" = ARRAY ] || die "handed_over_from が配列でない: $(cat "$f")"
    case "$(pj "$(cat "$f")" '$d->{updated_at}')" in '' | *[!0-9]*) die "updated_at が UNIX 秒でない: $(cat "$f")" ;; esac
    [ ! -e "$LOCK" ] || die "予約を書いたあとに錠を残した"
}

# shellcheck disable=SC2016 # $d などは pj に渡す perl の式の変数で、シェルの変数ではない
t_reserve_other_session_started() {
    local out before
    # WT のセッション s-wt が、ブランチを作る前に予約を書いた(branch が空)
    put_session s-wt "$WT" "$(fkey "$WT_DIR")" 300
    put_issue 42 "$WT" "" s-wt
    before=$(cat "$STATE/issues/42.json")
    out=$(check_start "$WT2_DIR" check-start 42 --session s-me) || die "$out"
    [ "$(pj "$out" 'scalar @{$d->{leftovers}}')" = 1 ] || die "leftovers の数が1でない: $out"
    [ "$(pj "$out" '$d->{leftovers}[0]{folder}')" = "$WT" ] || die "folder が予約した作業フォルダでない: $out"
    [ "$(pj "$out" '$d->{leftovers}[0]{kinds}')" = '["started"]' ] || die "kinds が started だけでない: $out"
    [ "$(pj "$out" '$d->{leftovers}[0]{is_self}')" = false ] || die "is_self が偽でない: $out"
    [ "$(pj "$out" '$d->{leftovers}[0]{active_session}')" = '{"last_seen":305,"session_id":"s-wt","started_at":300}' ] \
        || die "active_session が予約したセッションでない: $out"
    [ "$(cat "$STATE/issues/42.json")" = "$before" ] || die "ほかのセッションの予約を書き換えた: $(cat "$STATE/issues/42.json")"
    # ほかの種類もある作業フォルダでは、started が先頭に並ぶ
    put_spec "$WT_DIR" beta 42
    out=$(check_start "$WT2_DIR" check-start 42 --session s-me) || die "$out"
    [ "$(pj "$out" 'join ",", @{$d->{leftovers}[0]{kinds}}')" = started,spec ] || die "kinds が started,spec でない: $out"
    [ "$(cat "$STATE/issues/42.json")" = "$before" ] || die "ほかのセッションの予約を書き換えた: $(cat "$STATE/issues/42.json")"
}

# shellcheck disable=SC2016 # $d などは pj に渡す perl の式の変数で、シェルの変数ではない
t_reserve_closed_session_rewritten() {
    local out
    # 予約したセッション s-closed の記録が無い(所有者が閉じた)。handed_over_from は残す
    put_issue 42 "$WT" "" s-closed "[\"$WORK/RepoOld\"]"
    out=$(check_start "$WT2_DIR" check-start 42 --session s-me) || die "$out"
    [ "$(pj "$out" '$d->{leftovers}')" = '[]' ] || die "閉じたセッションの予約が leftovers に出た: $out"
    [ "$(issue_fields 42)" = "42|$WT2||s-me|$WORK/RepoOld" ] || die "予約がこのセッションのものに書き換わっていない: $(cat "$STATE/issues/42.json")"
    [ "$(pj "$(cat "$STATE/issues/42.json")" '$d->{updated_at}')" != 1 ] || die "updated_at が書き直されていない"
}

# shellcheck disable=SC2016 # $d などは pj に渡す perl の式の変数で、シェルの変数ではない
t_reserve_same_session_rerun() {
    local out before
    put_session s-me "$WT" "$(fkey "$WT_DIR")" 100
    out=$(check_start "$WT_DIR" check-start 42 --session s-me) || die "$out"
    set_updated_at 42 7
    before=$(issue_fields 42)
    out=$(check_start "$WT_DIR" check-start 42 --session s-me) || die "$out"
    [ "$(pj "$out" '$d->{leftovers}')" = '[]' ] || die "同じセッションの打ち直しで leftovers が出た: $out"
    [ "$(issue_fields 42)" = "$before" ] || die "打ち直しで updated_at のほかの欄が変わった: $(cat "$STATE/issues/42.json")"
    [ "$(pj "$(cat "$STATE/issues/42.json")" '$d->{updated_at}')" != 7 ] || die "打ち直しで updated_at が書き直されていない"
    # claim でブランチを書いたあとの打ち直しでも、ブランチを空にしない
    ss "$WT_DIR" claim 42 --branch feat/wt --session s-me || die "claim の終了コード $?"
    before=$(issue_fields 42)
    out=$(check_start "$WT_DIR" check-start 42 --session s-me) || die "$out"
    [ "$(pj "$out" '$d->{leftovers}')" = '[]' ] || die "claim のあとの打ち直しで leftovers が出た: $out"
    [ "$(issue_fields 42)" = "$before" ] || die "claim のあとの打ち直しで記録が変わった: $(cat "$STATE/issues/42.json")"
}

# shellcheck disable=SC2016 # $d などは pj に渡す perl の式の変数で、シェルの変数ではない
t_reserve_empty_session_id_not_started() {
    local out
    # 予約の session_id が空(セッションのIDが分からなかったセッションの予約)は started に数えない。
    # session_id が空のセッションの記録(sessions/.json)があっても、空のIDでは引かない
    put_session s-wt "$WT" "$(fkey "$WT_DIR")" 300
    put_session "" "$WT" "$(fkey "$WT_DIR")" 310
    put_issue 42 "$WT" "" ""
    out=$(check_start "$WT2_DIR" check-start 42 --session s-me) || die "$out"
    [ "$(pj "$out" '$d->{leftovers}')" = '[]' ] || die "session_id が空の予約が leftovers に出た: $out"
}

t_reserve_write_failure() {
    local real_perl out rc err
    real_perl=$(command -v perl)
    mkdir -p "$TMP_ROOT/writefail"
    # 記録を書く perl(lib.sh の kp_json_write)だけが失敗する perl
    cat >"$TMP_ROOT/writefail/perl" <<EOF
#!/bin/bash
case "\$*" in *kp_json_write*) echo "fake write failure" >&2; exit 1 ;; esac
exec "$real_perl" "\$@"
EOF
    chmod +x "$TMP_ROOT/writefail/perl"
    out=$(PATH="$TMP_ROOT/writefail:$PATH" ss "$WT_DIR" check-start 42 --session s-me 2>"$WORK/err.txt")
    rc=$?
    err=$(cat "$WORK/err.txt")
    [ "$rc" = 69 ] || die "予約を書けないのに終了コードが69でない: $rc: $out $err"
    [ -z "$out" ] || die "予約を書けないのに JSON を出した: $out"
    case "$err" in *'[parallel]'*) ;; *) die "標準エラーに [parallel] で始まる理由が無い: $err" ;; esac
    [ ! -e "$LOCK" ] || die "予約を書けなかったときに錠を残した"
    [ ! -f "$STATE/issues/42.json" ] || die "予約を書けなかったのに記録がある: $(cat "$STATE/issues/42.json")"
}

# 2つの worktree から別々のセッションで同時に check-start を呼び、片方だけが着手したことになるかを確かめる
# shellcheck disable=SC2016 # $d などは pj に渡す perl の式の変数で、シェルの変数ではない
concurrent_check_start_once() { # <回>
    local pa pb rca rcb outa outb win lose win_dir
    rm -f "$STATE/issues/42.json"
    ss "$WT_DIR" check-start 42 --session s-a >"$WORK/outa.txt" 2>"$WORK/erra.txt" &
    pa=$!
    ss "$WT2_DIR" check-start 42 --session s-b >"$WORK/outb.txt" 2>"$WORK/errb.txt" &
    pb=$!
    wait "$pa"
    rca=$?
    wait "$pb"
    rcb=$?
    outa=$(cat "$WORK/outa.txt")
    outb=$(cat "$WORK/outb.txt")
    [ "$rca" = 0 ] && [ "$rcb" = 0 ] || die "$1 回目: 終了コードが0でない: a=$rca b=$rcb $(cat "$WORK/erra.txt" "$WORK/errb.txt")"
    if [ "$(pj "$outa" '$d->{leftovers}')" = '[]' ]; then
        win=s-a lose=$outb win_dir=$WT
        [ "$(pj "$outb" '$d->{leftovers}')" != '[]' ] || die "$1 回目: 両方の leftovers が空: $outa / $outb"
    else
        win=s-b lose=$outa win_dir=$WT2
        [ "$(pj "$outb" '$d->{leftovers}')" = '[]' ] || die "$1 回目: どちらの leftovers も空でない: $outa / $outb"
    fi
    [ "$(pj "$lose" 'scalar @{$d->{leftovers}}')" = 1 ] || die "$1 回目: あとのほうの leftovers の数が1でない: $lose"
    [ "$(pj "$lose" '$d->{leftovers}[0]{kinds}')" = '["started"]' ] || die "$1 回目: あとのほうに started が出ない: $lose"
    [ "$(pj "$lose" '$d->{leftovers}[0]{folder}')" = "$win_dir" ] || die "$1 回目: started の folder が先のほうの作業フォルダでない: $lose"
    [ "$(pj "$lose" '$d->{leftovers}[0]{active_session}{session_id}')" = "$win" ] || die "$1 回目: started の active_session が先のほうでない: $lose"
    [ "$(issue_fields 42)" = "42|$win_dir||$win|" ] || die "$1 回目: 予約が空を返したほうのものでない: $(cat "$STATE/issues/42.json")"
    [ ! -e "$LOCK" ] || die "$1 回目: 錠が残った"
}

t_reserve_concurrent() {
    local i
    put_session s-a "$WT" "$(fkey "$WT_DIR")" 100
    put_session s-b "$WT2" "$(fkey "$WT2_DIR")" 200
    for i in 1 2 3 4 5 6 7 8 9 10; do
        concurrent_check_start_once "$i"
    done
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
    remote_sha=$(git -C "$MAIN_DIR" "${GITC[@]}" commit-tree -p "$SEED_SHA" -m remote "$SEED_SHA^{tree}")
    # origin を足す前に送る(Git 2.56 から、送り先の URL が足したリモートと同じだとリモートのブランチの記録ができるため)
    git -C "$MAIN_DIR" push -q "$ORIGIN_DIR" "$remote_sha:refs/heads/feat/extra" || die "リモートに push できない"
    git -C "$MAIN_DIR" remote add origin "$ORIGIN_DIR"
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

# =====================================================================
# claim の断りと、claim と takeover の錠(session-overlap-guard 要件1.3・1.4)
# =====================================================================
# claim を呼び、終了コードを CLAIM_RC に、標準エラーを CLAIM_ERR に入れる
claim_rc() { # <フォルダ> <引数>...
    ss "$1" claim "${@:2}" >/dev/null 2>"$WORK/claim-err.txt"
    CLAIM_RC=$?
    CLAIM_ERR=$(cat "$WORK/claim-err.txt")
}

t_claim_refuses_other_reservation() {
    local before want
    # WT のセッション s-wt が check-start で予約した(branch が空)
    put_session s-wt "$WT" "$(fkey "$WT_DIR")" 100
    put_session s-me "$WT2" "$(fkey "$WT2_DIR")" 200
    put_issue 42 "$WT" "" s-wt
    before=$(cat "$STATE/issues/42.json")
    claim_rc "$WT2_DIR" 42 --branch feat/wt2 --session s-me
    [ "$CLAIM_RC" = 1 ] || die "ほかの作業フォルダの予約への claim の終了コードが1でない: $CLAIM_RC: $CLAIM_ERR"
    want="[parallel] 着手できない: Issue #42 は、別のセッション(作業フォルダ $WT、セッション s-wt)が着手したものとして記録されている。"
    case "$CLAIM_ERR" in "$want"*) ;; *) die "標準エラーの文が違う: $CLAIM_ERR" ;; esac
    [ "$(cat "$STATE/issues/42.json")" = "$before" ] || die "ほかのセッションの予約を書き換えた: $(cat "$STATE/issues/42.json")"
    [ ! -e "$LOCK" ] || die "断ったあとに錠を残した"
    # 記録の session_id が空でも、folder がほかの作業フォルダなら断る
    put_issue 42 "$WT" feat/wt ""
    before=$(cat "$STATE/issues/42.json")
    claim_rc "$WT2_DIR" 42 --branch feat/wt2 --session s-me
    [ "$CLAIM_RC" = 1 ] || die "session_id が空でほかの作業フォルダの記録への claim の終了コードが1でない: $CLAIM_RC"
    [ "$(cat "$STATE/issues/42.json")" = "$before" ] || die "session_id が空の、ほかの作業フォルダの記録を書き換えた"
    # 同じ作業フォルダでも、記録の session_id が空でなくこのセッションのIDと違えば断る
    put_issue 42 "$WT2" "" s-wt
    before=$(cat "$STATE/issues/42.json")
    claim_rc "$WT2_DIR" 42 --branch feat/wt2 --session s-me
    [ "$CLAIM_RC" = 1 ] || die "同じ作業フォルダのほかのセッションの記録への claim の終了コードが1でない: $CLAIM_RC"
    case "$CLAIM_ERR" in *"作業フォルダ $WT2、セッション s-wt)"*) ;; *) die "標準エラーに記録の作業フォルダとセッションが出ない: $CLAIM_ERR" ;; esac
    [ "$(cat "$STATE/issues/42.json")" = "$before" ] || die "同じ作業フォルダのほかのセッションの記録を書き換えた"
}

t_claim_writes_own_or_free_record() {
    local upper
    put_session s-me "$WT" "$(fkey "$WT_DIR")" 100
    # 自分の予約があれば branch を書く
    check_start "$WT_DIR" check-start 42 --session s-me >/dev/null || die "check-start が成り立たない"
    [ "$(issue_fields 42)" = "42|$WT||s-me|" ] || die "前提: 自分の予約が無い: $(cat "$STATE/issues/42.json")"
    claim_rc "$WT_DIR" 42 --branch feat/wt --session s-me
    [ "$CLAIM_RC" = 0 ] || die "自分の予約への claim の終了コードが0でない: $CLAIM_RC: $CLAIM_ERR"
    [ "$(issue_fields 42)" = "42|$WT|feat/wt|s-me|" ] || die "自分の予約に branch を書いていない: $(cat "$STATE/issues/42.json")"
    [ ! -e "$LOCK" ] || die "claim のあとに錠を残した"
    # 記録が無ければ作る
    claim_rc "$WT_DIR" 43 --branch feat/wt --session s-me
    [ "$CLAIM_RC" = 0 ] || die "記録の無い claim の終了コードが0でない: $CLAIM_RC: $CLAIM_ERR"
    [ "$(issue_fields 43)" = "43|$WT|feat/wt|s-me|" ] || die "記録の無い claim の記録が違う: $(cat "$STATE/issues/43.json")"
    # folder と session_id が空の記録(prune が残した記録)は書き直す
    put_issue 44 "" feat/old ""
    claim_rc "$WT_DIR" 44 --branch feat/wt --session s-me
    [ "$CLAIM_RC" = 0 ] || die "prune が残した記録への claim の終了コードが0でない: $CLAIM_RC: $CLAIM_ERR"
    [ "$(issue_fields 44)" = "44|$WT|feat/wt|s-me|" ] || die "prune が残した記録を書き直していない: $(cat "$STATE/issues/44.json")"
    # 作業フォルダを比べるときは core.ignorecase に従う
    if [ "$(git -C "$MAIN_DIR" config --get core.ignorecase)" = true ]; then
        upper=$(printf '%s' "$WT" | tr 'abcdefghijklmnopqrstuvwxyz' 'ABCDEFGHIJKLMNOPQRSTUVWXYZ')
        put_issue 45 "$upper" "" s-me
        claim_rc "$WT_DIR" 45 --branch feat/wt --session s-me
        [ "$CLAIM_RC" = 0 ] || die "大文字と小文字だけが違う作業フォルダの自分の予約を断った: $CLAIM_RC: $CLAIM_ERR"
        [ "$(issue_fields 45)" = "45|$WT|feat/wt|s-me|" ] || die "大文字と小文字だけが違う自分の予約に書いていない: $(cat "$STATE/issues/45.json")"
    fi
}

t_claim_without_session_id_writes() {
    # このセッションのIDが空(--session も KP_SESSION_ID も無く、いまの作業フォルダにセッションの記録も無い)なら、
    # いまの作業フォルダの記録は、session_id が空でなくても断らずに書き直す
    unset KP_SESSION_ID
    [ ! -d "$STATE/sessions" ] || [ -z "$(ls "$STATE/sessions")" ] || die "前提: セッションの記録がある"
    put_issue 42 "$MAIN" "" s-other
    claim_rc "$MAIN_DIR" 42 --branch main
    [ "$CLAIM_RC" = 0 ] || die "IDが空のセッションの claim を断った: $CLAIM_RC: $CLAIM_ERR"
    [ "$(issue_fields 42)" = "42|$MAIN|main||" ] || die "IDが空のセッションの claim が記録を書き直していない: $(cat "$STATE/issues/42.json")"
    [ ! -e "$LOCK" ] || die "claim のあとに錠を残した"
}

# shellcheck disable=SC2016 # $d などは pj に渡す perl の式の変数で、シェルの変数ではない
t_end_then_check_start_takes_reservation() {
    local out before
    # WT のセッション s-wt が先に予約し、WT2 のセッション s-me には started で出る
    put_session s-wt "$WT" "$(fkey "$WT_DIR")" 100
    put_session s-me "$WT2" "$(fkey "$WT2_DIR")" 200
    check_start "$WT_DIR" check-start 42 --session s-wt >/dev/null || die "先の check-start が成り立たない"
    out=$(check_start "$WT2_DIR" check-start 42 --session s-me) || die "$out"
    [ "$(pj "$out" '$d->{leftovers}[0]{kinds}')" = '["started"]' ] || die "前提: 先の予約が started で出ない: $out"
    # 所有者が「やめた」と答えたので、s-wt の記録を消してから調べ直す
    ss "$WT2_DIR" end s-wt || die "end の終了コード $?"
    out=$(check_start "$WT2_DIR" check-start 42 --session s-me) || die "$out"
    [ "$(pj "$out" '$d->{leftovers}')" = '[]' ] || die "end のあとも leftovers が空でない: $out"
    [ "$(issue_fields 42)" = "42|$WT2||s-me|" ] || die "予約がこのセッションのものに書き換わっていない: $(cat "$STATE/issues/42.json")"
    # そのあとで先のセッションが claim しても、記録を奪わない
    before=$(cat "$STATE/issues/42.json")
    claim_rc "$WT_DIR" 42 --branch feat/wt --session s-wt
    [ "$CLAIM_RC" = 1 ] || die "やめたセッションの claim の終了コードが1でない: $CLAIM_RC: $CLAIM_ERR"
    [ "$(cat "$STATE/issues/42.json")" = "$before" ] || die "やめたセッションの claim が記録を書き換えた: $(cat "$STATE/issues/42.json")"
}

t_claim_lock_held_refused() {
    local before
    mkdir -p "$LOCK"
    # 記録が無いときも、錠を取れなければ作らない
    PATH="$TMP_ROOT/fastsleep:$PATH" claim_rc "$WT_DIR" 42 --branch feat/wt --session s-me
    [ "$CLAIM_RC" = 69 ] || die "錠がほかに持たれたままなのに claim の終了コードが69でない: $CLAIM_RC: $CLAIM_ERR"
    case "$CLAIM_ERR" in *'[parallel]'*records.lock*) ;; *) die "標準エラーに [parallel] で始まる錠の理由が無い: $CLAIM_ERR" ;; esac
    [ ! -f "$STATE/issues/42.json" ] || die "錠を取れないのに記録を書いた: $(cat "$STATE/issues/42.json")"
    [ -d "$LOCK" ] || die "ほかのセッションの錠を消した"
    # 自分の予約があっても、錠を取れなければ書き換えない
    put_issue 42 "$WT" "" s-me
    before=$(cat "$STATE/issues/42.json")
    PATH="$TMP_ROOT/fastsleep:$PATH" claim_rc "$WT_DIR" 42 --branch feat/wt --session s-me
    [ "$CLAIM_RC" = 69 ] || die "錠がほかに持たれたままなのに claim の終了コードが69でない(予約があるとき): $CLAIM_RC"
    [ "$(cat "$STATE/issues/42.json")" = "$before" ] || die "錠を取れないのに記録を書き換えた: $(cat "$STATE/issues/42.json")"
    [ -d "$LOCK" ] || die "ほかのセッションの錠を消した(予約があるとき)"
}

t_takeover_lock() {
    local before out rc real_perl
    put_session s-old "$WT" "$(fkey "$WT_DIR")" 100
    put_issue 42 "$WT" feat/wt s-old
    before=$(cat "$STATE/issues/42.json")
    # 錠がほかに持たれたままなら、記録を書かずに終了コード69で終わり、その錠を消さない
    mkdir -p "$LOCK"
    out=$(PATH="$TMP_ROOT/fastsleep:$PATH" ss "$WT_DIR" takeover 42 --from "$WT" --session s-new 2>"$WORK/err.txt")
    rc=$?
    [ "$rc" = 69 ] || die "錠がほかに持たれたままなのに takeover の終了コードが69でない: $rc: $out $(cat "$WORK/err.txt")"
    grep -q 'records.lock' "$WORK/err.txt" || die "標準エラーに錠の理由が無い: $(cat "$WORK/err.txt")"
    [ "$(cat "$STATE/issues/42.json")" = "$before" ] || die "錠を取れないのに記録を書き換えた: $(cat "$STATE/issues/42.json")"
    [ -d "$LOCK" ] || die "ほかのセッションの錠を消した"
    rmdir "$LOCK"
    # 錠の中で記録を読めなければ、終了コード69で終わり、錠を残さない
    real_perl=$(command -v perl)
    mkdir -p "$TMP_ROOT/handedfail"
    # handed_over_from を求める perl(_kp_ss_handed_json)だけが失敗する perl
    cat >"$TMP_ROOT/handedfail/perl" <<EOF
#!/bin/bash
case "\$*" in *'push @out, \$prev'*) echo "fake perl failure" >&2; exit 1 ;; esac
exec "$real_perl" "\$@"
EOF
    chmod +x "$TMP_ROOT/handedfail/perl"
    PATH="$TMP_ROOT/handedfail:$PATH" ss "$WT_DIR" takeover 42 --from "$WT" --session s-new >/dev/null 2>&1
    rc=$?
    [ "$rc" = 69 ] || die "記録を読めないのに takeover の終了コードが69でない: $rc"
    [ ! -e "$LOCK" ] || die "記録を読めなかったときに錠を残した"
    [ "$(cat "$STATE/issues/42.json")" = "$before" ] || die "記録を読めないのに書き換えた"
    # 引き継げたあとは錠を残さない。takeover は記録の持ち主を確かめずに書き直す
    ss "$WT_DIR" takeover 42 --from "$WT" --session s-new >/dev/null || die "takeover の終了コード $?"
    [ "$(issue_fields 42)" = "42|$WT|feat/wt|s-new|" ] || die "Issueの記録が書き直されていない: $(cat "$STATE/issues/42.json")"
    [ ! -e "$LOCK" ] || die "引き継いだあとに錠を残した"
}

# =====================================================================
# check-spec: 同じ spec を直しているほかのセッションの調べ(session-overlap-guard 要件2・要件3.1)
# =====================================================================
# 作業フォルダに触れずに、<親のコミット> にファイルを置いたコミットを作り、その ID を出す(origin/main を作るため)。
# 中身は printf の %b で読む(\n で改行)
main_commit() { # <親のコミット> <ファイル> <中身> [<ファイル> <中身>]...
    local parent="$1" idx="$WORK/main-commit.index" blob tree
    shift
    rm -f "$idx"
    GIT_INDEX_FILE="$idx" git -C "$MAIN_DIR" read-tree "$parent" || return 1
    while [ $# -ge 2 ]; do
        blob=$(printf '%b' "$2" | git -C "$MAIN_DIR" hash-object -w --stdin) || return 1
        GIT_INDEX_FILE="$idx" git -C "$MAIN_DIR" update-index --add --cacheinfo "100644,$blob,$1" || return 1
        shift 2
    done
    tree=$(GIT_INDEX_FILE="$idx" git -C "$MAIN_DIR" write-tree) || return 1
    rm -f "$idx"
    git -C "$MAIN_DIR" "${GITC[@]}" commit-tree -p "$parent" -m "main" "$tree"
}

# origin/main を <コミット> に動かす(偽物のリモートの main の進み具合)
set_origin_main() { git -C "$MAIN_DIR" update-ref refs/remotes/origin/main "$1" || die "origin/main を動かせない"; }

REQ=.kiro/specs/beta/requirements.md

# origin/main と WT・WT2 のブランチを、spec beta の requirements.md(a b c の3行)を持つコミット SPEC_BASE にする。
# WT のセッション s-wt は作業中(Issue 42 の記録がある)。WT2 のセッション s-me が調べる
spec_base() {
    SPEC_BASE=$(main_commit "$SEED_SHA" "$REQ" 'a\nb\nc\n') || die "SPEC_BASE を作れない"
    set_origin_main "$SPEC_BASE"
    git -C "$WT_DIR" reset -q --hard "$SPEC_BASE"
    git -C "$WT2_DIR" reset -q --hard "$SPEC_BASE"
    put_session s-wt "$WT" "$(fkey "$WT_DIR")" 300
    put_issue 42 "$WT" feat/wt s-wt
    put_session s-me "$WT2" "$(fkey "$WT2_DIR")" 400
}

# check-spec を呼び、終了コード0と1行の JSON であることを確かめて JSON を出す
check_spec() { # <フォルダ> <引数>...
    local out rc lines
    out=$(ss "$1" check-spec "${@:2}" 2>"$WORK/spec-err.txt")
    rc=$?
    [ "$rc" = 0 ] || die "check-spec の終了コード $rc: $(cat "$WORK/spec-err.txt")"
    lines=$(printf '%s\n' "$out" | wc -l)
    [ "$lines" -eq 1 ] || die "check-spec の出力が1行でない: $out"
    pj "$out" '1' >/dev/null 2>&1 || die "check-spec の出力が JSON でない: $out"
    printf '%s' "$out"
}

# check-spec の要素のセッションのIDを , でつないで出す
# shellcheck disable=SC2016 # $d などは pj に渡す perl の式の変数で、シェルの変数ではない
spec_sids() { pj "$1" 'join ",", map { $_->{session_id} } @{$d->{conflicts}}'; }

# 調べが残した一時的な索引(どの作業フォルダの git のディレクトリにも残してはならない)
spec_tmp_left() { find "$MAIN_DIR/.git" -name 'kp-check-spec*' 2>/dev/null; }

# 調べのあとに、錠と一時的な索引が残っていないことを確かめる
spec_clean_after() { # <場面>
    [ ! -e "$LOCK" ] || die "$1: 錠が残った"
    [ -z "$(spec_tmp_left)" ] || die "$1: 一時的な索引が残った: $(spec_tmp_left)"
}

# shellcheck disable=SC2016 # $d などは pj に渡す perl の式の変数で、シェルの変数ではない
t_check_spec_uncommitted() {
    local out
    spec_base
    out=$(check_spec "$WT2_DIR" beta --issue 50 --session s-me) || die "$out"
    [ "$(pj "$out" '$d->{conflicts}')" = '[]' ] || die "前提: 変更が無いのに conflicts が空でない: $out"
    # WT がコミットしていない spec の変更を持つ
    printf 'A\nb\nc\n' >"$WT_DIR/$REQ"
    out=$(check_spec "$WT2_DIR" beta --issue 50 --session s-me) || die "$out"
    [ "$(pj "$out" 'scalar @{$d->{conflicts}}')" = 1 ] || die "conflicts の数が1でない: $out"
    [ "$(pj "$out" '$d->{conflicts}[0]')" = "{\"folder\":\"$WT\",\"issue\":42,\"last_seen\":305,\"reason\":\"changes\",\"session_id\":\"s-wt\",\"started_at\":300}" ] \
        || die "要素の中身が違う: $out"
    spec_clean_after "変更があるとき"
    # ほかの spec の名前では出ない
    out=$(check_spec "$WT2_DIR" gamma --issue 50 --session s-me) || die "$out"
    [ "$(pj "$out" '$d->{conflicts}')" = '[]' ] || die "ほかの spec の名前で conflicts が出た: $out"
    # このセッションのIDの記録は除く
    out=$(check_spec "$WT2_DIR" beta --issue 50 --session s-wt) || die "$out"
    [ "$(pj "$out" '$d->{conflicts}')" = '[]' ] || die "このセッション自身が conflicts に出た: $out"
    # いまの作業フォルダの変更は数えない
    out=$(check_spec "$WT_DIR" beta --issue 50 --session s-other) || die "$out"
    [ "$(pj "$out" '$d->{conflicts}')" = '[]' ] || die "いまの作業フォルダの変更が conflicts に出た: $out"
    spec_clean_after "調べのあと"
}

t_check_spec_committed() {
    local out
    spec_base
    # spec の変更と spec の新しいファイルをコミットしたが、main にはマージしていない
    printf 'A\nb\nc\n' >"$WT_DIR/$REQ"
    echo design >"$WT_DIR/.kiro/specs/beta/design.md"
    git -C "$WT_DIR" add -A
    git -C "$WT_DIR" "${GITC[@]}" commit -q -m spec
    [ -z "$(wt_status "$WT_DIR")" ] || die "前提: WT がきれいでない"
    out=$(check_spec "$WT2_DIR" beta --issue 50 --session s-me) || die "$out"
    [ "$(spec_sids "$out")" = s-wt ] || die "コミットしてマージしていない変更で s-wt が出ない: $out"
    # 新しいファイルだけをコミットしたときも出る
    git -C "$WT_DIR" reset -q --hard "$SPEC_BASE"
    echo design >"$WT_DIR/.kiro/specs/beta/design.md"
    git -C "$WT_DIR" add -A
    git -C "$WT_DIR" "${GITC[@]}" commit -q -m spec-new-file
    out=$(check_spec "$WT2_DIR" beta --issue 50 --session s-me) || die "$out"
    [ "$(spec_sids "$out")" = s-wt ] || die "新しいファイルだけのコミットで s-wt が出ない: $out"
    spec_clean_after "調べのあと"
}

# shellcheck disable=SC2016 # $d などは pj に渡す perl の式の変数で、シェルの変数ではない
t_check_spec_old_base() {
    local out newer
    spec_base
    # WT のブランチは古い main(SPEC_BASE)から作られ、spec のほかのファイルだけをコミットした
    echo other >"$WT_DIR/other.txt"
    git -C "$WT_DIR" add -A
    git -C "$WT_DIR" "${GITC[@]}" commit -q -m other
    # origin/main が spec を変えた
    newer=$(main_commit "$SPEC_BASE" "$REQ" 'a\nB\nc\n') || die "origin/main の変更を作れない"
    set_origin_main "$newer"
    out=$(check_spec "$WT2_DIR" beta --issue 50 --session s-me) || die "$out"
    [ "$(pj "$out" '$d->{conflicts}')" = '[]' ] || die "古い main から作ったブランチで conflicts が出た: $out"
    # WT に spec のディレクトリが無い(spec ができる前の main から作った)ときも空
    git -C "$WT_DIR" reset -q --hard "$SEED_SHA"
    [ ! -e "$WT_DIR/.kiro/specs/beta" ] || die "前提: WT に spec beta がある"
    out=$(check_spec "$WT2_DIR" beta --issue 50 --session s-me) || die "$out"
    [ "$(pj "$out" '$d->{conflicts}')" = '[]' ] || die "spec の無い作業フォルダで conflicts が出た: $out"
    spec_clean_after "調べのあと"
}

t_check_spec_deleted_dir() {
    local out
    spec_base
    # WT が spec のディレクトリを作業フォルダで消した(コミットしていない)
    rm -rf "$WT_DIR/.kiro/specs/beta"
    out=$(check_spec "$WT2_DIR" beta --issue 50 --session s-me) || die "$out"
    [ "$(spec_sids "$out")" = s-wt ] || die "作業フォルダで spec のディレクトリを消したときに s-wt が出ない: $out"
    # 消したことをコミットした(作業フォルダにも HEAD の木にも spec が無い)が、main にはマージしていない
    git -C "$WT_DIR" add -A
    git -C "$WT_DIR" "${GITC[@]}" commit -q -m remove-spec
    if [ -e "$WT_DIR/.kiro/specs/beta" ] || git -C "$WT_DIR" cat-file -e HEAD:.kiro/specs/beta 2>/dev/null; then
        die "前提: WT の作業フォルダか HEAD の木に spec beta がある"
    fi
    out=$(check_spec "$WT2_DIR" beta --issue 50 --session s-me) || die "$out"
    [ "$(spec_sids "$out")" = s-wt ] || die "spec のディレクトリを消してコミットしたときに s-wt が出ない: $out"
    spec_clean_after "調べのあと"
}

# shellcheck disable=SC2016 # $d などは pj に渡す perl の式の変数で、シェルの変数ではない
t_check_spec_inactive_skipped() {
    local out
    spec_base
    printf 'A\nb\nc\n' >"$WT_DIR/$REQ"
    # WT のセッションの記録はあるが、Issueの記録が無い(着手していない)
    rm -f "$STATE/issues/42.json"
    out=$(check_spec "$WT2_DIR" beta --issue 50 --session s-me) || die "$out"
    [ "$(pj "$out" '$d->{conflicts}')" = '[]' ] || die "作業中でないセッションの作業フォルダで conflicts が出た: $out"
    # セッションの記録も無い(閉じた)
    put_issue 42 "$WT" feat/wt s-wt
    rm -f "$STATE/sessions/s-wt.json"
    out=$(check_spec "$WT2_DIR" beta --issue 50 --session s-me) || die "$out"
    [ "$(pj "$out" '$d->{conflicts}')" = '[]' ] || die "セッションの無い作業フォルダで conflicts が出た: $out"
    spec_clean_after "調べのあと"
}

# shellcheck disable=SC2016 # $d などは pj に渡す perl の式の変数で、シェルの変数ではない
t_check_spec_two_sessions_and_end() {
    local out
    spec_base
    # WT にもう1つ作業中のセッション s-wt0(先に始めた)がある
    put_session s-wt0 "$WT" "$(fkey "$WT_DIR")" 200
    printf 'A\nb\nc\n' >"$WT_DIR/$REQ"
    out=$(check_spec "$WT2_DIR" beta --issue 50 --session s-me) || die "$out"
    [ "$(spec_sids "$out")" = s-wt0,s-wt ] || die "要素が started_at の古い順の2つでない: $out"
    [ "$(pj "$out" 'join ",", map { "$_->{issue}|$_->{folder}|$_->{started_at}|$_->{last_seen}|$_->{reason}" } @{$d->{conflicts}}')" \
        = "42|$WT|200|205|changes,42|$WT|300|305|changes" ] || die "要素の欄が違う: $out"
    # 所有者が「やめた」と答えたので、s-wt0 の記録を消してから調べ直す
    ss "$WT2_DIR" end s-wt0 || die "end の終了コード $?"
    out=$(check_spec "$WT2_DIR" beta --issue 50 --session s-me) || die "$out"
    [ "$(spec_sids "$out")" = s-wt ] || die "end のあとも s-wt0 が出る: $out"
    ss "$WT2_DIR" end s-wt || die "end の終了コード $?"
    out=$(check_spec "$WT2_DIR" beta --issue 50 --session s-me) || die "$out"
    [ "$(pj "$out" '$d->{conflicts}')" = '[]' ] || die "両方を end したあとも conflicts が空でない: $out"
}

t_check_spec_leaves_worktree() {
    local out status index content refs head
    spec_base
    # WT は、索引に載せた変更と、載せていない変更と、git の管理外のファイルを持つ
    printf 'A\nb\nc\n' >"$WT_DIR/$REQ"
    git -C "$WT_DIR" add "$REQ"
    printf 'A\nb\nC\n' >"$WT_DIR/$REQ"
    echo draft >"$WT_DIR/.kiro/specs/beta/design.md"
    status=$(wt_status "$WT_DIR")
    index=$(git -C "$WT_DIR" ls-files -s)
    content=$(cat "$WT_DIR/$REQ" "$WT_DIR/.kiro/specs/beta/design.md")
    refs=$(git -C "$MAIN_DIR" for-each-ref)
    head=$(git -C "$WT_DIR" rev-parse HEAD)
    out=$(check_spec "$WT2_DIR" beta --issue 50 --session s-me) || die "$out"
    [ "$(spec_sids "$out")" = s-wt ] || die "前提: s-wt が出ない: $out"
    [ "$(wt_status "$WT_DIR")" = "$status" ] || die "WT の git status が変わった: $(wt_status "$WT_DIR")"
    [ "$(git -C "$WT_DIR" ls-files -s)" = "$index" ] || die "WT の索引が変わった"
    [ "$(cat "$WT_DIR/$REQ" "$WT_DIR/.kiro/specs/beta/design.md")" = "$content" ] || die "WT の中身が変わった"
    [ "$(git -C "$WT_DIR" rev-parse HEAD)" = "$head" ] || die "WT の HEAD が変わった"
    # 一時的なコミット S はどのブランチにも載らない
    [ "$(git -C "$MAIN_DIR" for-each-ref)" = "$refs" ] || die "ブランチなどの参照が変わった: $(git -C "$MAIN_DIR" for-each-ref)"
    spec_clean_after "調べのあと"
}

t_check_spec_no_origin_main() {
    local out rc err
    put_session s-wt "$WT" "$(fkey "$WT_DIR")" 300
    put_issue 42 "$WT" feat/wt s-wt
    out=$(ss "$WT2_DIR" check-spec beta --issue 50 --session s-me 2>"$WORK/err.txt")
    rc=$?
    err=$(cat "$WORK/err.txt")
    [ "$rc" = 69 ] || die "origin/main が無いのに終了コードが69でない: $rc: $out $err"
    [ -z "$out" ] || die "origin/main が無いのに JSON を出した: $out"
    case "$err" in *'[parallel] 調べられない: origin/main が手元に無い'*) ;; *) die "標準エラーの文が違う: $err" ;; esac
    spec_clean_after "origin/main が無いとき"
}

t_check_spec_usage() {
    local rc args
    set_origin_main "$SEED_SHA"
    for args in "Beta --issue 50" "be/ta --issue 50" "beta_x --issue 50" " --issue 50" "beta" "beta --issue" \
        "beta --issue x" "beta --issue 50 extra" "beta --issue 50 --bogus"; do
        # shellcheck disable=SC2086 # 引数を空白で分けて渡す
        ss "$WT2_DIR" check-spec $args >/dev/null 2>&1
        rc=$?
        [ "$rc" = 64 ] || die "check-spec $args の終了コードが64でない: $rc"
    done
    ss "$WT2_DIR" check-spec "" --issue 50 >/dev/null 2>&1
    rc=$?
    [ "$rc" = 64 ] || die "空の名前の終了コードが64でない: $rc"
    spec_clean_after "誤った呼び方のあと"
}

t_check_spec_git_failure() {
    local real_git out rc err at
    spec_base
    printf 'A\nb\nc\n' >"$WT_DIR/$REQ"
    real_git=$(command -v git)
    mkdir -p "$TMP_ROOT/gitfail"
    # FAKE_GIT_FAIL に挙げた段の git が失敗する。失敗するときに、一時的な索引が git のディレクトリにあれば
    # FAKE_GIT_MARK のファイルを作る(失敗したあとに、その索引が消されたことを確かめるため)。
    #   read-tree    一時的な索引に W の HEAD を読み込む git(本物の read-tree で索引を作ってから失敗する)
    #   add          一時的な索引に spec のディレクトリを載せる git
    #   commit-tree  一時的なコミット S を作る git
    #   merge-base   origin/main と S の分かれ目を求める git
    #   diff         分かれ目から S までの spec の差分を取る git
    cat >"$TMP_ROOT/gitfail/git" <<EOF
#!/bin/bash
fail() {
    if find "$MAIN_DIR/.git" -name 'kp-check-spec-index*' 2>/dev/null | grep -q .; then : >"\$FAKE_GIT_MARK"; fi
    echo "fake \$FAKE_GIT_FAIL failure" >&2
    exit 1
}
case "\$FAKE_GIT_FAIL: \$* " in
    "read-tree: "*" read-tree "*)
        case "\${GIT_INDEX_FILE:-}" in *kp-check-spec-index*) "$real_git" "\$@" >/dev/null 2>&1; fail ;; esac
        ;;
    "add: "*" add "*)
        case "\${GIT_INDEX_FILE:-}" in *kp-check-spec-index*) fail ;; esac
        ;;
    "commit-tree: "*" commit-tree "* | "merge-base: "*" merge-base "* | "diff: "*" diff "*) fail ;;
esac
exec "$real_git" "\$@"
EOF
    chmod +x "$TMP_ROOT/gitfail/git"
    for at in read-tree add commit-tree merge-base diff; do
        rm -f "$WORK/gitfail-mark"
        out=$(FAKE_GIT_FAIL=$at FAKE_GIT_MARK="$WORK/gitfail-mark" PATH="$TMP_ROOT/gitfail:$PATH" \
            ss "$WT2_DIR" check-spec beta --issue 50 --session s-me 2>"$WORK/err.txt")
        rc=$?
        err=$(cat "$WORK/err.txt")
        [ "$rc" = 69 ] || die "$at: git が失敗したのに終了コードが69でない: $rc: $out $err"
        [ -z "$out" ] || die "$at: git が失敗したのに JSON を出した: $out"
        case "$err" in *'[parallel] 調べられない:'*"$WT"*"fake $at failure"*) ;; *) die "$at: 標準エラーに作業フォルダと失敗の理由が無い: $err" ;; esac
        [ -e "$WORK/gitfail-mark" ] || die "$at: 前提: 失敗したときに一時的な索引が無かった"
        spec_clean_after "$at の git が失敗したとき"
    done
}

t_check_spec_lock_held() {
    local out rc
    spec_base
    mkdir -p "$LOCK"
    out=$(PATH="$TMP_ROOT/fastsleep:$PATH" ss "$WT2_DIR" check-spec beta --issue 50 --session s-me 2>"$WORK/err.txt")
    rc=$?
    [ "$rc" = 69 ] || die "錠がほかに持たれたままなのに終了コードが69でない: $rc: $out $(cat "$WORK/err.txt")"
    [ -z "$out" ] || die "錠を取れないのに JSON を出した: $out"
    grep -q 'records.lock' "$WORK/err.txt" || die "標準エラーに錠の理由が無い: $(cat "$WORK/err.txt")"
    [ -d "$LOCK" ] || die "ほかのセッションの錠を消した"
}

# --- check-spec の spec の予約(session-overlap-guard 要件2.5)
SPEC_RSV="$STATE/specs/beta.json"

# spec beta の予約を、session.sh の書き込みに頼らずに置く。<何秒前> は、いまの時刻から引いて updated_at にする
put_spec_reserve() { # <作業フォルダ> <session_id> <issue> <何秒前>
    mkdir -p "$STATE/specs"
    printf '{"feature":"beta","folder":"%s","issue":%s,"session_id":"%s","updated_at":%s}\n' \
        "$1" "$3" "$2" "$(($(date +%s) - $4))" >"$SPEC_RSV"
}

# shellcheck disable=SC2016 # $d などは pj に渡す perl の式の変数で、シェルの変数ではない
t_check_spec_reserve_starting() {
    local out before
    spec_base
    # WT の作業中のセッション s-wt が、580秒前に spec beta を予約した(spec のファイルはまだ変えていない)
    put_spec_reserve "$WT" s-wt 42 580
    before=$(cat "$SPEC_RSV")
    out=$(check_spec "$WT2_DIR" beta --issue 50 --session s-me) || die "$out"
    [ "$(pj "$out" 'scalar @{$d->{conflicts}}')" = 1 ] || die "600秒以内の予約で要素が1つでない: $out"
    [ "$(pj "$out" '$d->{conflicts}[0]')" = "{\"folder\":\"$WT\",\"issue\":42,\"last_seen\":305,\"reason\":\"starting\",\"session_id\":\"s-wt\",\"started_at\":300}" ] \
        || die "予約の要素の中身が違う: $out"
    [ "$(cat "$SPEC_RSV")" = "$before" ] || die "要素があるのに予約が書き換わった: $(cat "$SPEC_RSV")"
    spec_clean_after "予約があるとき"
    # 予約の folder と作業フォルダを比べるときは core.ignorecase に従う
    if [ "$(git -C "$MAIN_DIR" config --get core.ignorecase)" = true ]; then
        put_spec_reserve "$(printf '%s' "$WT" | tr 'abcdefghijklmnopqrstuvwxyz' 'ABCDEFGHIJKLMNOPQRSTUVWXYZ')" s-wt 42 10
        out=$(check_spec "$WT2_DIR" beta --issue 50 --session s-me) || die "$out"
        [ "$(pj "$out" 'join ",", map { "$_->{session_id}|$_->{reason}" } @{$d->{conflicts}}')" = "s-wt|starting" ] \
            || die "大文字と小文字だけが違う作業フォルダの予約で starting の要素が出ない: $out"
        put_spec_reserve "$WT" s-wt 42 580
        before=$(cat "$SPEC_RSV")
    fi
    # 作業中のセッションが2つある作業フォルダの予約では、どちらのセッションも starting の要素になる
    put_session s-wt0 "$WT" "$(fkey "$WT_DIR")" 200
    out=$(check_spec "$WT2_DIR" beta --issue 50 --session s-me) || die "$out"
    [ "$(pj "$out" 'join ",", map { "$_->{session_id}|$_->{reason}" } @{$d->{conflicts}}')" = "s-wt0|starting,s-wt|starting" ] \
        || die "2つのセッションの要素が starting で出ない: $out"
    rm -f "$STATE/sessions/s-wt0.json"
    # 予約と spec の変更の両方があるときは、reason は changes
    printf 'A\nb\nc\n' >"$WT_DIR/$REQ"
    out=$(check_spec "$WT2_DIR" beta --issue 50 --session s-me) || die "$out"
    [ "$(pj "$out" 'join ",", map { "$_->{session_id}|$_->{reason}" } @{$d->{conflicts}}')" = "s-wt|changes" ] \
        || die "予約と変更の両方があるのに reason が changes の1つでない: $out"
    [ "$(cat "$SPEC_RSV")" = "$before" ] || die "要素があるのに予約が書き換わった: $(cat "$SPEC_RSV")"
    spec_clean_after "調べのあと"
}

# shellcheck disable=SC2016 # $d などは pj に渡す perl の式の変数で、シェルの変数ではない
t_check_spec_reserve_ignored() {
    local out at
    spec_base
    # 600秒より古い予約は無視する
    put_spec_reserve "$WT" s-wt 42 620
    out=$(check_spec "$WT2_DIR" beta --issue 50 --session s-me) || die "$out"
    [ "$(pj "$out" '$d->{conflicts}')" = '[]' ] || die "600秒より古い予約で要素が出た: $out"
    # 予約のセッションが作業中でない(Issueの記録が無い)ときは無視する
    put_spec_reserve "$WT" s-wt 42 10
    mv "$STATE/issues/42.json" "$WORK/issue42.json"
    out=$(check_spec "$WT2_DIR" beta --issue 50 --session s-me) || die "$out"
    [ "$(pj "$out" '$d->{conflicts}')" = '[]' ] || die "作業中でないセッションの予約で要素が出た: $out"
    mv "$WORK/issue42.json" "$STATE/issues/42.json"
    # 予約のセッションの記録が無い(閉じた)ときは、その作業フォルダにほかの作業中のセッションがあっても無視する
    put_spec_reserve "$WT" s-closed 42 10
    out=$(check_spec "$WT2_DIR" beta --issue 50 --session s-me) || die "$out"
    [ "$(pj "$out" '$d->{conflicts}')" = '[]' ] || die "閉じたセッションの予約で要素が出た: $out"
    # 予約の folder が、予約のセッションの作業フォルダと違うときは無視する
    put_spec_reserve "$MAIN" s-wt 42 10
    out=$(check_spec "$WT2_DIR" beta --issue 50 --session s-me) || die "$out"
    [ "$(pj "$out" '$d->{conflicts}')" = '[]' ] || die "ほかの作業フォルダの予約で要素が出た: $out"
    # 予約の updated_at が負でない整数でないときは、警告を出さずに無視する
    for at in '"x"' '[1]' '"Inf"' '"1e9"' '-1' '1.5' 'true' 'null'; do
        printf '{"feature":"beta","folder":"%s","issue":42,"session_id":"s-wt","updated_at":%s}\n' "$WT" "$at" >"$SPEC_RSV"
        out=$(check_spec "$WT2_DIR" beta --issue 50 --session s-me) || die "$out"
        [ "$(pj "$out" '$d->{conflicts}')" = '[]' ] || die "updated_at が $at の予約で要素が出た: $out"
        [ ! -s "$WORK/spec-err.txt" ] || die "updated_at が $at の予約で標準エラーに出た: $(cat "$WORK/spec-err.txt")"
    done
    # 予約の session_id が空のときは、session_id が空の作業中のセッションの記録があっても無視する
    printf '{"folder":"%s","folder_key":"%s","last_seen":255,"session_id":"","started_at":250}\n' \
        "$WT" "$(fkey "$WT_DIR")" >"$STATE/sessions/blank.json"
    put_spec_reserve "$WT" "" 42 10
    out=$(check_spec "$WT2_DIR" beta --issue 50 --session s-me) || die "$out"
    [ "$(pj "$out" '$d->{conflicts}')" = '[]' ] || die "session_id が空の予約で要素が出た: $out"
    rm -f "$STATE/sessions/blank.json"
    # このセッション自身の予約は、ほかの作業フォルダに書かれていても数えない
    put_session s-me2 "$WT" "$(fkey "$WT_DIR")" 500
    put_spec_reserve "$WT" s-me2 42 10
    out=$(check_spec "$WT2_DIR" beta --issue 50 --session s-me2) || die "$out"
    [ "$(spec_sids "$out")" = "" ] || die "このセッション自身の予約で要素が出た: $out"
    spec_clean_after "調べのあと"
}

# shellcheck disable=SC2016 # $d などは pj に渡す perl の式の変数で、シェルの変数ではない
t_check_spec_reserve_written() {
    local out t0 t1 at
    spec_base
    [ ! -e "$SPEC_RSV" ] || die "前提: 予約がある"
    t0=$(date +%s)
    out=$(check_spec "$WT2_DIR" beta --issue 050 --session s-me) || die "$out"
    t1=$(date +%s)
    [ "$(pj "$out" '$d->{conflicts}')" = '[]' ] || die "前提: conflicts が空でない: $out"
    [ -f "$SPEC_RSV" ] || die "conflicts が空なのに予約を書いていない"
    [ "$(pj "$(cat "$SPEC_RSV")" 'join "|", sort keys %$d')" = "feature|folder|issue|session_id|updated_at" ] \
        || die "予約の欄が違う: $(cat "$SPEC_RSV")"
    [ "$(pj "$(cat "$SPEC_RSV")" 'join "|", $d->{feature}, $d->{folder}, $d->{session_id}, $d->{issue}')" = "beta|$WT2|s-me|50" ] \
        || die "予約の中身が違う: $(cat "$SPEC_RSV")"
    [ "$(pj "$(cat "$SPEC_RSV")" 'JSON::PP->new->allow_nonref->encode($d->{issue})')" = 50 ] || die "予約の issue が数でない: $(cat "$SPEC_RSV")"
    at=$(pj "$(cat "$SPEC_RSV")" '$d->{updated_at}')
    case "$at" in '' | *[!0-9]*) die "updated_at が UNIX 秒でない: $(cat "$SPEC_RSV")" ;; esac
    [ "$at" -ge "$t0" ] && [ "$at" -le "$t1" ] || die "updated_at が調べの時刻でない: $at($t0..$t1)"
    spec_clean_after "予約を書いたあと"
    # 書いた予約は、ほかの作業フォルダの作業中のセッションの check-spec に starting で見える
    put_issue 50 "$WT2" "" s-me
    out=$(check_spec "$WT_DIR" beta --issue 42 --session s-wt) || die "$out"
    [ "$(pj "$out" 'join ",", map { "$_->{session_id}|$_->{folder}|$_->{issue}|$_->{reason}" } @{$d->{conflicts}}')" = "s-me|$WT2|50|starting" ] \
        || die "書いた予約がほかのセッションに starting で見えない: $out"
    [ "$(pj "$(cat "$SPEC_RSV")" '$d->{session_id}')" = s-me ] || die "要素があるのに予約が書き換わった: $(cat "$SPEC_RSV")"
    # conflicts が空でないときは、予約が無ければ書かない
    rm -f "$SPEC_RSV" "$STATE/issues/50.json"
    printf 'A\nb\nc\n' >"$WT_DIR/$REQ"
    out=$(check_spec "$WT2_DIR" beta --issue 50 --session s-me) || die "$out"
    [ "$(spec_sids "$out")" = s-wt ] || die "前提: s-wt が出ない: $out"
    [ ! -e "$SPEC_RSV" ] || die "conflicts が空でないのに予約を書いた: $(cat "$SPEC_RSV")"
    # 古い予約があって conflicts が空のときは、このセッションの予約に書き直す
    git -C "$WT_DIR" checkout -q -- "$REQ"
    put_spec_reserve "$WT" s-wt 42 700
    out=$(check_spec "$WT2_DIR" beta --issue 50 --session s-me) || die "$out"
    [ "$(pj "$out" '$d->{conflicts}')" = '[]' ] || die "前提: conflicts が空でない: $out"
    [ "$(pj "$(cat "$SPEC_RSV")" 'join "|", $d->{folder}, $d->{session_id}, $d->{issue}')" = "$WT2|s-me|50" ] \
        || die "古い予約がこのセッションの予約に書き直されていない: $(cat "$SPEC_RSV")"
    spec_clean_after "調べのあと"
}

t_check_spec_reserve_write_failure() {
    local real_perl out rc err
    spec_base
    real_perl=$(command -v perl)
    mkdir -p "$TMP_ROOT/writefail"
    # 記録を書く perl(lib.sh の kp_json_write)だけが失敗する perl
    cat >"$TMP_ROOT/writefail/perl" <<EOF
#!/bin/bash
case "\$*" in *kp_json_write*) echo "fake write failure" >&2; exit 1 ;; esac
exec "$real_perl" "\$@"
EOF
    chmod +x "$TMP_ROOT/writefail/perl"
    out=$(PATH="$TMP_ROOT/writefail:$PATH" ss "$WT2_DIR" check-spec beta --issue 50 --session s-me 2>"$WORK/err.txt")
    rc=$?
    err=$(cat "$WORK/err.txt")
    [ "$rc" = 69 ] || die "予約を書けないのに終了コードが69でない: $rc: $out $err"
    [ -z "$out" ] || die "予約を書けないのに JSON を出した: $out"
    case "$err" in *'[parallel] 調べられない:'*beta*) ;; *) die "標準エラーに [parallel] で始まる理由が無い: $err" ;; esac
    [ ! -e "$SPEC_RSV" ] || die "予約を書けなかったのに予約がある: $(cat "$SPEC_RSV")"
    spec_clean_after "予約を書けなかったとき"
}

# --- prune の spec の予約の片付け(session-overlap-guard 要件2.5)
# 予約 specs/<名前>.json を、updated_at の JSON の値をそのまま書いて置く
put_spec_reserve_raw() { # <名前> <updated_at の JSON>
    mkdir -p "$STATE/specs"
    printf '{"feature":"%s","folder":"%s","issue":42,"session_id":"s-wt","updated_at":%s}\n' \
        "$1" "$WT" "$2" >"$STATE/specs/$1.json"
}

t_prune_spec_reservations() {
    local out err rc name kept fresh at i
    local -a bad=()
    # specs/ が無くても prune は成り立ち、specs/ を作らない
    ss "$MAIN_DIR" prune >"$WORK/out.txt" 2>"$WORK/err.txt" || die "specs/ が無いときの prune の終了コード $?: $(cat "$WORK/err.txt")"
    [ ! -e "$STATE/specs" ] || die "specs/ が無いときに prune が specs/ を作った"
    # 600秒たった予約(old)と、600秒たっていない予約(fresh)と、updated_at が負でない整数でない予約と、読めない JSON
    put_spec_reserve_raw old "$(($(date +%s) - 600))"
    put_spec_reserve_raw older "$(($(date +%s) - 86400))"
    fresh=$(($(date +%s) - 580))
    put_spec_reserve_raw fresh "$fresh"
    kept=$(cat "$STATE/specs/fresh.json")
    i=0
    for at in '"Inf"' '"x"' 'null' '1.5' '-1' '"1e9"' 'true' '[1]' '{}'; do
        i=$((i + 1))
        put_spec_reserve_raw "bad$i" "$at"
        bad+=("bad$i")
    done
    printf '{"feature":"noat","folder":"%s","session_id":"s-wt"}\n' "$WT" >"$STATE/specs/noat.json"
    printf '{"feature":"broken",' >"$STATE/specs/broken.json"
    printf '[1,2]\n' >"$STATE/specs/array.json"
    out=$(ss "$MAIN_DIR" prune 2>"$WORK/err.txt")
    rc=$?
    err=$(cat "$WORK/err.txt")
    [ "$rc" = 0 ] || die "prune の終了コード $rc: $out $err"
    for name in old older "${bad[@]}" noat broken array; do
        [ ! -e "$STATE/specs/$name.json" ] || die "spec の予約 $name.json が消えていない: $(cat "$STATE/specs/$name.json")"
        printf '%s\n' "$out" | grep -qxF "[parallel] 片付け: spec の予約 $name.json を消した" \
            || die "spec の予約 $name.json を消したことが標準出力に無い: $out"
    done
    [ "$(cat "$STATE/specs/fresh.json" 2>/dev/null)" = "$kept" ] || die "600秒たっていない予約が消えたか変わった"
    case "$out" in *fresh.json*) die "残した予約を消したと出した: $out" ;; esac
    [ -z "$err" ] || die "片付けで標準エラーに出た: $err"
    [ ! -e "$LOCK" ] || die "prune が記録の錠を残した"
    # check-start も、最初の prune で古い予約を消す(標準出力には出さない)
    put_spec_reserve_raw old "$(($(date +%s) - 700))"
    out=$(check_start "$MAIN_DIR" check-start 42 --session s-me) || die "$out"
    [ ! -e "$STATE/specs/old.json" ] || die "check-start の prune が古い予約を消していない"
    [ -f "$STATE/specs/fresh.json" ] || die "check-start の prune が600秒たっていない予約を消した"
}

t_prune_spec_reservations_lock_held() {
    local out err rc
    put_spec_reserve_raw old "$(($(date +%s) - 700))"
    # ほかのセッションが記録の錠を持っている(60秒より新しい)あいだは、予約を消さずに理由を標準エラーに出す
    mkdir -p "$LOCK"
    out=$(PATH="$TMP_ROOT/fastsleep:$PATH" ss "$MAIN_DIR" prune 2>"$WORK/err.txt")
    rc=$?
    err=$(cat "$WORK/err.txt")
    [ "$rc" = 0 ] || die "錠を取れないときの prune の終了コード $rc: $out $err"
    [ -f "$STATE/specs/old.json" ] || die "錠を取れないのに予約を消した"
    case "$err" in *'[parallel]'*'spec の予約'*records.lock*) ;; *) die "標準エラーに spec の予約と錠の理由が無い: $err" ;; esac
    [ -d "$LOCK" ] || die "ほかのセッションの錠を消した"
    # 錠が返されたあとの prune は消す
    rmdir "$LOCK"
    out=$(ss "$MAIN_DIR" prune 2>/dev/null) || die "prune の終了コード $?"
    [ ! -e "$STATE/specs/old.json" ] || die "錠が返されたあとの prune が古い予約を消していない"
    [ ! -e "$LOCK" ] || die "prune が記録の錠を残した"
}

# --- check-spec の判定の細かい場面(変更のかたまりを M の行の位置で比べる。session-overlap-guard 要件2.1・2.4)
# 場面ごとに、spec_base のあとで spec_case で WT と origin/main を作り、expect_spec で WT2 から調べた結果を確かめる。
# 「squash でのマージ」は、W と同じ中身を、古い main(土台)の上の別のコミットとして origin/main に入れて真似る

# <親のコミット> から <パス> を除いたコミットを作り、その ID を出す(作業フォルダに触れない)
main_rm_commit() { # <親のコミット> <パス>
    local idx="$WORK/main-commit.index" tree
    rm -f "$idx"
    GIT_INDEX_FILE="$idx" git -C "$MAIN_DIR" read-tree "$1" || return 1
    GIT_INDEX_FILE="$idx" git -C "$MAIN_DIR" rm -q -r --cached -- "$2" || return 1
    tree=$(GIT_INDEX_FILE="$idx" git -C "$MAIN_DIR" write-tree) || return 1
    rm -f "$idx"
    git -C "$MAIN_DIR" "${GITC[@]}" commit-tree -p "$1" -m "main" "$tree"
}

# 場面を作る。REQ が <土台> のコミット CASE_BASE に WT を戻し(コミットしていない変更と新しいファイルも消す)、
# WT の REQ を <W の中身> にする(コミットしない)。origin/main は、CASE_BASE から REQ を <main の中身> に順に
# 変えたコミットの列の先にする(<main の中身> が無ければ CASE_BASE のまま。マージしていない場面)。中身は printf の %b で読む
spec_case() { # <土台> <W の中身> [<main の中身>...]
    local tip c
    CASE_BASE=$(main_commit "$SEED_SHA" "$REQ" "$1") || die "土台のコミットを作れない"
    git -C "$WT_DIR" reset -q --hard "$CASE_BASE" || die "WT を土台に戻せない"
    git -C "$WT_DIR" clean -fdq
    printf '%b' "$2" >"$WT_DIR/$REQ"
    tip=$CASE_BASE
    shift 2
    for c in "$@"; do
        tip=$(main_commit "$tip" "$REQ" "$c") || die "origin/main のコミットを作れない"
    done
    set_origin_main "$tip"
}

# WT2 のセッション s-me から check-spec を呼び、WT のセッション s-wt の要素が出るか(changes)、
# conflicts が空か(empty)を確かめる
# shellcheck disable=SC2016 # $d などは pj に渡す perl の式の変数で、シェルの変数ではない
expect_spec() { # <場面> <changes|empty>
    local out
    out=$(check_spec "$WT2_DIR" beta --issue 50 --session s-me) || die "$1: $out"
    if [ "$2" = changes ]; then
        [ "$(spec_sids "$out")" = s-wt ] || die "$1: s-wt の要素が出ない: $out"
        [ "$(pj "$out" '$d->{conflicts}[0]{reason}')" = changes ] || die "$1: reason が changes でない: $out"
    else
        [ "$(pj "$out" '$d->{conflicts}')" = '[]' ] || die "$1: conflicts が空でない: $out"
    fi
}

t_check_spec_squash_merged() {
    spec_base
    spec_case 'a\nb\nc\n' 'A\nb\nc\n'
    expect_spec "1行目を書き換え、マージしていない" changes
    spec_case 'a\nb\nc\n' 'A\nb\nc\n' 'a\nB\nc\n'
    expect_spec "1行目を書き換え、マージしていない(main は隣の2行目を書き換えた)" changes
    spec_case 'a\nb\nc\n' 'A\nb\nc\n' 'A\nb\nc\n'
    expect_spec "1行目の書き換えを squash でマージした" empty
    spec_case 'a\nb\nc\n' 'A\nb\nc\n' 'A\nb\nc\n' 'A\nB\nc\n'
    expect_spec "1行目の書き換えを squash でマージし、隣の2行目がさらに変わった" empty
    spec_case 'a\nb\nc\n' 'A\nb\nc\n' 'Z\nb\nc\n'
    expect_spec "main が同じ1行目を別の中身に変えた" changes
    spec_case 'a\nb\nc\n' 'A\nb\nc\n' 'A\nb\nc\n' 'A2\nb\nc\n'
    expect_spec "1行目の書き換えをマージしたあと、main が同じ行をさらに書き換えた" changes
    # 終わりに改行の無い行は、改行のある行と別の中身として比べる
    spec_case 'a\nb\nc\n' 'a\nb\nC' 'a\nb\nC\n'
    expect_spec "最後の行を改行無しで書き換え、main は同じ行を改行ありで書き換えた" changes
    spec_case 'a\nb\nc\n' 'a\nb\nC' 'a\nb\nC'
    expect_spec "最後の行を改行無しで書き換えた変更を squash でマージした" empty
    spec_clean_after "調べのあと"
}

t_check_spec_delete_and_add_lines() {
    spec_base
    spec_case 'a\nb\nc\n' 'a\nc\n'
    expect_spec "2行目を消しただけで、マージしていない" changes
    spec_case 'a\nb\nc\n' 'a\nc\n' 'a\nc\n'
    expect_spec "2行目を消した変更を squash でマージした" empty
    spec_case 'a\nb\nc\n' 'b\nc\n'
    expect_spec "先頭の行を消し、マージしていない" changes
    spec_case 'a\nb\nc\n' 'b\nc\n' 'b\nc\n'
    expect_spec "先頭の行を消した変更を squash でマージした" empty
    spec_case 'a\nb\nc\n' ''
    expect_spec "ファイルを空にし、マージしていない" changes
    spec_case 'a\nb\nc\n' '' ''
    expect_spec "ファイルを空にした変更を squash でマージした" empty
    spec_case 'a\nb\nc\n' 'a\nN\nb\nc\n'
    expect_spec "行を1行足しただけで、マージしていない" changes
    spec_case 'a\nb\nc\n' 'a\nN\nb\nc\n' 'a\nN\nb\nc\n'
    expect_spec "行を足した変更を squash でマージした" empty
    spec_clean_after "調べのあと"
}

t_check_spec_files_and_dir() {
    local tip pad
    spec_base
    # コミットしていない新しいファイルだけを足した
    spec_case 'a\nb\nc\n' 'a\nb\nc\n'
    mkdir -p "$WT_DIR/.kiro/specs/beta/reviews"
    printf 'note\n' >"$WT_DIR/.kiro/specs/beta/reviews/r.md"
    expect_spec "コミットしていない新しいファイルだけを足し、マージしていない" changes
    tip=$(main_commit "$CASE_BASE" .kiro/specs/beta/reviews/r.md 'note\n') || die "origin/main のコミットを作れない"
    set_origin_main "$tip"
    expect_spec "新しいファイルを squash でマージした" empty
    # spec のディレクトリを作業フォルダで消した(コミットしていない)
    spec_case 'a\nb\nc\n' 'a\nb\nc\n'
    rm -rf "$WT_DIR/.kiro/specs/beta"
    expect_spec "spec のディレクトリを作業フォルダで消し、マージしていない" changes
    tip=$(main_rm_commit "$CASE_BASE" .kiro/specs/beta) || die "origin/main のコミットを作れない"
    set_origin_main "$tip"
    expect_spec "spec のディレクトリを消した変更を squash でマージした" empty
    # spec のディレクトリを消してコミットした(作業フォルダにも HEAD の木にも spec が無い)
    spec_case 'a\nb\nc\n' 'a\nb\nc\n'
    git -C "$WT_DIR" rm -q -r -- .kiro/specs/beta || die "spec のディレクトリを消せない"
    git -C "$WT_DIR" "${GITC[@]}" commit -q -m remove-spec || die "消したことをコミットできない"
    expect_spec "spec のディレクトリを消してコミットし、マージしていない" changes
    set_origin_main "$tip"
    expect_spec "spec のディレクトリを消してコミットした変更を squash でマージした" empty
    # バイナリのファイル(NUL を含む)は、S と origin/main の中身が同じときだけ入っているとみなす
    spec_case 'a\nb\nc\n' 'a\nb\nc\n'
    printf 'x\000y\n' >"$WT_DIR/.kiro/specs/beta/b.bin"
    expect_spec "バイナリのファイルを足し、マージしていない" changes
    tip=$(main_commit "$CASE_BASE" .kiro/specs/beta/b.bin 'x\0000z\n') || die "origin/main のコミットを作れない"
    set_origin_main "$tip"
    expect_spec "main が同じバイナリのファイルを別の中身で足した" changes
    tip=$(main_commit "$CASE_BASE" .kiro/specs/beta/b.bin 'x\0000y\n') || die "origin/main のコミットを作れない"
    set_origin_main "$tip"
    expect_spec "バイナリのファイルを squash でマージした" empty
    # NUL が先頭の8000バイトより後ろにあり、git が文字のファイルとみなすときも、中身(blob)で比べる。
    # main は W の足した行に1行を足した中身なので、変更のかたまりで比べると入っているように見える
    spec_case 'a\nb\nc\n' 'a\nb\nc\n'
    pad=$(printf '%9000s' '' | tr ' ' a)
    printf '%s\n\000\n' "$pad" >"$WT_DIR/.kiro/specs/beta/late.bin"
    tip=$(main_commit "$CASE_BASE" .kiro/specs/beta/late.bin "$pad\n\0000\nZ\n") || die "origin/main のコミットを作れない"
    set_origin_main "$tip"
    git -C "$MAIN_DIR" diff "$CASE_BASE" "$tip" | grep -q '^@@' || die "前提: git が NUL の遅いファイルをバイナリとみなした"
    expect_spec "NUL が後ろにあるファイルを足し、main は1行多い中身で足した" changes
    spec_clean_after "調べのあと"
}

t_check_spec_same_content_elsewhere() {
    spec_base
    spec_case 'a\nb\nc\n' 'c\nb\nc\n'
    expect_spec "1行目の a を c に書き換え、main は別の行に c を持つだけ" changes
    spec_case 'a\nb\nc\n' 'a\nN\nb\nc\n' 'a\nb\nc\nN\n'
    expect_spec "行を足し、main は同じ中身の行を別の場所に足しただけ" changes
    # 2行目と4行目が空行のファイル
    spec_case 'x\n\ny\n\nz\n' 'x\ny\n\nz\n' 'x\n\ny\nz\n'
    expect_spec "2行目の空行を消し、main は4行目の空行を消した" changes
    spec_case 'x\n\ny\n\nz\n' 'x\ny\n\nz\n' 'x\n\nY\nz\n'
    expect_spec "2行目の空行を消し、main は3行目を書き換えて4行目の空行を消した" changes
    spec_case 'x\n\ny\n\nz\n' 'x\n\ny\nz\n' 'x\nY\n\nz\n'
    expect_spec "4行目の空行を消し、main は2行目の空行を消して3行目を書き換えた" changes
    spec_case 'x\n\ny\n\nz\n' 'x\n\ny\nz\n' 'x\n\ny\nz\n' 'x\n\nY\nz\n'
    expect_spec "4行目の空行を消した変更を squash でマージし、3行目も書き換えた" empty
    spec_clean_after "調べのあと"
}

t_check_spec_hunk_positions() {
    spec_base
    spec_case '1\n2\n3\n4\n5\n' '1\n2\n5\n' '1\n2\n3\nFOUR\n5\n'
    expect_spec "3行目と4行目を消し、main は4行目だけを書き換えた" changes
    spec_case '1\n2\n3\n4\n5\n' '1\n2\n5\n' '1\n2\n5\n'
    expect_spec "3行目と4行目を消した変更を squash でマージした" empty
    spec_case 'a\nb\nc\n' 'a\nN\nb\nc\n' 'a\nN\nb\nc\n' 'A\nN\nb\nc\n'
    expect_spec "行を足した変更を squash でマージし、直前の行を書き換えた" empty
    spec_case 'a\nb\nc\n' 'a\nN\nb\nc\n' 'a\nN\nb\nc\n' 'a\nN\nB\nc\n'
    expect_spec "行を足した変更を squash でマージし、直後の行を書き換えた" empty
    spec_case 'a\nb\nc\n' 'a\nb\nN\nc\n' 'A\nN\nb\nc\n'
    expect_spec "2行目のあとに行を足し、main は同じ中身の行を1行目のあとに足して1行目を書き換えた" changes
    # 足した行は、main の足した行の中に同じ順で現れなければならない
    spec_case 'a\nb\nc\n' 'a\nX\nY\nb\nc\n' 'a\nY\nX\nb\nc\n'
    expect_spec "1行目のあとに X と Y を足し、main は同じ位置に Y と X の順で足した" changes
    spec_case 'a\nb\nc\n' 'a\nX\nY\nb\nc\n' 'a\nX\nY\nb\nc\n'
    expect_spec "1行目のあとに X と Y を足した変更を squash でマージした" empty
    spec_case '1\n2\n3\n4\n5\n' '1\n2\n3\n5\n' '1\n2\n3\n4\nNEW\n5\n'
    expect_spec "4行目を消し、main は4行目と5行目の間に行を足しただけ" changes
    spec_case '1\n2\n3\n4\n5\n' '1\n2\n3\n5\n' '1\n2\nTHREE\n4\nFIVE\n'
    expect_spec "4行目を消し、main は3行目と5行目を書き換えた" changes
    # 利用者の git の設定と環境変数で、かたまりの区切りと前後の行が変わらない
    git -C "$MAIN_DIR" config diff.interHunkContext 3
    [ "$(git -C "$MAIN_DIR" diff -U0 "$CASE_BASE" origin/main -- "$REQ" | grep -c '^@@')" = 1 ] \
        || die "前提: diff.interHunkContext で main の2つのかたまりが1つにまとまらない"
    expect_spec "diff.interHunkContext を置いても、4行目を消し main が3行目と5行目を書き換えた" changes
    git -C "$MAIN_DIR" config --unset diff.interHunkContext
    GIT_DIFF_OPTS=-u3 git -C "$MAIN_DIR" diff -U0 "$CASE_BASE" origin/main -- "$REQ" | grep -q '^ ' \
        || die "前提: GIT_DIFF_OPTS で差分に前後の行が入らない"
    export GIT_DIFF_OPTS=-u3
    expect_spec "GIT_DIFF_OPTS を置いても、4行目を消し main が3行目と5行目を書き換えた" changes
    unset GIT_DIFF_OPTS
    spec_clean_after "調べのあと"
}

t_check_spec_context_line_refused() {
    local real_git out rc err
    spec_base
    spec_case 'a\nb\nc\n' 'A\nb\nc\n' 'A\nb\nc\n'
    real_git=$(command -v git)
    mkdir -p "$TMP_ROOT/gitctx"
    # -U0 の git diff の出力の、最初のかたまりの本文に、空白で始まる行(前後の行)を混ぜる偽物の git
    cat >"$TMP_ROOT/gitctx/git" <<EOF
#!/bin/bash
set -o pipefail
case " \$* " in
    *" diff "*"-U0 "*)
        "$real_git" "\$@" | perl -pe 'if (!\$done && /^@@ /) { \$_ .= " injected\\n"; \$done = 1 }'
        exit
        ;;
esac
exec "$real_git" "\$@"
EOF
    chmod +x "$TMP_ROOT/gitctx/git"
    "$TMP_ROOT/gitctx/git" -C "$MAIN_DIR" diff -U0 "$CASE_BASE" origin/main -- "$REQ" | grep -q '^ injected$' \
        || die "前提: 偽物の git が前後の行を混ぜない"
    out=$(PATH="$TMP_ROOT/gitctx:$PATH" ss "$WT2_DIR" check-spec beta --issue 50 --session s-me 2>"$WORK/err.txt")
    rc=$?
    err=$(cat "$WORK/err.txt")
    [ "$rc" = 69 ] || die "差分に前後の行があるのに終了コードが69でない: $rc: $out $err"
    [ -z "$out" ] || die "差分に前後の行があるのに JSON を出した: $out"
    case "$err" in *'[parallel] 調べられない:'*"$WT"*"$REQ"*) ;; *) die "標準エラーに作業フォルダとファイルの名前が無い: $err" ;; esac
    spec_clean_after "差分に前後の行があったとき"
}

# =====================================================================
# busy-issues: spec があるIssueと、ほかのセッションが作業中のIssue(spec-need-triage 要件11.4)
# =====================================================================
# busy-issues を呼び、終了コード0と1行の JSON であることを確かめて JSON を出す(標準エラーは $WORK/busy-err.txt に残す)
busy() { # <フォルダ> <引数>...
    local out rc lines
    out=$(ss "$1" busy-issues "${@:2}" 2>"$WORK/busy-err.txt")
    rc=$?
    [ "$rc" = 0 ] || die "busy-issues の終了コード $rc: $(cat "$WORK/busy-err.txt")"
    lines=$(printf '%s\n' "$out" | wc -l)
    [ "$lines" -eq 1 ] || die "busy-issues の出力が1行でない: $out"
    pj "$out" '1' >/dev/null 2>&1 || die "busy-issues の出力が JSON でない: $out"
    printf '%s' "$out"
}

# 記録の置き場所のファイルとディレクトリの一覧と、ファイルの中身を出す(busy-issues が記録を書かないことを比べるため)
state_snapshot() {
    local p
    (cd "$STATE" && find . | LC_ALL=C sort) || return 1
    while IFS= read -r p; do
        printf '== %s\n' "$p"
        cat "$p"
    done < <(find "$STATE" -type f | LC_ALL=C sort)
}

t_busy_empty() {
    local out d
    # 種のコミットの spec alpha を、どの作業フォルダの中身からも消す(reset_state が戻す)
    for d in "$MAIN_DIR" "$WT_DIR" "$WT2_DIR"; do
        rm -rf "$d/.kiro"
    done
    out=$(busy "$MAIN_DIR" --session s-me) || die "$out"
    [ "$out" = '{"active":[],"spec":[]}' ] || die "記録も spec も無いのに空の配列でない: $out"
    [ ! -e "$LOCK" ] || die "錠を残した"
}

# shellcheck disable=SC2016 # $d などは pj に渡す perl の式の変数で、シェルの変数ではない
t_busy_active_started() {
    local out
    # WT のセッション s-wt は claim した(branch がある)。WT2 のセッション s-wt2 はブランチを作る前に予約した(branch が空)
    put_session s-wt "$WT" "$(fkey "$WT_DIR")" 300
    put_issue 42 "$WT" feat/wt s-wt
    put_session s-wt2 "$WT2" "$(fkey "$WT2_DIR")" 310
    put_issue 43 "$WT2" "" s-wt2
    out=$(busy "$MAIN_DIR" --session s-me) || die "$out"
    [ "$(pj "$out" '$d->{active}')" = '[42,43]' ] || die "claim した記録と予約の記録が active に出ない: $out"
    # このセッションの記録は出ない(--session でも、KP_SESSION_ID でも、いまの作業フォルダのセッションの記録からでも)
    out=$(busy "$WT_DIR" --session s-wt) || die "$out"
    [ "$(pj "$out" '$d->{active}')" = '[43]' ] || die "--session s-wt で自分の記録が active に出た: $out"
    out=$(KP_SESSION_ID=s-wt2 busy "$WT2_DIR") || die "$out"
    [ "$(pj "$out" '$d->{active}')" = '[42]' ] || die "KP_SESSION_ID=s-wt2 で自分の記録が active に出た: $out"
    out=$(busy "$WT_DIR") || die "$out"
    [ "$(pj "$out" '$d->{active}')" = '[43]' ] || die "作業フォルダのセッションの記録から決めた自分の記録が active に出た: $out"
    [ ! -e "$LOCK" ] || die "錠を残した"
}

# shellcheck disable=SC2016 # $d などは pj に渡す perl の式の変数で、シェルの変数ではない
t_busy_active_excluded() {
    local out gone="$WORK/RepoGone"
    put_session s-wt "$WT" "$(fkey "$WT_DIR")" 300
    # 数える記録(下の記録がすべて外れたことを、何も出ないことと見分けるため)
    put_issue 56 "$WT" feat/wt s-wt
    # prune が残したブランチだけの記録(folder と session_id が空)
    git -C "$MAIN_DIR" branch -q feat/extra "$SEED_SHA"
    put_issue 50 "" feat/extra ""
    # セッションの記録が無い(セッションを終えた)記録
    put_issue 51 "$WT" "" s-closed
    # 作業フォルダが無くなったセッションの記録(prune が消し終えるまで残す記録)。Issueの記録の folder は開かれている
    put_session s-gone "$gone" "$(fkey_path "$gone")" 200
    put_issue 52 "$WT" "" s-gone
    # 同じ作業フォルダで開き直したセッション s-new がいるときの、前のセッション s-prev の記録(folder だけが一致する)
    put_session s-new "$WT2" "$(fkey "$WT2_DIR")" 320
    put_issue 53 "$WT2" "" s-prev
    # 記録の folder が handed_over_from にある記録
    put_issue 54 "$WT" "" s-wt "[\"$WT\"]"
    # 記録の folder が開かれている作業フォルダでない記録
    put_issue 55 "$WORK/RepoElsewhere" "" s-wt
    out=$(busy "$MAIN_DIR" --session s-me) || die "$out"
    [ "$(pj "$out" '$d->{active}')" = '[56]' ] || die "数えない記録が active に出たか、数える記録が出ない: $out"
}

t_busy_spec_sources() {
    local c out
    # 本体の中身(コミットしていない spec)と、worktree の中身。種のコミットの alpha(10)も本体と worktree の中身にある
    put_spec "$MAIN_DIR" beta 20 '[21]'
    put_spec "$WT_DIR" gamma 22 '[23]'
    # origin/main にだけある spec
    c=$(main_commit "$SEED_SHA" .kiro/specs/delta/spec.json '{"issue":30,"additional_issues":[31]}\n') \
        || die "origin/main を作れない"
    set_origin_main "$c"
    # 記録の branch のブランチにだけある spec(ローカルのブランチ)
    c=$(main_commit "$SEED_SHA" .kiro/specs/epsilon/spec.json '{"issue":40,"additional_issues":[41]}\n') \
        || die "ブランチのコミットを作れない"
    git -C "$MAIN_DIR" update-ref refs/heads/feat/extra-local "$c" || die "ローカルのブランチを作れない"
    put_issue 60 "" feat/extra-local ""
    # 記録の branch のブランチにだけある spec(リモートにだけあるブランチ)
    c=$(main_commit "$SEED_SHA" .kiro/specs/zeta/spec.json '{"issue":44}\n') || die "ブランチのコミットを作れない"
    git -C "$MAIN_DIR" update-ref refs/remotes/origin/feat/extra-remote "$c" || die "リモートのブランチを作れない"
    put_issue 61 "" feat/extra-remote ""
    # ローカルにもリモートにもあるブランチは、ローカルのブランチを読む
    c=$(main_commit "$SEED_SHA" .kiro/specs/eta/spec.json '{"issue":45}\n') || die "ブランチのコミットを作れない"
    git -C "$MAIN_DIR" update-ref refs/heads/feat/extra-both "$c" || die "ローカルのブランチを作れない"
    c=$(main_commit "$SEED_SHA" .kiro/specs/theta/spec.json '{"issue":46}\n') || die "ブランチのコミットを作れない"
    git -C "$MAIN_DIR" update-ref refs/remotes/origin/feat/extra-both "$c" || die "リモートのブランチを作れない"
    put_issue 62 "" feat/extra-both ""
    out=$(busy "$WT2_DIR" --session s-me) || die "$out"
    [ "$out" = '{"active":[],"spec":[10,20,21,22,23,30,31,40,41,44,45]}' ] \
        || die "spec の番号が違う(期待は 10,20,21,22,23,30,31,40,41,44,45): $out"
}

t_busy_branch_missing() {
    local out
    put_issue 63 "" feat/extra-none ""
    out=$(busy "$MAIN_DIR" --session s-me) || die "$out"
    [ "$out" = '{"active":[],"spec":[10]}' ] || die "どこにも無いブランチの記録で spec が変わった: $out"
    [ ! -s "$WORK/busy-err.txt" ] || die "どこにも無いブランチで標準エラーに文が出た: $(cat "$WORK/busy-err.txt")"
}

t_busy_broken_spec() {
    local c out err
    mkdir -p "$WT_DIR/.kiro/specs/broken"
    printf '{"issue":' >"$WT_DIR/.kiro/specs/broken/spec.json"
    c=$(main_commit "$SEED_SHA" .kiro/specs/bad/spec.json 'not json\n') || die "origin/main を作れない"
    set_origin_main "$c"
    put_spec "$WT2_DIR" beta 20
    out=$(busy "$MAIN_DIR" --session s-me) || die "$out"
    [ "$out" = '{"active":[],"spec":[10,20]}' ] || die "壊れた spec.json があると読める spec の番号が出ない: $out"
    err=$(cat "$WORK/busy-err.txt")
    grep -F "$WT/.kiro/specs/broken/spec.json" "$WORK/busy-err.txt" | grep -q '^\[parallel\] 読めない spec\.json:' \
        || die "作業フォルダの壊れた spec.json の文が標準エラーに無い: $err"
    grep -F 'origin/main' "$WORK/busy-err.txt" | grep -F '.kiro/specs/bad/spec.json' \
        | grep -q '^\[parallel\] 読めない spec\.json:' \
        || die "origin/main の壊れた spec.json の文が標準エラーに無い: $err"
}

# shellcheck disable=SC2016 # $d などは pj に渡す perl の式の変数で、シェルの変数ではない
t_busy_no_write() {
    local out before after gone="$WORK/RepoGone"
    put_session s-wt "$WT" "$(fkey "$WT_DIR")" 300
    put_issue 42 "$WT" feat/wt s-wt
    # prune なら片付ける記録(作業フォルダが無くなったセッションとIssueの記録、ブランチがどこにも無い記録、
    # 600秒たった spec の予約)
    put_session s-gone "$gone" "$(fkey_path "$gone")" 200
    put_issue 52 "$gone" "" s-gone
    put_issue 63 "" feat/extra-none ""
    put_spec_reserve_raw old 1
    before=$(state_snapshot) || die "記録の置き場所を読めない"
    out=$(busy "$MAIN_DIR" --session s-me) || die "$out"
    [ "$(pj "$out" '$d->{active}')" = '[42]' ] || die "前提: active が 42 でない: $out"
    after=$(state_snapshot) || die "記録の置き場所を読めない"
    [ "$after" = "$before" ] || die "記録の置き場所のファイルの一覧か中身が変わった:
$(diff <(printf '%s\n' "$before") <(printf '%s\n' "$after"))"
    [ ! -s "$FAKE_DOCKER_LOG" ] || die "docker が呼ばれた: $(cat "$FAKE_DOCKER_LOG")"
}

t_busy_usage() {
    local out rc a
    put_session s-wt "$WT" "$(fkey "$WT_DIR")" 300
    put_issue 42 "$WT" feat/wt s-wt
    for a in 'extra' '--session' '--bogus' '--session s-me extra'; do
        # shellcheck disable=SC2086 # 空白で引数に分けて渡す
        out=$(ss "$MAIN_DIR" busy-issues $a 2>"$WORK/err.txt")
        rc=$?
        [ "$rc" = 64 ] || die "busy-issues $a の終了コードが64でない: $rc: $out $(cat "$WORK/err.txt")"
        [ -z "$out" ] || die "busy-issues $a が JSON を出した: $out"
    done
}

t_busy_lock_held() {
    local out rc
    put_session s-wt "$WT" "$(fkey "$WT_DIR")" 300
    put_issue 42 "$WT" feat/wt s-wt
    mkdir -p "$LOCK"
    out=$(PATH="$TMP_ROOT/fastsleep:$PATH" ss "$MAIN_DIR" busy-issues --session s-me 2>"$WORK/err.txt")
    rc=$?
    [ "$rc" = 69 ] || die "錠がほかに持たれたままなのに終了コードが69でない: $rc: $out $(cat "$WORK/err.txt")"
    [ -z "$out" ] || die "錠を取れないのに JSON を出した: $out"
    grep -q 'records.lock' "$WORK/err.txt" || die "標準エラーに錠の理由が無い: $(cat "$WORK/err.txt")"
    [ -d "$LOCK" ] || die "ほかのセッションの錠を消した"
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
run_test "capacity は返答している途中のセッションだけを数える(#520)" t_capacity_only_responding
run_test "folder_conflict と leftovers は返答しているかによらない(#520)" t_conflict_and_leftover_ignore_responding

echo "--- claim・spec-names"
run_test "claim がIssueの記録を書き、prune が残した記録は書き直し、ほかの作業フォルダとセッションの記録は終了コード1で断る" t_claim
run_test "claim は誤った呼び方で記録を書かない" t_claim_usage
run_test "spec-names がほかの worktree の spec の名前も出す" t_spec_names
run_test "check-start・claim・spec-names は docker を呼ばない" t_no_docker_in_check_start

echo "--- 記録の錠(session-overlap-guard 要件3.1)"
run_test "錠がほかに持たれたままなら check-start は終了コード69で終わり、その錠を消さない" t_lock_held_refused
run_test "60秒より古い錠は壊して取り直し、check-start は錠を返して終わる" t_lock_stale_broken
run_test "錠の中の調べが失敗したら、check-start は終了コード69で終わり、錠を残さない" t_lock_released_on_failure

echo "--- check-start の着手の予約(session-overlap-guard 要件1・要件3.1)"
run_test "何も見つからなければ、check-start はいまの作業フォルダとこのセッションの予約を書く" t_reserve_when_nothing_found
run_test "ほかの worktree の作業中のセッションの予約は started で出て、予約は書き換わらない" t_reserve_other_session_started
run_test "予約したセッションの記録が無ければ leftovers は空で、予約がこのセッションに書き換わる" t_reserve_closed_session_rewritten
run_test "同じセッションの打ち直しでは leftovers が空で、updated_at だけが変わる" t_reserve_same_session_rerun
run_test "予約の session_id が空なら started を出さない" t_reserve_empty_session_id_not_started
run_test "予約を書けなければ終了コード69で、錠が残らない" t_reserve_write_failure
run_test "2つの worktree から同時に check-start を呼ぶと、片方だけが空を返し、予約はそのセッションのもの(10回)" t_reserve_concurrent

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

echo "--- claim の断りと、claim と takeover の錠(session-overlap-guard 要件1.3・1.4)"
run_test "ほかの作業フォルダの予約があると claim は終了コード1で断り、記録を書き換えない" t_claim_refuses_other_reservation
run_test "自分の予約・記録が無いとき・prune が残した記録には claim が書く" t_claim_writes_own_or_free_record
run_test "このセッションのIDが空なら、いまの作業フォルダの記録は session_id が空でなくても claim が書く" t_claim_without_session_id_writes
run_test "end で予約したセッションの記録を消したあとの check-start は、予約をこのセッションに書き換え、先のセッションの claim は断られる" t_end_then_check_start_takes_reservation
run_test "錠がほかに持たれたままなら claim は終了コード69で終わり、記録を書かず、その錠を消さない" t_claim_lock_held_refused
run_test "takeover は錠の中で記録を書き直し、錠を取れなければ終了コード69で終わり、どの経路でも自分の錠を残さない" t_takeover_lock

echo "--- check-spec: 同じ spec を直しているほかのセッションの調べ(session-overlap-guard 要件2・要件3.1)"
run_test "ほかの worktree の作業中のセッションがコミットしていない spec の変更を持つと changes の要素が出る" t_check_spec_uncommitted
run_test "spec の変更をコミットしても、マージしていなければ要素が出る" t_check_spec_committed
run_test "古い main から作ったブランチで spec を変えていなければ、origin/main が spec を変えていても空" t_check_spec_old_base
run_test "spec のディレクトリを作業フォルダで消したときと、消してコミットしたとき(マージしていない)は要素が出る" t_check_spec_deleted_dir
run_test "変更を持つ worktree に作業中のセッションが無ければ空" t_check_spec_inactive_skipped
run_test "作業中のセッションが2つある worktree では要素が2つ出て、end のあとの check-spec はそのセッションの要素を出さない" t_check_spec_two_sessions_and_end
run_test "調べのあと、ほかの worktree の git status --porcelain の出力と索引と中身とブランチが変わっていない" t_check_spec_leaves_worktree
run_test "origin/main が無いと終了コード69" t_check_spec_no_origin_main
run_test "名前に大文字か / を含むときと、--issue が無いか数でないときは終了コード64" t_check_spec_usage
run_test "調べの git が失敗したら終了コード69で、作業フォルダと理由を出し、錠と一時的な索引を残さない" t_check_spec_git_failure
run_test "錠がほかに持たれたままなら check-spec は終了コード69で終わり、その錠を消さない" t_check_spec_lock_held

echo "--- check-spec の spec の予約(session-overlap-guard 要件2.5)"
run_test "ほかの作業中のセッションの600秒以内の予約は starting の要素になり、予約と変更の両方があれば changes" t_check_spec_reserve_starting
run_test "600秒より古い予約、作業中でないセッションや閉じたセッションの予約、作業フォルダの違う予約、壊れた予約、このセッション自身の予約は無視する" t_check_spec_reserve_ignored
run_test "conflicts が空のときだけ、このセッションの予約が書かれる" t_check_spec_reserve_written
run_test "予約を書けなければ終了コード69で、JSON を出さず、錠と一時的な索引を残さない" t_check_spec_reserve_write_failure
run_test "prune は600秒たった spec の予約と updated_at が負でない整数でない予約と読めない予約を消したと出し、新しい予約を残し、specs/ が無くても成り立つ" t_prune_spec_reservations
run_test "記録の錠がほかに持たれたままなら、prune は spec の予約を消さずに理由を標準エラーに出し、錠が返されたあとに消す" t_prune_spec_reservations_lock_held

echo "--- check-spec の判定: 変更のかたまりを M の行の位置で比べる(session-overlap-guard 要件2.1・2.4・3.1)"
run_test "マージしていない書き換えは要素が出て、squash でマージしたあとは隣の行が変わっても空。main が同じ行を別の中身に変えたときと、マージのあとにさらに書き換えたときは要素が出る" t_check_spec_squash_merged
run_test "行を消しただけ・先頭の行を消した・ファイルを空にした・行を足しただけは、マージしていなければ要素が出て、squash のあとは空" t_check_spec_delete_and_add_lines
run_test "コミットしていない新しいファイル・spec のディレクトリの削除(コミットしたものも)・バイナリのファイルは、マージしていなければ要素が出て、squash のあとは空" t_check_spec_files_and_dir
run_test "同じ中身の行が別の場所にあるか、別の場所で消されていても要素が出て、隣り合う空行の squash のあとは空" t_check_spec_same_content_elsewhere
run_test "置き換えた行の一部だけを main が変えたとき、行を足しただけの main のかたまり、diff.interHunkContext と GIT_DIFF_OPTS で判定が変わらず、足した行の squash のあとは前後の行が変わっても空" t_check_spec_hunk_positions
run_test "差分のかたまりの本文に前後の行があれば終了コード69で、作業フォルダとファイルの名前を出し、錠と一時的な索引を残さない" t_check_spec_context_line_refused

echo "--- busy-issues: spec があるIssueと、ほかのセッションが作業中のIssue(spec-need-triage 要件11.4)"
run_test "記録も spec も無いときは空の配列を出し、終了コード0で終わる" t_busy_empty
run_test "ほかの作業中のセッションが claim した記録と予約の記録は active に出て、このセッションの記録は出ない" t_busy_active_started
run_test "ブランチだけの記録、セッションを終えた記録、作業フォルダが無くなったセッションの記録、folder だけが一致する前のセッションの記録、handed_over_from の記録、開かれていない作業フォルダの記録は active に出ない" t_busy_active_excluded
run_test "本体と worktree の中身、origin/main にだけある、記録の branch のブランチ(ローカルを先に、無ければリモート)にだけある spec.json の issue と additional_issues が spec に出る" t_busy_spec_sources
run_test "記録の branch のブランチがローカルにもリモートにも無ければ飛ばし、終了コード0で終わる" t_busy_branch_missing
run_test "壊れた spec.json は飛ばして標準エラーに場所を出し、終了コード0で終わる" t_busy_broken_spec
run_test "busy-issues は記録の置き場所のファイルの一覧と中身を変えず、prune も docker も呼ばない" t_busy_no_write
run_test "余計な引数、--session の値が無い、知らないオプションは終了コード64で、JSON を出さない" t_busy_usage
run_test "錠がほかに持たれたままなら busy-issues は終了コード69で終わり、JSON を出さず、その錠を消さない" t_busy_lock_held

echo
echo "結果: 成功 $pass / 失敗 $fail"
[ "$fail" -eq 0 ]
